import UIKit

/// 输入法控制器。只干两件事：把 textDocumentProxy 接到键盘视图上、管住高度。
/// 所有 UI 都在 ClawdKeyboardView 里，那份代码同时被宿主 App 的预览页复用。
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
        kb.onKeySound = { UIDevice.current.playInputClick() }
        view.addSubview(kb)

        NSLayoutConstraint.activate([
            kb.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            kb.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            kb.topAnchor.constraint(equalTo: view.topAnchor),
            kb.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        keyboard = kb

        // 键盘高度自己定，不受系统键盘限制。优先级压到 999，别跟系统的约束硬顶。
        let height = view.heightAnchor.constraint(equalToConstant: KeyboardMetrics.totalHeight)
        height.priority = UILayoutPriority(999)
        height.isActive = true
        heightConstraint = height
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        bindProxy()
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        bindProxy()
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        heightConstraint?.constant = KeyboardMetrics.totalHeight
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        PetSpriteStore.shared.purge()
    }

    private func bindProxy() {
        keyboard?.sink = ProxyTextSink(proxy: textDocumentProxy)
    }
}
