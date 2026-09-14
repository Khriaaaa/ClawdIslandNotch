import UIKit

/// Clawd 的活动范围 —— 键盘顶部那一条。
///
/// 位置上正好是系统键盘「候选词条」那一行，所以以后接拼音候选字，
/// 直接浮在这条里就行，不用再占地方。
///
/// 条右边那四颗圆形工具按钮照着真机截图摆（直径 29.3 / 间距 16.67 / 右缩进 14.3），
/// 截图里最左边那颗品牌图标的位置留给 Clawd，所以它从条左边一直逛到按钮组跟前。
///
/// 这里**没有**状态文字：条只有 46pt，右边四颗按钮占掉 167pt，
/// 再塞一行字螃蟹就没地方走了 —— 状态改由它的姿势表达（敲键盘 / 睡着 / 举牌）。
final class PetStripView: UIView {

    enum Mood: Equatable {
        case idle, walking, typing, sleeping, alert, happy

        var spriteName: String {
            switch self {
            case .idle:     return "clawd-mini-idle"
            case .walking:  return "clawd-mini-crabwalk"
            case .typing:   return "clawd-mini-typing"
            case .sleeping: return "clawd-mini-sleep"
            case .alert:    return "clawd-mini-alert"
            case .happy:    return "clawd-mini-happy"
            }
        }
    }

    /// 工具按钮点了以后往上抛
    var onToolAction: ((KeyAction) -> Void)?

    private let spriteView = UIImageView()
    private var toolButtons: [ToolButton] = []

    private var mood: Mood = .idle
    private var position: CGFloat = 0
    private var targetX: CGFloat = 0
    private var restUntil: CFTimeInterval = 0
    private var holdUntil: CFTimeInterval = 0
    private var lastKeyTime: CFTimeInterval = CACurrentMediaTime()
    private var external: Mood?
    private var theme = KeyboardTheme(dark: true)

    // CADisplayLink 会强引用 target，用它就会形成 runloop ↔ self 的环，
    // deinit 永远不跑、invalidate 变死代码。所以走一个弱代理。
    private var displayLink: CADisplayLink?
    private final class LinkProxy {
        weak var owner: PetStripView?
        init(_ owner: PetStripView) { self.owner = owner }
        @objc func tick() { owner?.tick() }
    }
    private var linkProxy: LinkProxy?

    private let sleepAfter: CFTimeInterval = 45
    private let walkSpeed: CGFloat = 30          // pt / 秒
    private let framesPerSecond: CGFloat = 30

    // MARK: - 尺寸

    /// 螃蟹比圆形按钮（29.3）略大一圈，像个角色而不像第五颗按钮
    private var spriteHeight: CGFloat { max(18, KeyboardMetrics.stripHeight - 8) }
    private var spriteAspect: CGFloat {
        guard let image = spriteView.image, image.size.height > 0 else { return 1.6 }
        return image.size.width / image.size.height
    }
    private var spriteWidth: CGFloat { spriteHeight * spriteAspect }
    private var minX: CGFloat { KeyboardMetrics.toolSideInset }
    /// 右边界到按钮组跟前为止，还要留 8pt 别贴着
    private var maxX: CGFloat {
        let groupStart = KeyboardMetrics.toolGroupStart(totalWidth: bounds.width)
        return max(minX, groupStart - 8 - spriteWidth)
    }

    // MARK: - 生命周期

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true

        spriteView.contentMode = .scaleAspectFit
        addSubview(spriteView)

