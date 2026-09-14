import UIKit

/// 键盘主体。
///
/// 刻意做成一个**不依赖键盘扩展**的普通 UIView：
/// 扩展里的 KeyboardViewController 拿它当真键盘用，
/// 宿主 App 的预览页也拿同一份放进界面 —— 后者是能在 CI 里截到图的关键，
/// 因为模拟器要装上第三方键盘得手动去设置里加，自动化很脆。
final class ClawdKeyboardView: UIView {

    enum Page { case letters, symbols, moreSymbols, emoji }

    /// 上字的出口
    var sink: KeyboardTextSink? {
        didSet { refreshDynamicTitles() }
    }
    /// 地球键 / 长按切输入法
    var onNextKeyboard: (() -> Void)?
    /// 长按「中英」要弹系统输入法列表
    var onInputModeList: (() -> Void)?
    /// 收起键盘
    var onDismiss: (() -> Void)?
    /// 按键音
    var onKeySound: (() -> Void)?

    /// 系统说需要能切输入法时，在「中英」那颗键上挂个地球角标
    var needsInputModeSwitchKey = false {
        didSet { applyInputModeBadge() }
    }

    let strip = PetStripView(frame: .zero)

    private var keyViews: [KeyView] = []
    private var rows: [KeyboardRow] = []
    private var page: Page = .letters
    private var shift: ShiftState = .off
    private var chinesePunctuation = true
    private var theme = KeyboardTheme(dark: true)
    private var pressedIndex: Int?

    private var backspaceTimer: Timer?
    private var inputModeTimer: Timer?
    private var lastSpaceTime: CFTimeInterval = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true

        addSubview(strip)
        strip.onToolAction = { [weak self] action in self?.handleTool(action) }

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

        let avail = width - KeyboardMetrics.sidePadding * 2
        let spacing = KeyboardMetrics.keySpacing

        // 基准键宽：只看 filled 行，取各自解出来的最小值，
        // 这样 centered 行（九个字母那行）沿用同一个键宽，不会比第一行胖。
        var baseUnit = CGFloat.greatestFiniteMagnitude
        for row in rows where row.layout == .filled {
            let units = row.keys.reduce(CGFloat(0)) { $0 + $1.units }
            let gaps = spacing * CGFloat(max(0, row.keys.count - 1))
            guard units > 0 else { continue }
            baseUnit = min(baseUnit, (avail - gaps) / units)
        }
        if !baseUnit.isFinite { baseUnit = 30 }

        var y = KeyboardMetrics.stripHeight + KeyboardMetrics.topPadding
        var index = 0

