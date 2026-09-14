import UIKit

/// 活动条右边那四颗圆形工具按钮。
///
/// 位置是照着真机截图量的：直径 29.3pt、间距 16.67pt、整组右缩进 14.3pt。
/// 截图里这一排最左边还有一颗品牌图标，那颗的位置留给 Clawd 了，所以只剩四颗。
final class ToolButton: UIView {

    private let iconView = UIImageView()
    private let label = UILabel()
    private let action: KeyAction
    private var theme: KeyboardTheme

    init(action: KeyAction, symbol: String?, text: String?, theme: KeyboardTheme) {
        self.action = action
        self.theme = theme
        super.init(frame: .zero)

        layer.cornerRadius = KeyboardMetrics.toolDiameter / 2
        layer.cornerCurve = .continuous

        iconView.contentMode = .scaleAspectFit
        label.textAlignment = .center
        label.numberOfLines = 2
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.5

        if let symbol {
            iconView.image = UIImage(systemName: symbol)
        } else {
            let para = NSMutableParagraphStyle()
            para.lineSpacing = -4
            para.alignment = .center
            label.attributedText = NSAttributedString(
                string: text ?? "",
                attributes: [.paragraphStyle: para,
                             .font: UIFont.systemFont(ofSize: 11, weight: .medium)])
        }

        addSubview(iconView)
        addSubview(label)

        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = text?.replacingOccurrences(of: "\n", with: "") ?? "工具"

        apply(theme: theme)
    }

    required init?(coder: NSCoder) { fatalError("不支持 xib") }

    var keyAction: KeyAction { action }

    func apply(theme: KeyboardTheme) {
        self.theme = theme
        backgroundColor = theme.toolFill
        let tint = theme.toolIcon
        iconView.tintColor = tint
        if label.attributedText != nil {
            let para = NSMutableParagraphStyle()
            para.lineSpacing = -4
            para.alignment = .center
            let plain = label.attributedText?.string ?? ""
            label.attributedText = NSAttributedString(
                string: plain,
                attributes: [.paragraphStyle: para,
                             .font: UIFont.systemFont(ofSize: 11, weight: .medium),
                             .foregroundColor: tint])
        }
    }

    private(set) var isPressed = false

    func setPressed(_ pressed: Bool) {
        guard pressed != isPressed else { return }
        isPressed = pressed
        backgroundColor = pressed ? theme.toolFill.withAlphaComponent(0.55) : theme.toolFill
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = bounds
        let side = bounds.height * 0.55
        iconView.frame = CGRect(x: bounds.midX - side / 2, y: bounds.midY - side / 2,
                                width: side, height: side)
    }
}
