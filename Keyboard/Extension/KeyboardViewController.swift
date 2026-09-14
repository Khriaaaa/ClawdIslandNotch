import UIKit

/// 输入法控制器。只干三件事：把 textDocumentProxy 接到键盘视图上、
/// 管住高度（含底部安全区）、把系统要求的输入法切换接上。
/// 所有 UI 都在 ClawdKeyboardView 里，那份代码同时被宿主 App 的预览页复用。
///
/// 这里**不读任何外部状态**：Clawd 的作息由 `ClawdBiorhythm` 按真实时钟自己走
/// （见 `PetStripView.tick()`），键盘控制器只负责把输入接进来。
final class KeyboardViewController: UIInputViewController, UIInputViewAudioFeedback {

    private var keyboard: ClawdKeyboardView?
    private var heightConstraint: NSLayoutConstraint?

    /// 有了这个 + 返回 true，UIDevice.playInputClick() 才有声音
    var enableInputClicksWhenVisible: Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()

        let kb = ClawdKeyboardView(frame: .zero)
        kb.translatesAutoresizingMaskIntoConstraints = false
        kb.onNextKeyboard = { [weak self] in self?.advanceToNextInputMode() }
        kb.onDismiss = { [weak self] in self?.dismissKeyboard() }
        kb.onKeySound = { UIDevice.current.playInputClick() }
        kb.needsInputModeSwitchKey = needsInputModeSwitchKey
        view.addSubview(kb)

        NSLayoutConstraint.activate([
            kb.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            kb.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            kb.topAnchor.constraint(equalTo: view.topAnchor),
            kb.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        keyboard = kb

        // 键盘高度自己定，不受系统键盘限制。优先级压到 999，别跟系统的约束硬顶。
        // 底下还要加一条安全区的高度：键盘铺到屏幕底，home indicator 那条横杠
        // 会盖住第四行按键。
        let height = view.heightAnchor.constraint(equalToConstant: KeyboardMetrics.totalHeight)
        height.priority = UILayoutPriority(999)
        height.isActive = true
        heightConstraint = height
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        keyboard?.needsInputModeSwitchKey = needsInputModeSwitchKey
        bindProxy()
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        bindProxy()
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        // safeAreaInsets 在 viewWillLayoutSubviews 里才是准的
        heightConstraint?.constant = KeyboardMetrics.totalHeight + view.safeAreaInsets.bottom
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        PetSpriteStore.shared.purge()
    }

    private func bindProxy() {
        keyboard?.sink = ProxyTextSink(proxy: textDocumentProxy)
    }
}