        for row in rows {
            let gaps = spacing * CGFloat(max(0, row.keys.count - 1))
            let units = row.keys.reduce(CGFloat(0)) { $0 + $1.units }

            switch row.layout {
            case .filled:
                let unitW = (avail - gaps) / max(units, 0.001)
                var x = KeyboardMetrics.sidePadding
                for spec in row.keys {
                    let w = unitW * spec.units
                    place(index, x: x, y: y, width: w)
                    x += w + spacing
                    index += 1
                }

            case .centered:
                let rowW = units * baseUnit + gaps
                var x = (width - rowW) / 2
                for spec in row.keys {
                    let w = baseUnit * spec.units
                    place(index, x: x, y: y, width: w)
                    x += w + spacing
                    index += 1
                }

            case .edgePinned:
                // 首尾贴边，中间一段在剩下的空档里整体居中
                let firstW = (row.keys.first?.units ?? 1) * baseUnit
                let lastW = (row.keys.last?.units ?? 1) * baseUnit
                place(index, x: KeyboardMetrics.sidePadding, y: y, width: firstW)
                index += 1

                let middle = Array(row.keys.dropFirst().dropLast())
                let middleW = middle.reduce(CGFloat(0)) { $0 + $1.units } * baseUnit
                    + spacing * CGFloat(max(0, middle.count - 1))
                let spanStart = KeyboardMetrics.sidePadding + firstW + spacing
                let spanEnd = width - KeyboardMetrics.sidePadding - lastW - spacing
                var x = spanStart + max(0, (spanEnd - spanStart - middleW) / 2)
                for spec in middle {
                    let w = baseUnit * spec.units
                    place(index, x: x, y: y, width: w)
                    x += w + spacing
                    index += 1
                }

                place(index, x: width - KeyboardMetrics.sidePadding - lastW, y: y, width: lastW)
                index += 1
            }
            y += KeyboardMetrics.rowHeight + KeyboardMetrics.rowSpacing
        }
    }

    private func place(_ index: Int, x: CGFloat, y: CGFloat, width: CGFloat) {
        guard index < keyViews.count else { return }
        keyViews[index].frame = CGRect(x: x, y: y, width: width,
                                       height: KeyboardMetrics.rowHeight)
    }

    // MARK: - 触摸

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let point = touches.first?.location(in: self),
              let index = index(at: point) else { return }
        press(index)

        // 退格长按连删：先等一下再开始重复，不然轻点会多删
        if keyViews[index].spec.action == .backspace {
            startBackspaceRepeat()
        }
        // 「中英」和地球键长按 = 切输入法，跟系统那颗一个手感
        if keyViews[index].spec.action == .toggleLanguage
            || keyViews[index].spec.action == .nextKeyboard {
            startInputModeTimer()
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let pressed = pressedIndex, pressed < keyViews.count,
              let point = touches.first?.location(in: self) else { return }
        // 手指滑走就撤掉高亮；滑到别的键不重复上字（按下即上字，滑动手势不补刀）
        let stillIn = keyViews[pressed].frame.contains(point)
        keyViews[pressed].setPressed(stillIn)
        if !stillIn { stopBackspaceRepeat() }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        stopBackspaceRepeat()
        stopInputModeTimer()
        clearPress()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        stopBackspaceRepeat()
        stopInputModeTimer()
        clearPress()
    }

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
        if let pressed = pressedIndex, pressed < keyViews.count {
            keyViews[pressed].setPressed(false)
        }
        pressedIndex = nil
    }

    private func startBackspaceRepeat() {
        stopBackspaceRepeat()
        backspaceTimer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.backspaceTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
                guard let self else { return }
                self.sink?.backspace()
                self.strip.petDidType()
            }
            RunLoop.main.add(self.backspaceTimer!, forMode: .common)
        }
        RunLoop.main.add(backspaceTimer!, forMode: .common)
    }

    private func stopBackspaceRepeat() {
        backspaceTimer?.invalidate()
        backspaceTimer = nil
    }

    private func startInputModeTimer() {
        stopInputModeTimer()
        inputModeTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            self?.onNextKeyboard?()
        }
        if let t = inputModeTimer { RunLoop.main.add(t, forMode: .common) }
    }

    private func stopInputModeTimer() {
        inputModeTimer?.invalidate()
        inputModeTimer = nil
    }

    // MARK: - 按键行为

    private func handle(_ spec: KeySpec) {
        switch spec.action {
        case .text(let text):
            sink?.insert(shift.insertsUppercase ? text.uppercased() : text)
            if shift == .on { shift = .off; rebuild() }
            strip.petDidType()

        case .space:
            let now = CACurrentMediaTime()
            if now - lastSpaceTime < 0.45 {
                // 双击空格出句号，跟系统键盘一致
                sink?.backspace()
                sink?.insert(chinesePunctuation ? "。" : ". ")
            } else {
                sink?.insert(" ")
            }
            lastSpaceTime = now
            strip.petDidType()

        case .punctuation:
            sink?.insert(KeyboardPages.punctText(chinese: chinesePunctuation))
            strip.petDidType()

        case .newline:
            sink?.insert("\n")
            strip.petDidType()

        case .backspace:
            sink?.backspace()
            strip.petDidType()

        case .clipboard:
            // 剪贴板要「完全访问」才读得到；没开就什么都不做，别崩
            if let text = UIPasteboard.general.string, !text.isEmpty {
                sink?.insert(text)
                strip.petDidType()
            }

        case .shift:
            shift = shift.next
            rebuild()

        case .toSymbols:
            page = .symbols; shift = .off; rebuild()

        case .toMoreSymbols:
            page = .moreSymbols; shift = .off; rebuild()

        case .toLetters:
            page = .letters; shift = .off; rebuild()

        case .toEmoji:
            page = .emoji; shift = .off; rebuild()

        case .toggleLanguage:
            chinesePunctuation.toggle()
            rebuild()

        case .dismiss:
            onDismiss?()

        case .nextKeyboard:
            onNextKeyboard?()
        }
    }

    private func handleTool(_ action: KeyAction) {
        switch action {
        case .toggleLanguage:
            chinesePunctuation.toggle()
            rebuild()
        default:
            handle(action)
        }
    }

    // MARK: - 重建 / 主题

    private func buildRows() -> [KeyboardRow] {
        switch page {
        case .letters:     return KeyboardPages.letterPage(shift: shift, chinese: chinesePunctuation)
        case .symbols:     return KeyboardPages.symbolPage(chinese: chinesePunctuation)
        case .moreSymbols: return KeyboardPages.moreSymbolPage(chinese: chinesePunctuation)
        case .emoji:       return KeyboardPages.emojiPage()
        }
    }

    private func rebuild() {
        buildKeys()
        // 新键的 frame 还是 .zero，不立刻排一次的话 touchesMoved 拿到的
        // 是零矩形，按下的高亮会瞬间消失
        layoutIfNeeded()
    }

    private func buildKeys() {
        rows = buildRows()

        keyViews.forEach { $0.removeFromSuperview() }
        keyViews = rows.flatMap { $0.keys }.map { spec in
            let view = KeyView(spec: spec, theme: theme)
            addSubview(view)
            return view
        }

        applyInputModeBadge()
        refreshDynamicTitles()
        setNeedsLayout()
    }

    private func applyInputModeBadge() {
        for view in keyViews where view.spec.action == .toggleLanguage {
            view.setBadge(needsInputModeSwitchKey ? "globe" : nil)
        }
    }

    private func refreshDynamicTitles() {
        guard let sink else { return }

        let dark = sink.isDarkAppearance
        theme = KeyboardTheme(dark: dark)
        applyTheme()

        let returnTitle = sink.returnKeyTitle
        for view in keyViews where view.spec.action == .newline {
            view.setTitle(returnTitle)
        }
    }

    private func applyTheme() {
        backgroundColor = theme.background
        strip.apply(theme: theme)
        keyViews.forEach { $0.apply(theme: theme) }
        applyInputModeBadge()
    }

    // MARK: - 外部状态

    /// Claude Code 在干活 / 在等批准 / 出错，直接驱动 Clawd 的姿势
    func setExternalState(_ state: PetStripView.Mood?) {
        strip.setExternalState(state)
    }
}
