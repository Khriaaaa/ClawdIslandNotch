import Foundation

/// 本地作息引擎 —— claw 自己过日子，不再等外部事件喂状态。
///
/// 方向（2026-09-15 定）：
/// - 打字时跟着敲：由输入事件驱动，不在这里（见 `PetStripView.petDidType()`）
/// - 不打字时按**真实时钟**作息：白天活跃闲逛，深夜自动睡，中间随机插入玩耍
///
/// 纯 Foundation，不引 UIKit / ActivityKit，所以键盘扩展也能编这份文件
/// （键盘 target 只挂 `ClawdState.swift` + `ClawdStore.swift`，本文件要一起加进 `project.yml`）。
enum ClawdBiorhythm {

    // MARK: - 时段

    /// 一天里的六个时段。边界按本地时间切，早上 6:30 起算。
    enum Shift: String, CaseIterable {
        case waking     // 06:30–09:00 刚醒，慢慢来
        case daytime    // 09:00–12:00 / 14:00–18:00 活跃
        case siesta     // 12:00–14:00 午间打盹
        case evening    // 18:00–22:30 傍晚，慢下来
        case bedtime    // 22:30–00:30 准备睡
        case deepNight  // 00:30–06:30 熟睡

        /// 面板 / 设置页显示用
        var title: String {
            switch self {
            case .waking:    return "刚醒"
            case .daytime:   return "白天活跃"
            case .siesta:    return "午间打盹"
            case .evening:   return "傍晚"
            case .bedtime:   return "准备睡"
            case .deepNight: return "深夜熟睡"
            }
        }

        /// 这个时段覆盖的钟点（展示用）
        var hours: String {
            switch self {
            case .waking:    return "06:30 – 09:00"
            case .daytime:   return "09:00 – 12:00 / 14:00 – 18:00"
            case .siesta:    return "12:00 – 14:00"
            case .evening:   return "18:00 – 22:30"
            case .bedtime:   return "22:30 – 00:30"
            case .deepNight: return "00:30 – 06:30"
            }
        }

        /// 这段时间 claw 大概在干嘛（展示用）
        var summary: String {
            switch self {
            case .waking:    return "刚醒，打哈欠，偶尔又趴回去"
            case .daytime:   return "闲逛为主，时不时起来玩一会儿"
            case .siesta:    return "午间多打盹"
            case .evening:   return "慢下来，逛一逛、打会儿盹"
            case .bedtime:   return "犯困，倒下就睡"
            case .deepNight: return "熟睡，偶尔起来溜达一下"
            }
        }
    }

    /// 某个时刻落在哪个时段。
    static func shift(at date: Date, calendar: Calendar = .current) -> Shift {
        let comps = calendar.dateComponents([.hour, .minute], from: date)
        let t = Double(comps.hour ?? 0) + Double(comps.minute ?? 0) / 60

        switch t {
        case 6.5..<9:   return .waking
        case 9..<12:    return .daytime
        case 12..<14:   return .siesta
        case 14..<18:   return .daytime
        case 18..<22.5: return .evening
        case 22.5..<24: return .bedtime
        default:        return .deepNight   // 00:00–06:30
        }
    }

    // MARK: - 节拍

    /// 一个节拍：接下来演什么状态、演多久。权重不必归一，掷骰子时按总和算。
    struct Beat: Equatable {
        let state: ClawdState
        let weight: Double
        let minSeconds: TimeInterval
        let maxSeconds: TimeInterval
    }

