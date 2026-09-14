import Foundation

/// 深链：从锁屏小组件 / 实时活动点进来，直接落到 App 的「刘海」页。
///
/// scheme 在 `project.yml` 的 `CFBundleURLTypes` 里登记，App 侧用 `.onOpenURL` 接。
/// 放在 `Shared/` 是因为 App 与 Widget 扩展两边都要用（两个 target 都编译这个目录）。
enum NotchDeepLink {
    static let scheme = "clawdisland"
    static let url = URL(string: "clawdisland://notch")
}
