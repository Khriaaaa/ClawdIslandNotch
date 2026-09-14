import UIKit

/// 单个按键。
///
/// 刻意不用 UIButton：键盘自己接管触摸（按下就上字、手指滑走就撤高亮），
/// UIButton 的 target-action 时序和手势识别都跟这个需求对不上，而且慢 ——
/// 一次性铺四十个 UIButton 也会把键盘扩展那点内存预算吃掉。
final class KeyView: UIView {

    let spec: KeySpec
    private(set) var title: String
    private let label = UILabel()
    private let iconView = UIImageView()
    private let badgeView = UIImageView()      // 右上角那个小地球
    private var theme: KeyboardTheme
    private let twoLineParagraph: NSParagraphStyle?

    init(spec: KeySpec, theme: KeyboardTheme) {
        self.spec = spec
        self.theme = theme
        self.title = spec.title

        if spec.twoLine {
            // 系统那颗「中/英」就是两行小字，行距要收紧，不然两颗字会顶到键边
            let para = NSMutableParagraphStyle()
            para.lineSpacing = -3
            para.alignment = .center
            twoLineParagraph = para
        } else {
            twoLineParagraph = nil
        }

        super.init(frame: .zero)

        layer.cornerRadius = KeyboardMetrics.cornerRadius
        layer.cornerCurve = .continuous

        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.6
        label.numberOfLines = spec.twoLine ? 2 : 1
        if spec.twoLine {
            label.font = .systemFont(ofSize: 12, weight: .medium)
        } else if spec.style == .primary {
            label.font = .systemFont(ofSize: 16)
        } else {
            label.font = .systemFont(ofSize: 22)
        }

        iconView.contentMode = .scaleAspectFit
        badgeView.contentMode = .scaleAspectFit

        addSubview(label)
        addSubview(iconView)
        addSubview(badgeView)

        isAccessibilityElement = true
        accessibilityTraits = .keyboardKey
        accessibilityLabel = spec.accessibilityLabel

        apply(theme: theme)
    }

    required init?(coder: NSCoder) { fatalError("不支持 xib") }

    func setTitle(_ newTitle: String) {
        title = newTitle
        setLabelText()
    }

    /// 右上角角标（中/英 那颗键上挂个小地球，表示长按能切输入法）
    func setBadge(_ symbol: String?) {
        guard let symbol else {
            badgeView.isHidden = true
            return
        }
        badgeView.image = UIImage(systemName: symbol)
        badgeView.tintColor = theme.textColor(for: spec.style).withAlphaComponent(0.75)
        badgeView.isHidden = false
        setNeedsLayout()
    }

    func apply(theme: KeyboardTheme) {
        self.theme = theme
        backgroundColor = theme.fill(for: spec.style)

        let textColor = theme.textColor(for: spec.style)
        label.textColor = textColor
        setLabelText()

        if let symbol = spec.symbol {
            iconView.image = UIImage(systemName: symbol)
            iconView.tintColor = textColor
            iconView.isHidden = false
            label.isHidden = true
        } else {
            iconView.isHidden = true
            label.isHidden = false
        }
        setNeedsLayout()
    }

    private(set) var isPressed = false

    func setPressed(_ pressed: Bool) {
        guard pressed != isPressed else { return }
        isPressed = pressed
        backgroundColor = pressed ? theme.pressedFill(for: spec.style) : theme.fill(for: spec.style)
    }

    private func setLabelText() {
        // UILabel.font 是隐式解包可选。直接塞进 [NSAttributedString.Key: Any] 不会被解包
        // （SE-0054 只在需要非可选的上下文才插 !），装进去的是 Optional 装箱值。
        // 先赋给非可选局部变量逼它解一次。
        let baseFont: UIFont = label.font
        if let para = twoLineParagraph {
            label.attributedText = NSAttributedString(
                string: title,
                attributes: [.paragraphStyle: para,
                             .foregroundColor: theme.textColor(for: spec.style),
                             .font: baseFont])
        } else {
            label.attributedText = nil
            label.text = title
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = bounds
        let side = min(bounds.height, bounds.width) * 0.50
        iconView.frame = CGRect(x: bounds.midX - side / 2, y: bounds.midY - side / 2,
                                width: side, height: side)

        if !badgeView.isHidden {
            let bs = min(bounds.height, bounds.width) * 0.32
            badgeView.frame = CGRect(x: bounds.maxX - bs - 3, y: 3, width: bs, height: bs)
        }
    }
}
