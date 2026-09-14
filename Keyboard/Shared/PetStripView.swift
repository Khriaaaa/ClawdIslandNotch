import UIKit

/// Clawd 的活动范围 —— 键盘顶部那一条。
///
/// 位置上正好是系统键盘「候选词条」那一行，所以以后接拼音候选字，
/// 直接浮在这条里就行，不用再占地方。
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

        var text: String {
            switch self {
            case .idle:     return "Clawd 在这儿"
            case .walking:  return "Clawd 在溜达"
            case .typing:   return "Clawd 在敲键盘"
            case .sleeping: return "Clawd 睡着了"
            case .alert:    return "Clawd 在等你"
            case .happy:    return "Clawd 很开心"
            }
        }
    }

    private let spriteView = UIImageView()
    private let statusLabel = UILabel()

    private var mood: Mood = .idle
    private var position: CGFloat = 0
    private var targetX: CGFloat = 0
    private var restUntil: CFTimeInterval = 0
    private var typingUntil: CFTimeInterval = 0
    private var lastKeyTime: CFTimeInterval = CACurrentMediaTime()
    private var pinnedText: String?
    private var displayLink: CADisplayLink?
    private var theme = KeyboardTheme(dark: true)

    private let sleepAfter: CFTimeInterval = 45
    private let walkSpeed: CGFloat = 30          // pt / 秒
    private let framesPerSecond: CGFloat = 30

    // MARK: - 尺寸

    private var spriteHeight: CGFloat { max(18, bounds.height - 12) }
    private var spriteAspect: CGFloat {
        guard let image = spriteView.image, image.size.height > 0 else { return 1.6 }
        return image.size.width / image.size.height
    }
    private var spriteWidth: CGFloat { spriteHeight * spriteAspect }
    private var maxX: CGFloat { max(0, bounds.width - spriteWidth - 12) }

    // MARK: - 生命周期

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true

        spriteView.contentMode = .scaleAspectFit
        addSubview(spriteView)

        statusLabel.font = .systemFont(ofSize: 11, weight: .medium)
        statusLabel.textAlignment = .right
        statusLabel.lineBreakMode = .byTruncatingHead
        addSubview(statusLabel)

        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap)))

        render()
        startDisplayLink()
    }

    required init?(coder: NSCoder) { fatalError("不支持 xib") }

    deinit { displayLink?.invalidate() }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        displayLink?.isPaused = (window == nil)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        position = min(position, maxX)
        spriteView.frame = CGRect(x: position, y: bounds.height - spriteHeight - 4,
                                  width: spriteWidth, height: spriteHeight)
        statusLabel.frame = CGRect(x: bounds.width * 0.35, y: 0,
                                   width: bounds.width * 0.65 - 12, height: bounds.height)
    }

    // MARK: - 对外

    func apply(theme: KeyboardTheme) {
        self.theme = theme
        backgroundColor = theme.stripBackground
        statusLabel.textColor = theme.stripText
    }

    /// 每敲一个键叫一次
    func petDidType() {
        let now = CACurrentMediaTime()
        lastKeyTime = now
        typingUntil = now + 0.7
        if mood != .alert { setMood(.typing) }
    }

    /// 外部状态（以后接状态服务器，Claude Code 干活就传文本进来）
    func setStatusText(_ text: String?) {
        pinnedText = text
        statusLabel.text = text ?? mood.text
    }

    func flashAlert() { setMood(.alert) }

    func relax() {
        guard mood == .alert else { return }
        setMood(.idle)
        restUntil = CACurrentMediaTime() + 0.5
    }

    var currentMood: Mood { mood }

    // MARK: - 内部

    @objc private func handleTap() {
        typingUntil = CACurrentMediaTime() + 1.2
        setMood(.happy)
    }

    private func startDisplayLink() {
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.preferredFramesPerSecond = Int(framesPerSecond)
        // 必须挂在 .common：打字时主 runloop 在 tracking 模式，默认模式下的 timer 会停
        link.add(to: .main, forMode: .common)
        displayLink = link
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
        statusLabel.text = pinnedText ?? mood.text
    }

    @objc private func tick() {
        guard window != nil else { return }
        let now = CACurrentMediaTime()

        switch mood {
        case .typing:
            if now > typingUntil { setMood(.idle); restUntil = now + 0.5 }

        case .happy:
            if now > typingUntil { setMood(.idle); restUntil = now + 0.8 }

        case .alert, .sleeping:
            break

        case .idle:
            if now - lastKeyTime > sleepAfter {
                setMood(.sleeping)
            } else if now > restUntil {
                targetX = CGFloat.random(in: 0...maxX)
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
