import Foundation

/// Clawd 的状态全集。
///
/// 依据：
/// - 状态名取自 reference/clawd-on-desk-android/assets/theme.json 的 `states` 键（16 个）。
/// - 事件 → 状态映射取自 reference/clawd-on-desk/agents/hermes.js 的 `eventMap`，
///   并以 reference/.../openclaw-plugin/index.js 的 handleHook() 为准做了补全：
///     SessionStart      → idle
///     UserPromptSubmit  → thinking
///     PreToolUse        → working
///     PostToolUse       → working
///     PostToolUseFailure→ error
///     Stop              → attention
///     StopFailure       → error
///     SessionEnd        → sleeping
///     PreCompact        → sweeping
///     PostCompact       → attention
///     Notification      → notification
///     SubagentStart     → juggling
///     SubagentStop      → working
///     WorktreeCreate    → carrying
///
/// 优先级取自 reference/clawd-on-desk/src/state-priority.js 的 STATE_PRIORITY。
/// 最小展示时长取自 theme.json 的 `timings.minDisplay`（单位毫秒）。
enum ClawdState: String, CaseIterable, Codable, Identifiable, Hashable {
    case idle
    case roam
    case yawning
    case dozing
    case collapsing
    case thinking
    case working
    case juggling
    case sweeping
    case error
    case attention
    case notification
    case carrying
    case sleeping
    case waking
    case dizzy

    var id: String { rawValue }

    /// 面板/小组件里显示的中文名。
    var title: String {
        switch self {
        case .idle: return "待命"
        case .roam: return "闲逛"
        case .yawning: return "打哈欠"
        case .dozing: return "打盹"
        case .collapsing: return "倒下就睡"
        case .thinking: return "思考中"
        case .working: return "干活中"
        case .juggling: return "多线程"
        case .sweeping: return "整理上下文"
        case .error: return "出错了"
        case .attention: return "等你"
        case .notification: return "有通知"
        case .carrying: return "搬运中"
        case .sleeping: return "睡觉"
        case .waking: return "刚醒"
        case .dizzy: return "晕了"
        }
    }

    /// 大图（主屏小组件 / 锁屏 / 灵动岛展开态）。名字对应 Assets.xcassets 里的 imageset。
    var imageName: String { "clawd-\(rawValue)" }

    /// 小图（灵动岛 compact / minimal）。优先用 reference 里现成的 mini 素材，
    /// 没有对应 mini 的状态就退回同名的迷你映射。
    ///
    /// 注意：这些资源是栅格 PNG，不是矢量图。`Contents.json` 必须显式写
    /// `scale`，否则 Xcode 按单倍图算，900px 就成了 900pt，超过灵动岛各面的
    /// 图片分辨率预算，系统会把那块换成灰方块（不报错、不崩，最难查）。
    /// 各面预算见 `ClawdGlyph` 的注释。
    var islandGlyph: String {
        switch self {
        case .idle: return "clawd-mini-idle"
        case .roam: return "clawd-mini-crabwalk"
        case .yawning: return "clawd-mini-sleep"
        case .dozing: return "clawd-mini-sleep"
        case .collapsing: return "clawd-mini-enter-sleep"
        case .thinking: return "clawd-mini-peek"
        case .working: return "clawd-mini-typing"
        case .juggling: return "clawd-mini-typing"
        case .sweeping: return "clawd-mini-typing"
        case .error: return "clawd-mini-alert"
        case .attention: return "clawd-mini-happy"
        case .notification: return "clawd-mini-alert"
        case .carrying: return "clawd-mini-crabwalk"
        case .sleeping: return "clawd-mini-sleep"
        case .waking: return "clawd-mini-enter"
        case .dizzy: return "clawd-mini-alert"
        }
    }

    /// 系统图标兜底。资源缺失时用得上，也用于设置页/按钮。
    var symbolName: String {
        switch self {
        case .idle: return "tortoise"
        case .roam: return "figure.walk"
        case .yawning: return "zzz"
        case .dozing: return "zzz"
        case .collapsing: return "bed.double"
        case .thinking: return "brain"
        case .working: return "hammer"
        case .juggling: return "arrow.triangle.branch"
        case .sweeping: return "wind"
        case .error: return "exclamationmark.triangle"
        case .attention: return "hand.raised"
        case .notification: return "bell"
        case .carrying: return "shippingbox"
        case .sleeping: return "moon.zzz"
        case .waking: return "sunrise"
        case .dizzy: return "sparkles"
        }
    }

    /// 优先级，数值越大越"抢镜"。来自 state-priority.js。
    var priority: Int {
        switch self {
        case .error: return 8
        case .notification: return 7
        case .sweeping: return 6
        case .attention: return 5
        case .carrying, .juggling: return 4
        case .working: return 3
        case .thinking: return 2
        case .idle, .roam: return 1
        case .sleeping: return 0
        case .yawning, .dozing, .collapsing, .waking, .dizzy: return 1
        }
    }

