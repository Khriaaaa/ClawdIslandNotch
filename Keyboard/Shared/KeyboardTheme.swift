import UIKit

/// 键盘配色。跟着输入框所在 App 的深浅色走（textDocumentProxy.keyboardAppearance）。
///
/// 深色那套数值是照一张 375pt 宽 @3x 的真机截图逐像素量出来的：
/// 键盘底 33,33,33 / 键帽 94,94,94 / 修饰键（123、表情、发送）53,53,53 /
/// 工具按钮底 78,78,78、图标 164,164,164。
/// 注意发送键在参考图里**不是**绿的，是跟 123 一样的深灰 —— 那个绿是工具条上
/// 最左边那颗品牌图标，位置已经留给 Clawd 了。
struct KeyboardTheme {
    let dark: Bool

    var keyFill: UIColor {
        dark ? UIColor(white: 0.369, alpha: 1) : UIColor.white
    }
    var modifierFill: UIColor {
        dark ? UIColor(white: 0.208, alpha: 1) : UIColor(white: 0.67, alpha: 1)
    }
    /// 主操作键（发送/搜索/前往）。参考图里跟修饰键同色。
    var primaryFill: UIColor {
        dark ? UIColor(white: 0.208, alpha: 1)
             : UIColor(red: 0.20, green: 0.66, blue: 0.46, alpha: 1)
    }
    var keyText: UIColor { dark ? .white : .black }
    var primaryText: UIColor { .white }
    var background: UIColor {
        dark ? UIColor(white: 0.129, alpha: 1) : UIColor(white: 0.82, alpha: 1)
    }
    /// 活动条跟键盘底色**同色** —— 参考图里那条工具条和按键区之间没有分隔线，
    /// 之前做成比底色更暗，结果整条糊掉看不出来
    var stripBackground: UIColor { background }
    /// 参考图里量不出分隔线，所以给底色同色（保留属性是为了以后想加再改一处）
    var separator: UIColor { background }

    var toolFill: UIColor {
        dark ? UIColor(white: 0.306, alpha: 1) : UIColor(white: 0.90, alpha: 1)
    }
    var toolIcon: UIColor {
        dark ? UIColor(white: 0.643, alpha: 1) : UIColor(white: 0.30, alpha: 1)
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
        case .modifier, .primary:
            return dark ? UIColor(white: 0.34, alpha: 1) : UIColor(white: 0.52, alpha: 1)
        }
    }

    func textColor(for style: KeyStyle) -> UIColor {
        style == .primary ? primaryText : keyText
    }
}