        // 四颗工具按钮：语言、表情、剪贴板、收起键盘
        let items: [(KeyAction, String?, String?)] = [
            (.nextKeyboard, nil, "文\nA"),
            (.toEmoji, "cube", nil),
            (.clipboard, "doc.on.clipboard", nil),
            (.dismiss, "chevron.down", nil),
        ]
        toolButtons = items.map { action, symbol, text in
            let button = ToolButton(action: action, symbol: symbol, text: text, theme: theme)
            button.addGestureRecognizer(
                UITapGestureRecognizer(target: self, action: #selector(handleToolTap(_:))))
            addSubview(button)
            return button
        }

        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap)))

        render()
        startDisplayLink()
    }

    required init?(coder: NSCoder) { fatalError("不支持 xib") }

    deinit {
        displayLink?.invalidate()
        displayLink = nil
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        displayLink?.isPaused = (window == nil)
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        // 工具按钮：整组右对齐
        let d = KeyboardMetrics.toolDiameter
        let groupStart = KeyboardMetrics.toolGroupStart(totalWidth: bounds.width)
        for (i, button) in toolButtons.enumerated() {
            let x = groupStart + CGFloat(i) * (d + KeyboardMetrics.toolSpacing)
            button.frame = CGRect(x: x, y: (bounds.height - d) / 2, width: d, height: d)
            button.layer.cornerRadius = d / 2
        }

        position = min(max(position, minX), maxX)
        spriteView.frame = CGRect(x: position, y: (bounds.height - spriteHeight) / 2,
                                  width: spriteWidth, height: spriteHeight)
    }

    // MARK: - 对外

    func apply(theme: KeyboardTheme) {
        self.theme = theme
        backgroundColor = theme.stripBackground
        toolButtons.forEach { $0.apply(theme: theme) }
    }

    /// 每敲一个键叫一次
    func petDidType() {
        let now = CACurrentMediaTime()
        lastKeyTime = now
        holdUntil = now + 0.7
        if mood != .alert { setMood(.typing) }
    }

    /// 外部状态（Claude Code 在干活 / 在等批准 / 出错了）盖在打字状态之上
    func setExternalState(_ state: Mood?) {
        external = state
        if let state {
            setMood(state)
        } else if mood == .alert {
            setMood(.idle)
            restUntil = CACurrentMediaTime() + 0.5
        }
    }

    var currentMood: Mood { mood }

    // MARK: - 内部

    @objc private func handleTap() {
        holdUntil = CACurrentMediaTime() + 1.2
        setMood(.happy)
    }

    @objc private func handleToolTap(_ gesture: UITapGestureRecognizer) {
        guard let button = gesture.view as? ToolButton else { return }
        button.setPressed(true)
        UIDevice.current.playInputClick()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { button.setPressed(false) }
        onToolAction?(button.keyAction)
    }

    private func startDisplayLink() {
        let proxy = LinkProxy(self)
        let link = CADisplayLink(target: proxy, selector: #selector(LinkProxy.tick))
        link.preferredFramesPerSecond = Int(framesPerSecond)
        // 必须挂在 .common：打字时主 runloop 在 tracking 模式，默认模式下的 timer 会停
        link.add(to: .main, forMode: .common)
        displayLink = link
        linkProxy = proxy
    }

    private func setMood(_ new: Mood) {
        guard mood != new else { return }
        mood = new
        // 只有走路才需要高帧率，其它时候降到 6fps 省电
        displayLink?.preferredFramesPerSecond = (new == .walking) ? Int(framesPerSecond) : 6
        render()
    }

    private func render() {
        spriteView.image = PetSpriteStore.shared.image(named: mood.spriteName)
    }

    private func tick() {
        guard window != nil else { return }
        let now = CACurrentMediaTime()

        // 外部状态优先，它说什么就是什么
        if let external {
            if mood != external { setMood(external) }
            return
        }

        switch mood {
        case .typing, .happy:
            if now > holdUntil {
                let wasHappy = (mood == .happy)
                setMood(.idle)
                restUntil = now + (wasHappy ? 0.8 : 0.5)
            }

        case .alert, .sleeping:
            break

        case .idle:
            if now - lastKeyTime > sleepAfter {
                setMood(.sleeping)
            } else if now > restUntil {
                targetX = CGFloat.random(in: minX...maxX)
                setMood(.walking)
            }

        case .walking:
            let dx = targetX - position
            let step = walkSpeed / framesPerSecond
            if abs(dx) <= step {
                position = targetX
                setMood(.idle)
                restUntil = now + Double.random(in: 0.6...2.2)
            } else {
                position += dx > 0 ? step : -step
                spriteView.frame.origin.x = position
            }
        }
    }
}