    /// 每个时段的候选节拍。
    ///
    /// 权重是相对的「这件事多久发生一次」，不是概率。深夜那两档（roam / juggling）
    /// 就是「偶尔起来溜达、更偶尔起来玩一下」—— 权重压得很低，睡还是主基调。
    static func beats(for shift: Shift) -> [Beat] {
        switch shift {
        case .waking:
            return [
                Beat(state: .yawning, weight: 2, minSeconds: 4, maxSeconds: 8),
                Beat(state: .idle,    weight: 4, minSeconds: 5, maxSeconds: 14),
                Beat(state: .roam,    weight: 3, minSeconds: 4, maxSeconds: 10),
                Beat(state: .dozing,  weight: 2, minSeconds: 20, maxSeconds: 60),
            ]

        case .daytime:
            return [
                Beat(state: .idle,     weight: 3, minSeconds: 6, maxSeconds: 20),
                Beat(state: .roam,     weight: 5, minSeconds: 4, maxSeconds: 12),
                Beat(state: .juggling, weight: 2, minSeconds: 3, maxSeconds: 7),   // 起来玩
                Beat(state: .dozing,   weight: 1, minSeconds: 15, maxSeconds: 45),
            ]

        case .siesta:
            return [
                Beat(state: .dozing,  weight: 4, minSeconds: 40, maxSeconds: 150),
                Beat(state: .idle,    weight: 2, minSeconds: 6, maxSeconds: 16),
                Beat(state: .yawning, weight: 2, minSeconds: 4, maxSeconds: 9),
                Beat(state: .roam,    weight: 1, minSeconds: 4, maxSeconds: 10),
            ]

        case .evening:
            return [
                Beat(state: .idle,     weight: 3, minSeconds: 8, maxSeconds: 22),
                Beat(state: .roam,     weight: 3, minSeconds: 4, maxSeconds: 12),
                Beat(state: .dozing,   weight: 2, minSeconds: 25, maxSeconds: 70),
                Beat(state: .juggling, weight: 1, minSeconds: 3, maxSeconds: 7),
            ]

        case .bedtime:
            return [
                Beat(state: .yawning,    weight: 3, minSeconds: 4, maxSeconds: 9),
                Beat(state: .dozing,     weight: 3, minSeconds: 30, maxSeconds: 90),
                Beat(state: .idle,       weight: 2, minSeconds: 6, maxSeconds: 16),
                Beat(state: .collapsing, weight: 1, minSeconds: 5, maxSeconds: 10),
                Beat(state: .roam,       weight: 1, minSeconds: 4, maxSeconds: 10),
            ]

        case .deepNight:
            return [
                Beat(state: .sleeping, weight: 10, minSeconds: 180, maxSeconds: 600),
                Beat(state: .dozing,   weight: 3,  minSeconds: 30, maxSeconds: 90),
                Beat(state: .roam,     weight: 1,  minSeconds: 4, maxSeconds: 10),   // 偶尔起来溜达
                Beat(state: .juggling, weight: 0.5, minSeconds: 3, maxSeconds: 6),   // 更偶尔：起来玩
            ]
        }
    }

    /// 掷出来的一个节拍：演哪个状态、演多久。
    struct Slot: Equatable {
        let state: ClawdState
        let duration: TimeInterval
    }

    /// 掷下一个节拍：按当前时段的权重挑状态，再在它的时长区间里取一个随机值。
    ///
    /// - Parameter minimumDuration: 下限。锁屏 / 灵动岛那类面一条通知就是一次系统预算，
    ///   换个状态不要换得太勤，调用方按面的能力抬高这个值。
    static func nextSlot(at date: Date = Date(),
                         calendar: Calendar = .current,
                         minimumDuration: TimeInterval = 0) -> Slot {
        let pool = beats(for: shift(at: date, calendar: calendar))
        let total = pool.reduce(0) { $0 + $1.weight }
        var roll = Double.random(in: 0..<max(total, 0.0001))

        var picked = pool[pool.count - 1]
        for beat in pool {
            if roll < beat.weight {
                picked = beat
                break
            }
            roll -= beat.weight
        }

        let lo = min(picked.minSeconds, picked.maxSeconds)
        let hi = max(picked.minSeconds, picked.maxSeconds)
        let rolled = Double.random(in: lo...max(lo, hi))
        return Slot(state: picked.state, duration: max(rolled, minimumDuration))
    }
}
