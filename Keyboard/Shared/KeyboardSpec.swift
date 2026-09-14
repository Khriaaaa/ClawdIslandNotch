import UIKit

/// 一个按键干什么
enum KeyAction: Equatable {
    case text(String)      // 直接上字
    case backspace
    case shift
    case toSymbols
    case toLetters
    case nextKeyboard
    case space
    case newline
}

/// 按键长什么样
enum KeyStyle: Equatable {
    case character   // 字母数字，亮底
    case modifier    // shift / 123 / 地球，暗底
    case space
    case primary     // 回车，高亮色
}

struct KeySpec: Equatable {
    let action: KeyAction
    let title: String
    let units: CGFloat          // 同一行里的宽度权重
    let style: KeyStyle
    let symbol: String?         // 有 SF Symbol 就画图标不画字
    let accessibilityLabel: String

    init(_ action: KeyAction, title: String, units: CGFloat = 1, style: KeyStyle = .character,
         symbol: String? = nil, accessibilityLabel: String? = nil) {
        self.action = action
        self.title = title
        self.units = units
        self.style = style
        self.symbol = symbol
        self.accessibilityLabel = accessibilityLabel ?? (title.isEmpty ? "按键" : title)
    }
}

/// 键盘尺寸。全部用代码算，不走 Auto Layout —— 键盘要的是快和可预测。
///
/// 这几个数不是拍脑袋来的，是拿一张 375×812 pt(@3x) 的真机截图逐像素量出来的：
/// 工具条 42~45、字母键行高 44.7、键宽 29.1、水平键距 8.46、行距 12.7~13、
/// 十键行左右边距 4、九键行左右边距 23（行内居中而不是撑满）。
/// 这套总数 278pt，跟截图里键盘顶边到底边完全对上。
enum KeyboardMetrics {
    static let stripHeight: CGFloat = 44        // Clawd 的活动范围，对齐系统那条工具条
    static let separatorHeight: CGFloat = 1
    static let topPadding: CGFloat = 7
    static let bottomPadding: CGFloat = 7
    static let rowHeight: CGFloat = 45
    static let rowSpacing: CGFloat = 13         // 纵向比横向松，这是 iOS 的手感来源
    static let keySpacing: CGFloat = 8.5
    static let sidePadding: CGFloat = 4
    static let cornerRadius: CGFloat = 5

    /// 基准键宽：拿最多键的那一行算，其余行沿用同一个宽度再整行居中。
    /// 第二行只有 9 键，如果按剩余宽度平摊就会比第一行胖，一眼假。
    static func baseUnitWidth(forTotalWidth width: CGFloat, maxKeys: Int) -> CGFloat {
        let gaps = keySpacing * CGFloat(max(0, maxKeys - 1))
        return (width - sidePadding * 2 - gaps) / CGFloat(max(maxKeys, 1))
    }

    static var totalHeight: CGFloat {
        stripHeight + separatorHeight + topPadding + rowHeight * 4 + rowSpacing * 3 + bottomPadding
    }
}

/// 键位表。纯数据，跟视图无关。
enum KeyboardPages {

    static func letterRows(shifted: Bool) -> [[KeySpec]] {
        func key(_ ch: String) -> KeySpec {
            let t = shifted ? ch.uppercased() : ch
            return KeySpec(.text(t), title: t)
        }
        var row2: [KeySpec] = [
            KeySpec(.shift, title: "", units: 1.5, style: .modifier,
                    symbol: shifted ? "shift.fill" : "shift", accessibilityLabel: "大写")
        ]
        row2.append(contentsOf: "zxcvbnm".map { key(String($0)) })
        row2.append(KeySpec(.backspace, title: "", units: 1.5, style: .modifier,
                            symbol: "delete.left", accessibilityLabel: "删除"))

        return [
            "qwertyuiop".map { key(String($0)) },
            "asdfghjkl".map { key(String($0)) },
            row2,
            bottomRow(left: KeySpec(.toSymbols, title: "123", units: 1.25, style: .modifier,
                                    accessibilityLabel: "数字与符号"))
        ]
    }

    static func symbolRows() -> [[KeySpec]] {
        func key(_ ch: String) -> KeySpec { KeySpec(.text(ch), title: ch) }
        var row2: [KeySpec] = [
            KeySpec(.toLetters, title: "ABC", units: 1.5, style: .modifier, accessibilityLabel: "字母")
        ]
        row2.append(contentsOf: [".", ",", "?", "!", "\'"].map { key($0) })
        row2.append(KeySpec(.backspace, title: "", units: 1.5, style: .modifier,
                            symbol: "delete.left", accessibilityLabel: "删除"))

        return [
            "1234567890".map { key(String($0)) },
            ["-", "/", ":", ";", "(", ")", "$", "&", "@", "\""].map { key($0) },
            row2,
            bottomRow(left: KeySpec(.toLetters, title: "ABC", units: 1.25, style: .modifier,
                                    accessibilityLabel: "字母"))
        ]
    }

    /// 第四行：左边切页 / 地球 / 空格 / 回车
    private static func bottomRow(left: KeySpec) -> [KeySpec] {
        [
            left,
            KeySpec(.nextKeyboard, title: "", units: 1.25, style: .modifier,
                    symbol: "globe", accessibilityLabel: "下一输入法"),
            KeySpec(.space, title: "空格", units: 5, style: .space, accessibilityLabel: "空格"),
            KeySpec(.newline, title: "换行", units: 2.25, style: .primary, accessibilityLabel: "回车")
        ]
    }
}
