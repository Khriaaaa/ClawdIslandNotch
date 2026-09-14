import Foundation

/// 键盘扩展 → 宿主 App 的状态桥。
///
/// 不自己存一份：直接读 `ClawdStore` 写进 App Group 的快照（`clawd.snapshot.v1`），
/// 跟锁屏小组件读的是同一份数据，值域也就不会跟 `ClawdState` 跑偏。
///
/// 没开「完全访问」的键盘扩展读不到共享容器，`loadSnapshot()` 会吐 `.empty`
/// （`updatedAt == 1970`），这里就返回 nil —— 那 Clawd 只有当打字反应，其它功能不受影响。
enum KeyboardStateBridge {

    /// 快照超过这个岁数就不认了，免得一小时前的「working」还挂在键盘上
    private static let staleAfter: TimeInterval = 600

    /// 宿主 App 最近一次推送的状态，读不到就给 nil
    static func currentMood() -> PetStripView.Mood? {
        let snapshot = ClawdStore.loadSnapshot()
        guard snapshot.updatedAt.timeIntervalSince1970 > 0 else { return nil }
        guard Date().timeIntervalSince(snapshot.updatedAt) < staleAfter else { return .idle }
        return mood(for: snapshot.state)
    }

    /// ClawdState 有 16 个值，活动条只有 6 个姿势，这里做归并
    static func mood(for state: ClawdState) -> PetStripView.Mood {
        switch state {
        case .working, .juggling, .sweeping, .carrying, .thinking:
            return .typing
        case .attention, .error, .notification:
            return .alert
        case .sleeping, .dozing, .yawning:
            return .sleeping
        case .idle, .roam, .waking, .collapsing, .dizzy:
            return .idle
        }
    }
}
