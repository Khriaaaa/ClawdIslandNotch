import AppIntents
import ActivityKit
import WidgetKit
import Foundation

/// iOS 17 交互按钮：让用户直接在灵动岛 / 锁屏 / 主屏小组件上点一下。
///
/// 用 `LiveActivityIntent`（它继承 AppIntent）：这样按钮出现在 Live Activity 里时
/// 能在 App 进程内执行，不需要先把 App 拉到前台。主屏小组件的 `Button(intent:)`
/// 同样接受它。
///
/// 执行内容写在 App Group 里（Widget 扩展与 App 共享），并顺手刷新已在运行的
/// Live Activity 和小组件时间线。App 回到前台时再读一次存储（见 ClawdIslandApp）。
struct WakeClawdIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "唤醒 Clawd"
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        ClawdIntentActions.apply(.idle)
        return .result()
    }
}

struct SleepClawdIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "让它睡"
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        ClawdIntentActions.apply(.sleeping)
        return .result()
    }
}

/// 按钮的真正落点：不依赖 App 是否在运行。
enum ClawdIntentActions {

    static func apply(_ state: ClawdState) {
        let now = Date()

        var snapshot = ClawdStore.loadSnapshot()
        snapshot.stateRaw = state.rawValue
        snapshot.stateTitle = state.title
        snapshot.imageName = state.imageName
        snapshot.islandGlyph = state.islandGlyph
        snapshot.detail = "手动 · \(state.title)"
        snapshot.updatedAt = now
        if snapshot.sessionStartedAt == Date(timeIntervalSince1970: 0) {
            snapshot.sessionStartedAt = now
        }
        ClawdStore.save(snapshot)
        ClawdStore.append(ClawdEvent.manual(state: state, at: now))

        WidgetCenter.shared.reloadAllTimelines()

        // 尽量同步已在运行的实时活动；扩展进程里拿不到活动列表时会自然跳过。
        Task {
            await refreshLiveActivities(snapshot)
        }
    }

    private static func refreshLiveActivities(_ snapshot: ClawdSnapshot) async {
        let content = ActivityContent(
            state: ClawdAttributes.ContentState(
                stateRaw: snapshot.stateRaw,
                stateTitle: snapshot.stateTitle,
                imageName: snapshot.imageName,
                sessionTitle: snapshot.sessionTitle,
                agentId: snapshot.agentId,
                detail: snapshot.detail,
                updatedAt: snapshot.updatedAt
            ),
            staleDate: Date().addingTimeInterval(8 * 3600)
        )
        for activity in Activity<ClawdAttributes>.activities {
            await activity.update(content)
        }
    }
}
