import Foundation
import ActivityKit
import WidgetKit

/// 管理 Live Activity（灵动岛 + 锁屏）的生命周期。
///
/// 关键平台事实（BRIEF 第五节）：
/// - Live Activity 有 8 小时硬上限，到点系统会把它变成 ended。这里在接近上限时
///   主动 end 再 start，避免用户看到"过期不更新"。
/// - 更新频率有限流预算，所以只在状态真的变化时 update，不写高频刷新。
/// - 交互按钮依赖 iOS 17 的 AppIntent（见 Widget/ClawdIntents.swift）。
@MainActor
final class ActivityController: ObservableObject {

    /// 系统规定的 8 小时上限。
    static let systemLimit: TimeInterval = 8 * 3600
    /// 提前到这个点就重建，留足余量。
    static let restartBudget: TimeInterval = 7 * 3600

    @Published private(set) var isActive = false
    @Published private(set) var lastError: String?

    private var activity: Activity<ClawdAttributes>?
    private var startedAt: Date?

    /// 构造 ContentState。所有字段都来自 ClawdSnapshot，保证 App 与 Widget 显示一致。
    private func contentState(from snapshot: ClawdSnapshot) -> ClawdAttributes.ContentState {
        ClawdAttributes.ContentState(
            stateRaw: snapshot.stateRaw,
            stateTitle: snapshot.stateTitle,
            imageName: snapshot.imageName,
            sessionTitle: snapshot.sessionTitle,
            agentId: snapshot.agentId,
            detail: snapshot.detail,
            updatedAt: snapshot.updatedAt
        )
    }

    /// 如果系统里已经有一个（比如 App 被杀掉后残留的），先接管过来。
    func adoptExistingActivity() {
        guard activity == nil else { return }
        guard let existing = Activity<ClawdAttributes>.activities.first else { return }
        activity = existing
        startedAt = Date()
        isActive = existing.activityState == .active
    }

    // MARK: - start

    func start(snapshot: ClawdSnapshot, sessionId: String) {
        let content = ActivityContent(
            state: contentState(from: snapshot),
            staleDate: Date().addingTimeInterval(Self.systemLimit)
        )
        do {
            let activity = try Activity.request(
                attributes: ClawdAttributes(sessionId: sessionId.isEmpty ? "clawd:default" : sessionId),
                content: content,
                pushType: nil
            )
            self.activity = activity
            self.startedAt = Date()
            self.isActive = true
            self.lastError = nil
            Diag.appliedLiveActivity(snapshot.stateRaw)
        } catch {
            self.isActive = false
            self.lastError = "开启实时活动失败：\(error.localizedDescription)"
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - update

    /// 状态变化时调用。内部处理：过期重建、已结束重建、正常 update。
    func update(snapshot: ClawdSnapshot, sessionId: String) {
        adoptExistingActivity()

        guard let activity = activity else {
            // 之前没开就顺手开一个；这是"自动开实时活动"的兜底。
            start(snapshot: snapshot, sessionId: sessionId)
            return
        }

        // 系统可能在 App 挂起期间把活动结束掉（超时 / 用户左滑关掉）。
        if activity.activityState != .active {
            self.activity = nil
            self.startedAt = nil
            start(snapshot: snapshot, sessionId: sessionId)
            return
        }

        // 8 小时上限：到点前重建。
        if let startedAt = startedAt, Date().timeIntervalSince(startedAt) >= Self.restartBudget {
            Task { [weak self] in
                await self?.replace(activity: activity, snapshot: snapshot, sessionId: sessionId)
            }
            return
        }

        let content = ActivityContent(
            state: contentState(from: snapshot),
            staleDate: Date().addingTimeInterval(Self.systemLimit)
        )
        let stateRaw = snapshot.stateRaw
        Task {
            await activity.update(content)
            // 收条只到「HTTP 进了这个 App」为止；岛上有没有被更新是另一步。
            // 这一行证明 ActivityKit 收下了 update。
            Diag.appliedLiveActivity(stateRaw)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// 到 8 小时上限：先 end 旧的，再 start 新的。
    private func replace(activity: Activity<ClawdAttributes>, snapshot: ClawdSnapshot, sessionId: String) async {
        await activity.end(nil, dismissalPolicy: .immediate)
        self.activity = nil
        self.startedAt = nil
        self.isActive = false
        start(snapshot: snapshot, sessionId: sessionId)
    }

    // MARK: - end

    func end(snapshot: ClawdSnapshot?) {
        guard let activity = activity else {
            isActive = false
            return
        }
        let content = snapshot.map { ActivityContent(state: contentState(from: $0), staleDate: nil) }
        Task {
            await activity.end(content, dismissalPolicy: .immediate)
        }
        self.activity = nil
        self.startedAt = nil
        self.isActive = false
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// 刷新小组件（状态变了但没开实时活动时也要刷新）。
    func refreshWidgets() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}
