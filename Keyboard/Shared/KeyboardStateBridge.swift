import Foundation

/// 键盘扩展 → 宿主 App 的状态桥。
///
/// 走 App Group 的 UserDefaults：宿主 App 把 Claude Code 的状态写进去，
/// 键盘在出现时读一次。没开「完全访问」的扩展读不到共享容器，
/// 这时拿到的永远是 nil —— 那就只有当打字反应的 Clawd，其它功能不受影响。
final class KeyboardStateBridge {

    static let shared = KeyboardStateBridge()

    private static let appGroup = "group.com.clawd.island.clawd"
    private static let stateKey = "clawd.keyboard.state"

    private init() {}

    /// 宿主 App 写状态：working / waiting / error / idle / nil
    func publish(_ state: String?) {
        guard let defaults = UserDefaults(suiteName: Self.appGroup) else { return }
        if let state {
            defaults.set(state, forKey: Self.stateKey)
        } else {
            defaults.removeObject(forKey: Self.stateKey)
        }
        defaults.synchronize()
    }

    /// 键盘读状态，映射成 Clawd 的姿势
    func currentMood() -> PetStripView.Mood? {
        guard let defaults = UserDefaults(suiteName: Self.appGroup),
              let raw = defaults.string(forKey: Self.stateKey) else { return nil }
        switch raw {
        case "working": return .typing
        case "waiting": return .alert
        case "error":   return .alert
        case "idle":    return .idle
        default:        return nil
        }
    }
}
