import Foundation
import UIKit
import CoreGraphics

/// 屏幕形态分类。
enum ClawdScreenKind: String, Equatable {
    /// 有灵动岛（iPhone 14 Pro 起）：`DynamicIsland` 那套布局会渲染。
    case dynamicIsland
    /// 有刘海、没有灵动岛（iPhone X 到 14 系列、iPhone 16e）。
    case notch
    /// 没有刘海也没有灵动岛（Home 键机型、iPad）。
    case plain
    /// 还没读到（扩展进程 / 窗口未就绪）。
    case unknown

    var label: String {
        switch self {
        case .dynamicIsland: return "灵动岛机型"
        case .notch: return "刘海机型"
        case .plain: return "无刘海机型"
        case .unknown: return "未探测"
        }
    }
}

/// 刘海几何。
///
/// **iOS 没有公开 API 能拿到刘海的矩形**（宽度、圆角、下沿都读不到）。能读到的只有：
/// - `UIWindow.safeAreaInsets.top`：屏幕顶部到安全区上沿的距离。刘海机型 44–50pt，
///   灵动岛机型 59pt 起，Home 键机型 20pt。注意它是「状态栏高度」，不是刘海高度。
/// - `UIWindow.bounds.size`：逻辑点尺寸；`UIScreen.nativeBounds.size`：物理像素尺寸。
/// - `sysctlbyname("hw.machine")`：机型标识（"iPhone14,5"），用于人工确认。
///
/// 所以「刘海栖木」不试图复刻刘海矩形，而是把桌宠的顶部压进 `[0, topInset]` 这条带子里：
/// 落在硬件挖孔范围内的像素会被物理遮住（挖孔不发光），露出带子两侧的部分 ——
/// 这就是「从刘海后面探出头」的全部原理，不需要任何私有 API。
struct NotchGeometry: Equatable {
    var kind: ClawdScreenKind
    /// 窗口的逻辑点尺寸（竖屏）。
    var size: CGSize
    /// 顶部安全区高度，即刘海带子的下沿。
    var topInset: CGFloat
    /// 底部安全区高度（Home 指示条）。
    var bottomInset: CGFloat
    var nativeSize: CGSize
    var scale: CGFloat
    var modelIdentifier: String

    static let unknown = NotchGeometry(
        kind: .unknown,
        size: .zero,
        topInset: 0,
        bottomInset: 0,
        nativeSize: .zero,
        scale: 0,
        modelIdentifier: ""
    )

    /// 栖木顶端要压进刘海带多深。取 topInset 的一半多一点：
    /// 足够让挖孔吃掉头顶，又不会把整只螃蟹藏没。
    /// 无刘海机型返回 0：那里没有挖孔可以借，压进状态栏只会和系统文字重叠。
    var peekDepth: CGFloat {
        switch kind {
        case .notch, .dynamicIsland:
            guard topInset > 0 else { return 12 }
            return min(max(topInset * 0.55, 16), 32)
        case .plain, .unknown:
            return 0
        }
    }

    /// `topInset` 是唯一稳定可用的度量，判定只看它，不看机型白名单。
    ///
    /// 59pt 起是灵动岛机型的实测安全区高度（14 Pro / 15 / 16 全系），
    /// 刘海机型落在 44–50pt，Home 键机型 20pt，iPad 24pt。
    static func classify(topInset: CGFloat) -> ClawdScreenKind {
        if topInset >= 59 { return .dynamicIsland }
        if topInset >= 44 { return .notch }
        if topInset > 0 { return .plain }
        return .unknown
    }

    var summary: String {
        var parts: [String] = [kind.label]
        if !modelIdentifier.isEmpty { parts.append(NotchProbe.displayName(for: modelIdentifier)) }
        if size != .zero {
            parts.append(String(format: "%.0f×%.0f pt", size.width, size.height))
        }
        if topInset > 0 {
            parts.append(String(format: "safeArea.top %.0f", topInset))
        }
        if nativeSize != .zero {
            parts.append(String(format: "%.0f×%.0f px @%.0fx", nativeSize.width, nativeSize.height, scale))
        }
        return parts.joined(separator: " · ")
    }
}

/// 读取当前窗口几何。只在 App target 里编译（Widget 扩展里 `UIApplication.shared` 不可用）。
enum NotchProbe {

    static func current() -> NotchGeometry {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        let window = scene?.windows.first { $0.isKeyWindow } ?? scene?.windows.first

        let size = window?.bounds.size ?? .zero
        let insets = window?.safeAreaInsets ?? .zero
        let native = scene?.screen.nativeBounds.size ?? .zero
        let scale = scene?.screen.scale ?? window?.traitCollection.displayScale ?? 0

        return NotchGeometry(
            kind: NotchGeometry.classify(topInset: insets.top),
            size: size,
            topInset: insets.top,
            bottomInset: insets.bottom,
            nativeSize: native,
            scale: scale,
            modelIdentifier: modelIdentifier()
        )
    }

    /// `sysctl hw.machine`，返回 "iPhone14,5" 这类标识。
    static func modelIdentifier() -> String {
        var size = 0
        guard sysctlbyname("hw.machine", nil, &size, nil, 0) == 0, size > 0 else { return "" }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.machine", &buffer, &size, nil, 0) == 0 else { return "" }
        return String(cString: buffer)
    }

    /// 机型标识 → 市场名。**只用于显示**，判定不依赖这张表；
    /// 表里没有的（新机型、iPad、模拟器）原样返回标识本身。
    static func displayName(for identifier: String) -> String {
        switch identifier {
        case "iPhone10,3", "iPhone10,6": return "iPhone X"
        case "iPhone11,2": return "iPhone XS"
        case "iPhone11,4", "iPhone11,6": return "iPhone XS Max"
        case "iPhone11,8": return "iPhone XR"
        case "iPhone12,1": return "iPhone 11"
        case "iPhone12,3": return "iPhone 11 Pro"
        case "iPhone12,5": return "iPhone 11 Pro Max"
        case "iPhone13,1": return "iPhone 12 mini"
        case "iPhone13,2": return "iPhone 12"
        case "iPhone13,3": return "iPhone 12 Pro"
        case "iPhone13,4": return "iPhone 12 Pro Max"
        case "iPhone14,2": return "iPhone 13 Pro"
        case "iPhone14,3": return "iPhone 13 Pro Max"
        case "iPhone14,4": return "iPhone 13 mini"
        case "iPhone14,5": return "iPhone 13"
        case "iPhone14,7": return "iPhone 14"
        case "iPhone14,8": return "iPhone 14 Plus"
        case "iPhone15,2": return "iPhone 14 Pro"
        case "iPhone15,3": return "iPhone 14 Pro Max"
        case "iPhone15,4": return "iPhone 15"
        case "iPhone15,5": return "iPhone 15 Plus"
        case "iPhone16,1": return "iPhone 15 Pro"
        case "iPhone16,2": return "iPhone 15 Pro Max"
        case "iPhone17,1": return "iPhone 16 Pro"
        case "iPhone17,2": return "iPhone 16 Pro Max"
        case "iPhone17,3": return "iPhone 16"
        case "iPhone17,4": return "iPhone 16 Plus"
        case "iPhone17,5": return "iPhone 16e"
        default: return identifier
        }
    }
}
