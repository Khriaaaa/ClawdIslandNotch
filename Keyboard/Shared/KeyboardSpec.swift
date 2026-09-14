import UIKit

/// 一个按键干什么
enum KeyAction: Equatable {
    case text(String)          // 直接上字
    case backspace
    case shift
    case punctuation           // 。/, 快键，跟着「中英」模式走
    case toSymbols             // 123
    case toMoreSymbols         // #+=
    case toLetters             // ABC
    case toEmoji               // 表情页
    case nextKeyboard
    case space
    case newline
    case toggleLanguage        // 中/英（标点全角半角），长按切输入法
    case dismiss               // 收起键盘
    case clipboard             // 贴剪贴板（要完全访问）
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
    let twoLine: Bool           // 双行小字（中/英、。/,）
    let accessibilityLabel: String

    init(_ action: KeyAction, title: String, units: CGFloat = 1, style: KeyStyle = .character,
         symbol: String? = nil, twoLine: Bool = false, accessibilityLabel: String? = nil) {
        self.action = action
        self.title = title
        self.units = units
        self.style = style
        self.symbol = symbol
        self.twoLine = twoLine
        self.accessibilityLabel = accessibilityLabel ?? (title.isEmpty ? "按键" : title)
    }
}

/// 一行怎么摆。这三种模式是照着真机截图反推的：
/// 第一行十个键正好铺满左右边距，第二行九个键保持同样的键宽、整行缩进居中，
/// 第三行 ⇧ 和 ⌫ 贴死左右边，中间七个字母在剩下的空档里居中，
/// 第四行六个键又是铺满。
enum RowLayout: Equatable {
    case centered     // 用全局基准键宽，整行居中
    case filled       // 撑满左右边距，键宽按本行单位数解出来
    case edgePinned   // 首尾两颗贴边，中间一段整体居中
}

struct KeyboardRow: Equatable {
    let keys: [KeySpec]
    let layout: RowLayout
}

/// 键盘尺寸。全部用代码算，不走 Auto Layout —— 键盘要的是快和可预测。
///
/// 下面每个数都是从一张 **375pt 宽、@3x** 的真机截图逐像素量出来的，不是估的：
/// 工具条高 46 / 圆形工具按钮直径 29.3、间距 16.67、右缩进 14.3 /
/// 键行高 45.3 / 行距 12.3 / 键距 5.85 / 外侧边距 3 / 圆角 6.3 /
/// 十键行键宽 31.6 / 九键行左右缩进 22。
/// 加起来总高 282.9pt，跟截图里键盘顶边到底边对得上。
enum KeyboardMetrics {
    static let stripHeight: CGFloat = 46        // Clawd 的活动范围，对齐系统那条工具条
    static let topPadding: CGFloat = 12.3
    static let bottomPadding: CGFloat = 6.5
    static let rowHeight: CGFloat = 45.3
    static let rowSpacing: CGFloat = 12.3       // 纵向比横向松得多，这是 iOS 的手感来源
    static let keySpacing: CGFloat = 5.85
    static let sidePadding: CGFloat = 3
    static let cornerRadius: CGFloat = 6.3

    // 活动条右边那四颗圆形工具按钮
    static let toolDiameter: CGFloat = 29.3
    static let toolSpacing: CGFloat = 16.67
    static let toolSideInset: CGFloat = 14.3
    static let toolCount = 4

    static var toolGroupWidth: CGFloat {
        CGFloat(toolCount) * toolDiameter + CGFloat(toolCount - 1) * toolSpacing
    }

    /// 工具按钮组的左边缘（Clawd 不许越过这里）
    static func toolGroupStart(totalWidth: CGFloat) -> CGFloat {
        totalWidth - toolSideInset - toolGroupWidth
    }

    static var totalHeight: CGFloat {
        stripHeight + topPadding + rowHeight * 4 + rowSpacing * 3 + bottomPadding
    }
}

/// 键位表。纯数据，跟视图无关。
enum KeyboardPages {

    // MARK: - 标点两套

    static func punctTitle(chinese: Bool) -> String { chinese ? "。\n，" : ".\n," }
    static func punctText(chinese: Bool) -> String { chinese ? "。" : "." }

    /// 第四行：切页 / 表情 / 标点 / 空格 / 中英 / 回车
    private static func bottomRow(left: KeySpec, chinese: Bool) -> KeyboardRow {
        KeyboardRow(keys: [
            left,
            KeySpec(.toEmoji, title: "", units: 1.0, style: .modifier,
                    symbol: "face.smiling", accessibilityLabel: "表情"),
            KeySpec(.punctuation, title: punctTitle(chinese: chinese), units: 1.0,
                    twoLine: true, accessibilityLabel: "标点"),
            KeySpec(.space, title: "空格", units: 3.66, style: .space, accessibilityLabel: "空格"),
            KeySpec(.toggleLanguage, title: "中\n英", units: 1.12, style: .modifier,
                    twoLine: true, accessibilityLabel: "中英文标点，长按切换输入法"),
            KeySpec(.newline, title: "换行", units: 2.34, style: .primary, accessibilityLabel: "回车"),
        ], layout: .filled)
    }

    private static func backspaceKey() -> KeySpec {
        KeySpec(.backspace, title: "", units: 1.27, style: .modifier,
                symbol: "delete.left", accessibilityLabel: "删除")
    }

