import UIKit

/// 键盘配色。跟着输入框所在 App 的深浅色走（textDocumentProxy.keyboardAppearance）。
struct KeyboardTheme {
    let dark: Bool

    var keyFill: UIColor {
        dark ? UIColor(white: 0.44, alpha: 1) : UIColor.white
    }
    var modifierFill: UIColor {
        dark ? UIColor(white: 0.29, alpha: 1) : UIColor(white: 0.67, alpha: 1)
    }
    var primaryFill: UIColor {
        dark ? UIColor(red: 0.20, green: 0.55, blue: 0.98, alpha: 1)
             : UIColor(red: 0.04, green: 0.48, blue: 1.00, alpha: 1)
    }
    var keyText: UIColor { dark ? .white : .black }
    var primaryText: UIColor { .white }
    var background: UIColor {
        dark ? UIColor(white: 0.16, alpha: 1) : UIColor(white: 0.82, alpha: 1)
    }
    var stripBackground: UIColor {
        dark ? UIColor(white: 0.11, alpha: 1) : UIColor(white: 0.90, alpha: 1)
    }
    var separator: UIColor {
        dark ? UIColor(white: 0.30, alpha: 1) : UIColor(white: 0.70, alpha: 1)
    }
    var stripText: UIColor {
        dark ? UIColor(white: 0.78, alpha: 1) : UIColor(white: 0.25, alpha: 1)
    }

    func fill(for style: KeyStyle) -> UIColor {
        switch style {
        case .character: return keyFill
        case .modifier: return modifierFill
        case .space: return keyFill
        case .primary: return primaryFill
        }
    }

    func pressedFill(for style: KeyStyle) -> UIColor {
        switch style {
        case .character, .space:
            return dark ? UIColor(white: 0.66, alpha: 1) : UIColor(white: 0.85, alpha: 1)
        case .modifier:
            return dark ? UIColor(white: 0.46, alpha: 1) : UIColor(white: 0.52, alpha: 1)
        case .primary:
            return primaryFill.withAlphaComponent(0.72)
        }
    }

    func textColor(for style: KeyStyle) -> UIColor {
        style == .primary ? primaryText : keyText
    }
}
