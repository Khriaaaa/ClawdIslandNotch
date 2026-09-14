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
enum KeyboardMetrics {
    static let stripHeight: CGFloat = 56        // Clawd 的活动范围
    static let separatorHeight: CGFloat = 1
    static let topPadding: CGFloat = 7
    static let bottomPadding: CGFloat = 7
    static let rowHeight: CGFloat = 43
    static let rowSpacing: CGFloat = 6
    static let keySpacing: CGFloat = 6
    static let sidePadding: CGFloat = 3
    static let cornerRadius: CGFloat = 5

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
