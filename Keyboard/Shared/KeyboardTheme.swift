import UIKit

/// 键盘配色。跟着输入框所在 App 的深浅色走（textDocumentProxy.keyboardAppearance）。
///
/// 深浅两套的数值都是照一张 375×812pt @3x 的真机深色截图逐像素量出来的：
/// 键盘底 33,33,33 / 键帽 94,94,94 / 发送键是绿的 95,197,149（不是蓝的）。
struct KeyboardTheme {
    let dark: Bool

    var keyFill: UIColor {
        dark ? UIColor(white: 0.37, alpha: 1) : UIColor.white
    }
    var modifierFill: UIColor {
        dark ? UIColor(white: 0.30, alpha: 1) : UIColor(white: 0.67, alpha: 1)
    }
    /// 主操作键（发送/搜索/前往）。照实测取聊天 App 里那个绿色。
    var primaryFill: UIColor {
        dark ? UIColor(red: 0.373, green: 0.773, blue: 0.584, alpha: 1)
             : UIColor(red: 0.20, green: 0.66, blue: 0.46, alpha: 1)
    }
    var keyText: UIColor { dark ? .white : .black }
    var primaryText: UIColor { .white }
    var background: UIColor {
        dark ? UIColor(white: 0.13, alpha: 1) : UIColor(white: 0.82, alpha: 1)
    }
    /// 活动条跟键盘底色**同色**，只用一条细线分界 —— 系统那条候选词条就是这么做的，
    /// 之前做成比底色更暗，结果在深色页面里整条糊掉看不出来
    var stripBackground: UIColor { background }
    var separator: UIColor {
        dark ? UIColor(white: 0.24, alpha: 1) : UIColor(white: 0.70, alpha: 1)
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