    // MARK: - 页

    static func letterPage(shift: ShiftState, chinese: Bool) -> [KeyboardRow] {
        // 键面一律大写 —— 目标输入法就是这么显示的（⇧ 空心时也显示大写，
        // 但上字是小写）。shift 只改上字，不改键面。
        func key(_ ch: String) -> KeySpec { KeySpec(.text(ch), title: ch.uppercased()) }

        let shiftSymbol: String
        switch shift {
        case .off:    shiftSymbol = "shift"
        case .on:     shiftSymbol = "shift.fill"
        case .locked: shiftSymbol = "capslock.fill"
        }

        var row3: [KeySpec] = [
            KeySpec(.shift, title: "", units: 1.32, style: .modifier,
                    symbol: shiftSymbol, accessibilityLabel: "大写")
        ]
        row3.append(contentsOf: "zxcvbnm".map { key(String($0)) })
        row3.append(backspaceKey())

        return [
            KeyboardRow(keys: "qwertyuiop".map { key(String($0)) }, layout: .filled),
            KeyboardRow(keys: "asdfghjkl".map { key(String($0)) }, layout: .centered),
            KeyboardRow(keys: row3, layout: .edgePinned),
            bottomRow(left: KeySpec(.toSymbols, title: "123", units: 1.54, style: .modifier,
                                    accessibilityLabel: "数字与符号"), chinese: chinese),
        ]
    }

    static func symbolPage(chinese: Bool) -> [KeyboardRow] {
        func key(_ ch: String) -> KeySpec { KeySpec(.text(ch), title: ch) }

        var row3: [KeySpec] = [
            KeySpec(.toMoreSymbols, title: "#+=", units: 1.32, style: .modifier,
                    accessibilityLabel: "更多符号")
        ]
        row3.append(contentsOf: [",", ".", "?", "!", "'"].map { key($0) })
        row3.append(backspaceKey())

        return [
            KeyboardRow(keys: "1234567890".map { key(String($0)) }, layout: .filled),
            KeyboardRow(keys: ["-", "/", ":", ";", "(", ")", "$", "&", "@", "\""].map { key($0) },
                        layout: .centered),
            KeyboardRow(keys: row3, layout: .edgePinned),
            bottomRow(left: KeySpec(.toLetters, title: "ABC", units: 1.54, style: .modifier,
                                    accessibilityLabel: "字母"), chinese: chinese),
        ]
    }

    static func moreSymbolPage(chinese: Bool) -> [KeyboardRow] {
        func key(_ ch: String) -> KeySpec { KeySpec(.text(ch), title: ch) }

        var row3: [KeySpec] = [
            KeySpec(.toSymbols, title: "123", units: 1.32, style: .modifier,
                    accessibilityLabel: "数字与符号")
        ]
        row3.append(contentsOf: ["[", "]", "{", "}", "\"", "~"].map { key($0) })
        row3.append(backspaceKey())

        return [
            KeyboardRow(keys: ["%", "^", "*", "+", "=", "_", "\\", "|", "<", ">"].map { key($0) },
                        layout: .filled),
            KeyboardRow(keys: ["€", "£", "¥", "•", "·", "°", "√", "∆", "≈"].map { key($0) },
                        layout: .centered),
            KeyboardRow(keys: row3, layout: .edgePinned),
            bottomRow(left: KeySpec(.toLetters, title: "ABC", units: 1.54, style: .modifier,
                                    accessibilityLabel: "字母"), chinese: chinese),
        ]
    }

    /// 表情页：四行八列，右下角那颗切页键换成地球。
    static func emojiPage() -> [KeyboardRow] {
        let pool = ["😀", "😄", "😅", "😂", "🙂", "😉", "😊", "😍",
                    "😘", "😜", "🤔", "😐", "😴", "😭", "😡", "🥺",
                    "👍", "👎", "👏", "🙏", "💪", "🤝", "✌️", "👀",
                    "❤️", "💔", "✨", "🎉", "🔥", "💡", "✅", "❌"]
        func key(_ ch: String) -> KeySpec { KeySpec(.text(ch), title: ch) }

        var rows: [KeyboardRow] = stride(from: 0, to: 32, by: 8).map { start in
            KeyboardRow(keys: Array(pool[start..<(start + 8)]).map { key($0) }, layout: .filled)
        }
        rows.append(KeyboardRow(keys: [
            KeySpec(.toLetters, title: "ABC", units: 1.54, style: .modifier,
                    accessibilityLabel: "字母"),
            KeySpec(.nextKeyboard, title: "", units: 1.0, style: .modifier,
                    symbol: "globe", accessibilityLabel: "下一输入法"),
            KeySpec(.space, title: "空格", units: 3.66, style: .space, accessibilityLabel: "空格"),
            KeySpec(.newline, title: "换行", units: 2.34, style: .primary, accessibilityLabel: "回车"),
        ], layout: .filled))
        return rows
    }
}

/// 上档键三态。系统键盘就是这个状态机：按一下上档一次，连按两下锁住。
enum ShiftState: Equatable {
    case off, on, locked

    var next: ShiftState {
        switch self {
        case .off:    return .on
        case .on:     return .locked
        case .locked: return .off
        }
    }

    var insertsUppercase: Bool { self != .off }
}