    /// 一次性状态（会自己退回去）。来自 state-priority.js 的 ONESHOT_STATES。
    var isOneShot: Bool {
        switch self {
        case .attention, .error, .sweeping, .notification, .carrying: return true
        default: return false
        }
    }

    /// 最小展示时长（秒）。来自 theme.json timings.minDisplay。
    /// 不在表里的状态返回 0（可直接被覆盖）。
    var minDisplaySeconds: TimeInterval {
        switch self {
        case .attention: return 4.0
        case .error: return 5.0
        case .sweeping: return 5.5
        case .notification: return 5.0
        case .carrying: return 3.0
        case .working: return 1.0
        case .thinking: return 1.0
        default: return 0
        }
    }

    /// 自动回落时长（秒）。来自 theme.json timings.autoReturn；nil 表示不自动回落。
    var autoReturnSeconds: TimeInterval? {
        switch self {
        case .attention: return 4.0
        case .error: return 5.0
        case .sweeping: return 300.0
        case .notification: return 5.0
        case .carrying: return 3.0
        case .dizzy: return 6.0
        default: return nil
        }
    }

    // MARK: - 事件名 / JSON 映射

    /// 事件名 → 状态。事件名是 PascalCase（Claude Code hook 风格）。
    static func from(event: String) -> ClawdState? {
        switch event {
        case "SessionStart": return .idle
        case "UserPromptSubmit": return .thinking
        case "PreToolUse": return .working
        case "PostToolUse": return .working
        case "PostToolUseFailure": return .error
        case "Stop": return .attention
        case "StopFailure": return .error
        case "SessionEnd": return .sleeping
        case "PreCompact": return .sweeping
        case "PostCompact": return .attention
        case "Notification", "Elicitation": return .notification
        case "SubagentStart": return .juggling
        case "SubagentStop": return .working
        case "WorktreeCreate": return .carrying
        default: return nil
        }
    }

    /// 从 payload 里解析状态：优先用显式的 state 字段（协议里 state 必填），
    /// 认不出来再退回 event 映射；都没有就当作 idle。
    static func resolve(stateRaw: String?, event: String?) -> ClawdState {
        if let raw = stateRaw, let state = ClawdState(rawValue: raw.lowercased()) {
            return state
        }
        if let event = event, let mapped = ClawdState.from(event: event) {
            return mapped
        }
        return .idle
    }
}

// MARK: - 状态切换的展示策略

/// 决定「新状态要不要立刻顶掉当前状态」。
///
/// 规则（对应 reference 行为）：
/// 1. 当前状态是一次性状态且还在 minDisplay 窗口内，新状态优先级不高于它 → 忽略。
/// 2. 否则接受新状态。
///
/// 多会话并发取状态的做法（theme.json 的 workingTiers 思路）：
/// 外部代理本来就是「每个会话各自 POST」，桌宠这一侧只维护一个当前展示状态，
/// 按 STATE_PRIORITY 取最高优先级；同为 working 的并发数用
/// `ClawdState.workingImageName(activeSessions:)` 换成 building / juggling / typing 三档素材。
struct StateGate {
    private(set) var current: ClawdState
    private(set) var changedAt: Date
    /// 被 gate 挡下来的新状态，等当前状态过了 minDisplay 后再补上。
    private(set) var pending: (state: ClawdState, at: Date)?

    init(initial: ClawdState = .sleeping, now: Date = Date()) {
        self.current = initial
        self.changedAt = now
    }

    /// 返回 true 表示当前展示状态应该变成 newState。
    mutating func accept(_ newState: ClawdState, now: Date = Date()) -> Bool {
        guard newState != current else { return false }

        // 新状态优先级更高（例如 error），永远立刻接受。
        if newState.priority > current.priority {
            current = newState
            changedAt = now
            pending = nil
            return true
        }

        let elapsed = now.timeIntervalSince(changedAt)
        if elapsed < current.minDisplaySeconds {
            // 还在最小展示窗口内。记下 pending，等窗口过去后再补。
            if pending == nil || newState.priority >= (pending?.state.priority ?? -1) {
                pending = (newState, now)
            }
            return false
        }

        current = newState
        changedAt = now
        pending = nil
        return true
    }

    /// 一次性状态到点后回落。返回应该切换到的状态，nil 表示不用动。
    mutating func fallback(now: Date = Date()) -> ClawdState? {
        let elapsed = now.timeIntervalSince(changedAt)
        if let limit = current.autoReturnSeconds, elapsed >= limit {
            let next = ClawdState.idle
            current = next
            changedAt = now
            pending = nil
            return next
        }
        if let pending = pending, elapsed >= current.minDisplaySeconds {
            let next = pending.state
            self.pending = nil
            current = next
            changedAt = now
            return next
        }
        return nil
    }
}

extension ClawdState {
    /// workingTiers 对应的资源名：并发会话数越多，画面越"壮观"。
    static func workingImageName(activeSessions: Int) -> String {
        if activeSessions >= 3 { return "clawd-working-building" }
        if activeSessions >= 2 { return "clawd-working-juggling" }
        return "clawd-working"
    }
}
