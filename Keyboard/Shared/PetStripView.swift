import UIKit

/// Clawd 的活动范围 —— 键盘顶部那一条。
///
/// 位置上正好是系统键盘「候选词条」那一行，所以以后接拼音候选字，
/// 直接浮在这条里就行，不用再占地方。
///
/// 条右边那四颗圆形工具按钮照着真机截图摆（直径 29.3 / 间距 16.67 / 右缩进 14.3），
/// 截图里最左边那颗品牌图标的位置留给 Clawd，所以它从条左边一直逛到按钮组跟前。
///
/// 行为就两条（2026-09-15 定的方向）：
/// 1. **打字跟着敲**：每敲一个键 `petDidType()`，打字姿按住 0.7 秒
/// 2. **不打字时按真实时钟过日子**：`ClawdBiorhythm` 按当前时段掷一个节拍
///    （白天闲逛、午间打盹、深夜睡、偶尔起来玩），一段演完再掷下一段
///
/// 这里**没有**状态文字：条只有 46pt，右边四颗按钮占掉 167pt，
/// 再塞一行字螃蟹就没地方走了 —— 状态改由它的姿势表达（敲键盘 / 睡着 / 玩）。
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
    /// 打字姿 / 开心姿按到这个时刻
    private var holdUntil: CFTimeInterval = 0
    /// 当前作息节拍要演的姿势，以及演到什么时候
    private var ambientMood: Mood = .idle
    private var ambientUntil: CFTimeInterval = 0
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

    private let walkSpeed: CGFloat = 30          // pt / 秒
    private let framesPerSecond: CGFloat = 30
    /// 敲完最后一个键还保持打字姿多久
    private let typingHold: CFTimeInterval = 0.7

    // MARK: - 尺寸

    /// 螃蟹比圆形按钮（29.3）略大一圈，像个角色而不像第五颗按钮
    private var naturalHeight: CGFloat { max(18, KeyboardMetrics.stripHeight - 8) }
    private var spriteAspect: CGFloat {
        guard let image = spriteView.image, image.size.height > 0 else { return 1.6 }
        return image.size.width / image.size.height
    }
    private var minX: CGFloat { KeyboardMetrics.toolSideInset }
    /// 精灵左边缘能走的横向行程：从左内缩一直走到工具按钮组跟前（留 8pt 别贴着）
    private var travel: CGFloat {
        let groupStart = KeyboardMetrics.toolGroupStart(totalWidth: bounds.width)
        return max(0, groupStart - 8 - minX)
    }
    /// 320pt 这类窄屏上行程只有 ~116pt，而按原始比例算下来身宽 ~62pt，
    /// 走完一个来回也挪不出一个身位，看着就是在原地抖。走动是这只角色的
    /// 主要性格，静止或抖动都不如把它缩小 —— 身宽封在行程的一半，至少能
    /// 挪完一个完整的自己。375pt 上行程 171pt，不触发封顶，尺寸跟原来一样。
    private var spriteWidth: CGFloat {
        let natural = naturalHeight * spriteAspect
        guard travel > 0, natural > travel / 2 else { return natural }
        return max(24, travel / 2)
    }
    private var spriteHeight: CGFloat { spriteWidth / max(spriteAspect, 0.01) }
    /// 右边界到按钮组跟前为止
    private var maxX: CGFloat { max(minX, minX + max(0, travel - spriteWidth)) }

    // MARK: - 生命周期

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true

        spriteView.contentMode = .scaleAspectFit
        addSubview(spriteView)

        // 四颗工具按钮：语言、表情、剪贴板、收起键盘
        let items: [(KeyAction, String?, String?, String)] = [
            (.nextKeyboard, nil, "文\nA", "切换输入法"),
            (.toEmoji, "cube", nil, "表情"),
            (.clipboard, "doc.on.clipboard", nil, "粘贴"),
            (.dismiss, "chevron.down", nil, "收起键盘"),
        ]
        toolButtons = items.map { action, symbol, text, a11y in
            let button = ToolButton(action: action, symbol: symbol, text: text,
                                    a11y: a11y, theme: theme)
            button.addGestureRecognizer(
                UITapGestureRecognizer(target: self, action: #selector(handleToolTap(_:))))
            addSubview(button)
            return button
        }

        // 整条也能点（点哪儿都算摸一下 Clawd），但落在工具按钮上的要排掉，
        // 不然点工具按钮的同时螃蟹还会开心一下
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        tap.delegate = self
        addGestureRecognizer(tap)

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
        holdUntil = CACurrentMediaTime() + typingHold
        if mood != .alert { setMood(.typing) }
    }

    /// 当前姿势。键盘自检 / 预览页拿它判行为，不参与展示逻辑。
    var currentMood: Mood { mood }

    /// 马上换一节拍。给预览页 / CI 用：不传就按当前时刻掷一个。
    /// 真机上不需要它 —— 作息是自己在 tick 里走的。
    func advanceAmbient(now: CFTimeInterval = CACurrentMediaTime()) {
        startNextSlot(now)
    }

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

    /// 按真实时钟掷一个节拍，接上。走动是唯一带位移的，单独起。
    private func startNextSlot(_ now: CFTimeInterval) {
        let slot = ClawdBiorhythm.nextSlot(at: Date())
        ambientUntil = now + slot.duration

        switch slot.state {
        case .roam:
            ambientMood = .walking
            targetX = CGFloat.random(in: minX...maxX)
            setMood(.walking)
        default:
            let mapped = Self.stripMood(for: slot.state)
            ambientMood = mapped
            setMood(mapped)
        }
    }

    private func tick() {
        guard window != nil else { return }
        let now = CACurrentMediaTime()

        // 1) 手上还在敲（或刚被戳过）：打字 / 开心姿按住，别的一切让位
        if now < holdUntil {
            if mood != .typing && mood != .happy { setMood(.typing) }
            return
        }

        // 2) 短姿刚过完：节拍还没到点就交回节拍的姿势，到点了就掷下一个
        if mood == .typing || mood == .happy {
            if now >= ambientUntil {
                startNextSlot(now)
            } else {
                setMood(ambientMood)
            }
            return
        }

        // 3) 走动：逐帧推位置，走到点就歇一下、把这一节拍走完
        if mood == .walking {
            let dx = targetX - position
            let step = walkSpeed / framesPerSecond
            if abs(dx) <= step {
                position = targetX
                setMood(.idle)
                ambientMood = .idle
                ambientUntil = now + Double.random(in: 0.6...2.2)
            } else {
                position += dx > 0 ? step : -step
                spriteView.frame.origin.x = position
            }
            return
        }

        // 4) 节拍到点，掷下一段
        if now >= ambientUntil {
            startNextSlot(now)
        }
    }

    /// 作息状态 → 活动条姿势。键盘上只有六张图，这里做归并：
    /// 玩（juggling / dizzy）用开心图，睡的一族（yawning / dozing / sleeping /
    /// collapsing）都睡姿，警戒一族（attention / notification / error）用举牌图。
    ///
    /// 名字带 `strip` 前缀不是啰嗦：上面那个实例属性就叫 `mood`，同名静态方法会撞。
    static func stripMood(for state: ClawdState) -> Mood {
        switch state {
        case .roam:
            return .walking
        case .juggling, .dizzy:
            return .happy
        case .yawning, .dozing, .sleeping, .collapsing:
            return .sleeping
        case .attention, .notification, .error:
            return .alert
        case .idle, .waking, .thinking, .working, .sweeping, .carrying:
            return .idle
        }
    }
}

// MARK: - 手势冲突

extension PetStripView: UIGestureRecognizerDelegate {

    /// 点工具按钮的时候，整条那颗「摸一下 Clawd」的手势不要跟着响应
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldReceive touch: UITouch) -> Bool {
        guard gestureRecognizer.view === self else { return true }
        var node = touch.view
        while let v = node {
            if v is ToolButton { return false }
            if v === self { break }
            node = v.superview
        }
        return true
    }
}
