import UIKit

/// 输入法控制器。只干三件事：把 textDocumentProxy 接到键盘视图上、
/// 管住高度（含底部安全区）、把系统要求的输入法切换接上。
/// 所有 UI 都在 ClawdKeyboardView 里，那份代码同时被宿主 App 的预览页复用。
final class KeyboardViewController: UIInputViewController, UIInputViewAudioFeedback {

    private var keyboard: ClawdKeyboardView?
    private var heightConstraint: NSLayoutConstraint?
    /// Claude Code 的状态轮询（只在键盘可见时跑）
    private var stateTimer: Timer?

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

        // 键盘不收起就一直挂着，而 Claude Code 的状态随时会变。
        // 只在 viewDidAppear 读一次的话，键盘开着的时候 Clawd 永远停在
        // 打开那一刻的姿势上。5 秒一刷，够用又不费电。
        stateTimer?.invalidate()
        let t = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.refreshExternalState()
        }
        RunLoop.main.add(t, forMode: .common)
        stateTimer = t
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stateTimer?.invalidate()
        stateTimer = nil
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

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        refreshExternalState()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        PetSpriteStore.shared.purge()
    }

    private func bindProxy() {
        keyboard?.sink = ProxyTextSink(proxy: textDocumentProxy)
    }

    /// 宿主 App 往 App Group 里写的 Claude Code 状态，读出来驱动 Clawd。
    /// 没开「完全访问」时读不到共享容器，那就只有当打字反应，不影响其它功能。
    private func refreshExternalState() {
        keyboard?.setExternalState(KeyboardStateBridge.currentMood())
    }
}
