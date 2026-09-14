import UIKit

/// 单个按键。
///
/// 刻意不用 UIButton：键盘自己接管触摸（按下就上字、手指滑走就撤高亮），
/// UIButton 的 target-action 时序和手势识别都跟这个需求对不上，而且慢。
final class KeyView: UIView {

    let spec: KeySpec
    private(set) var title: String
    private let label = UILabel()
    private let iconView = UIImageView()
    private var theme: KeyboardTheme

    init(spec: KeySpec, theme: KeyboardTheme) {
        self.spec = spec
        self.theme = theme
        self.title = spec.title
        super.init(frame: .zero)

        layer.cornerRadius = KeyboardMetrics.cornerRadius
        layer.cornerCurve = .continuous

        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.6
        label.font = .systemFont(ofSize: spec.style == .primary ? 16 : 22)

        iconView.contentMode = .scaleAspectFit

        addSubview(label)
        addSubview(iconView)

        isAccessibilityElement = true
        accessibilityTraits = .keyboardKey
        accessibilityLabel = spec.accessibilityLabel

        apply(theme: theme)
    }

    required init?(coder: NSCoder) { fatalError("不支持 xib") }

    func setTitle(_ newTitle: String) {
        title = newTitle
        label.text = newTitle
    }

    func apply(theme: KeyboardTheme) {
        self.theme = theme
        backgroundColor = theme.fill(for: spec.style)
        label.textColor = theme.textColor(for: spec.style)
        label.text = title

        if let symbol = spec.symbol {
            iconView.image = UIImage(systemName: symbol)
            iconView.tintColor = theme.textColor(for: spec.style)
            iconView.isHidden = false
            label.isHidden = true
        } else {
            iconView.isHidden = true
            label.isHidden = false
        }
    }

    private(set) var isPressed = false

    func setPressed(_ pressed: Bool) {
        guard pressed != isPressed else { return }
        isPressed = pressed
        backgroundColor = pressed ? theme.pressedFill(for: spec.style) : theme.fill(for: spec.style)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = bounds
        let side = min(bounds.height, bounds.width) * 0.50
        iconView.frame = CGRect(x: bounds.midX - side / 2, y: bounds.midY - side / 2,
                                width: side, height: side)
    }
}
