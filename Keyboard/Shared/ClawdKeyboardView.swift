import UIKit

/// 键盘主体。
///
/// 刻意做成一个**不依赖键盘扩展**的普通 UIView：
/// 扩展里的 KeyboardViewController 拿它当真键盘用，
/// 宿主 App 的预览页也拿同一份放进界面 —— 后者是能在 CI 里截到图的关键，
/// 因为模拟器要装上第三方键盘得手动去设置里加，自动化很脆。
final class ClawdKeyboardView: UIView {

    /// 上字的出口
    var sink: KeyboardTextSink? {
        didSet { refreshDynamicTitles() }
    }
    /// 地球键（系统要求必须有，不然过不了审核）
    var onNextKeyboard: (() -> Void)?
    /// 按键音
    var onKeySound: (() -> Void)?

    let strip = PetStripView(frame: .zero)

    private let separator = UIView()
    private var keyViews: [KeyView] = []
    private var rows: [[KeySpec]] = []
    private var isLettersPage = true
    private var shifted = false
    private var theme = KeyboardTheme(dark: true)
    private var pressedIndex: Int?

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true

        addSubview(strip)
        addSubview(separator)
        buildKeys()
        applyTheme()
    }

    required init?(coder: NSCoder) { fatalError("不支持 xib") }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: KeyboardMetrics.totalHeight)
    }

    // MARK: - 布局（全手算，不用 Auto Layout）

    override func layoutSubviews() {
        super.layoutSubviews()

        let width = bounds.width
        strip.frame = CGRect(x: 0, y: 0, width: width, height: KeyboardMetrics.stripHeight)
        separator.frame = CGRect(x: 0, y: KeyboardMetrics.stripHeight,
                                 width: width, height: KeyboardMetrics.separatorHeight)

        var y = KeyboardMetrics.stripHeight + KeyboardMetrics.separatorHeight + KeyboardMetrics.topPadding
        var index = 0

        for row in rows {
            let totalUnits = row.reduce(CGFloat(0)) { $0 + $1.units }
            let gaps = KeyboardMetrics.keySpacing * CGFloat(max(0, row.count - 1))
            let usable = width - KeyboardMetrics.sidePadding * 2 - gaps
            let unit = usable / max(totalUnits, 0.001)

            var x = KeyboardMetrics.sidePadding
            for spec in row {
                let keyWidth = unit * spec.units
                keyViews[index].frame = CGRect(x: x, y: y, width: keyWidth,
                                               height: KeyboardMetrics.rowHeight)
                x += keyWidth + KeyboardMetrics.keySpacing
                index += 1
            }
            y += KeyboardMetrics.rowHeight + KeyboardMetrics.rowSpacing
        }
    }

    // MARK: - 触摸

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let point = touches.first?.location(in: self),
              let index = index(at: point) else { return }
        press(index)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let pressed = pressedIndex,
              let point = touches.first?.location(in: self) else { return }
        // 手指滑走就撤掉高亮；滑到别的键不重复上字（按下即上字，滑动手势不补刀）
        keyViews[pressed].setPressed(keyViews[pressed].frame.contains(point))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { clearPress() }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { clearPress() }

    private func index(at point: CGPoint) -> Int? {
        keyViews.firstIndex { $0.frame.contains(point) }
    }

    private func press(_ index: Int) {
        clearPress()
        pressedIndex = index
        keyViews[index].setPressed(true)
        onKeySound?()
        handle(keyViews[index].spec)
    }

    private func clearPress() {
        if let pressed = pressedIndex {
            keyViews[pressed].setPressed(false)
            pressedIndex = nil
        }
    }

    // MARK: - 按键行为

    private func handle(_ spec: KeySpec) {
        switch spec.action {
        case .text(let text):
            sink?.insert(text)
            if shifted {
                shifted = false
                buildKeys()
            }
            strip.petDidType()

        case .space:
            sink?.insert(" ")
            strip.petDidType()

        case .newline:
            sink?.insert("\n")
            strip.petDidType()

        case .backspace:
            sink?.backspace()
            strip.petDidType()

        case .shift:
            shifted.toggle()
            buildKeys()

        case .toSymbols:
            isLettersPage = false
            shifted = false
            buildKeys()

        case .toLetters:
            isLettersPage = true
            shifted = false
            buildKeys()

        case .nextKeyboard:
            onNextKeyboard?()
        }
    }

    // MARK: - 重建 / 主题

    private func buildKeys() {
        rows = isLettersPage ? KeyboardPages.letterRows(shifted: shifted) : KeyboardPages.symbolRows()

        keyViews.forEach { $0.removeFromSuperview() }
        keyViews = rows.flatMap { $0 }.map { spec in
            let view = KeyView(spec: spec, theme: theme)
            addSubview(view)
            return view
        }

        refreshDynamicTitles()
        setNeedsLayout()
    }

    private func refreshDynamicTitles() {
        guard let sink else { return }

        let dark = sink.isDarkAppearance
        if dark != theme.dark {
            theme = KeyboardTheme(dark: dark)
            applyTheme()
        } else {
            applyTheme()
        }

        let returnTitle = sink.returnKeyTitle
        for view in keyViews where view.spec.action == .newline {
            view.setTitle(returnTitle)
        }
    }

    private func applyTheme() {
        backgroundColor = theme.background
        separator.backgroundColor = theme.separator
        strip.apply(theme: theme)
        keyViews.forEach { $0.apply(theme: theme) }
    }
}
