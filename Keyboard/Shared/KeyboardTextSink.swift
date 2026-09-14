import UIKit

/// 键盘视图只通过这个协议跟外面说话。
/// 所以同一份视图既能被键盘扩展用真实 textDocumentProxy 驱动，
/// 也能被宿主 App 的预览页用假实现驱动 —— 后者是 CI 能截图的前提。
protocol KeyboardTextSink: AnyObject {
    func insert(_ text: String)
    func backspace()
    /// 回车键该显示什么字（发送 / 搜索 / 换行…）
    var returnKeyTitle: String { get }
    /// 键盘该用深色还是浅色
    var isDarkAppearance: Bool { get }
}

/// 把 UIInputViewController.textDocumentProxy 包一层。
/// proxy 要强引用：系统给的这个对象可能会被换掉，弱引用会直接空掉。
final class ProxyTextSink: KeyboardTextSink {
    private let proxy: UITextDocumentProxy

    init(proxy: UITextDocumentProxy) {
        self.proxy = proxy
    }

    func insert(_ text: String) { proxy.insertText(text) }

    func backspace() { proxy.deleteBackward() }

    var returnKeyTitle: String {
        switch proxy.returnKeyType {
        case .send: return "发送"
        case .search: return "搜索"
        case .go: return "前往"
        case .done: return "完成"
        case .next: return "下一项"
        case .join: return "加入"
        case .route: return "路线"
        case .emergencyCall: return "紧急呼叫"
        default: return "换行"
        }
    }

    var isDarkAppearance: Bool {
        switch proxy.keyboardAppearance {
        case .dark: return true
        case .light: return false
        default: return UITraitCollection.current.userInterfaceStyle == .dark
        }
    }
}
