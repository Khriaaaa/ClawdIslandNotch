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
        // 过期要说「不知道」，不能回 .idle：活动条只要收到非 nil 就交给外部接管
        // （PetStripView.tick 里 `if let external`），回 .idle 等于把打字、走动、
        // 45 秒睡着这些本地行为永久钉死 —— 开过一次 App 之后就再也不动了。
        guard Date().timeIntervalSince(snapshot.updatedAt) < staleAfter else { return nil }
        return mood(for: snapshot.state)
    }

    /// ClawdState 有 16 个值，活动条只有 6 个姿势，这里做归并。
    /// 静息那一档返回 nil：那些姿势交给活动条自己演（打字、走动、睡着），
    /// App 侧没有值得抢镜的信息时不该去接管它。
    static func mood(for state: ClawdState) -> PetStripView.Mood? {
        switch state {
        case .working, .juggling, .sweeping, .carrying, .thinking:
            return .typing
        case .attention, .error, .notification:
            return .alert
        case .sleeping, .dozing, .yawning:
            return .sleeping
        case .idle, .roam, .waking, .collapsing, .dizzy:
            return nil
        }
    }
}
