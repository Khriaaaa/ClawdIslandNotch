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
    ///
    /// 长按走的是 `advanceToNextInputMode()`（切下一个），不是
    /// `handleInputModeList(from:with:)`（弹列表）。后者要一个真的 UIEvent，
    /// 官方做法是把触发键做成 UIControl 再 `addTarget(_:action:for: .allTouchEvents)`，
    /// 让 UIKit 自己把 view 和 event 递进来；光靠 touchesBegan 拿不到，也没有
    /// 官方途径手搓 UIEvent，社区里照抄那个写法有 SIGQUIT 崩溃的报告。
    /// 要真弹列表得把 KeyView 改成 UIControl —— 那是另一件事，先不为它冒险。
    var onNextKeyboard: (() -> Void)?
    /// 收起键盘
    var onDismiss: (() -> Void)?
    /// 按键音
    var onKeySound: (() -> Void)?

    /// 系统说需要能切输入法时，在「中英」那颗键上挂个地球角标
    var needsInputModeSwitchKey = false {
        didSet {
            guard oldValue != needsInputModeSwitchKey else { return }
            applyInputModeBadge()
            // 表情页底行那颗地球的「在不在」是 buildRows() 里定死的键集合，
            // 光刷角标改不了已经建好的页。同一台键盘从「要切输入法」的输入框
            // 换到「不要」的输入框（viewWillAppear 会重设这个值）时就会露馅：
            // 底行停在旧形态，直到用户手动切一次页。
            if page == .emoji { rebuild() }
        }
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
        tapKey(at: index)
    }

    /// 按下第 index 颗键。从 touchesBegan 里抽出来，为的是让模拟器自检
    /// （runEmojiTapSelfTest）调的是**同一段代码**，不是照抄一份。
    /// simctl 没有 tap 命令，CI 又是靠截静止画面，这颗键以前从来没被点过 ——
    /// pi 第三轮抓到的越界崩就是这么漏出去的。
    func tapKey(at index: Int) {
        guard index >= 0, index < keyViews.count else { return }

        // action 必须先取走再 press：press → handle → 切页 rebuild() 会把
        // keyViews 整个换成新页的数组，之后再用旧 index 下标就崩。
        // 点第四行表情键就是这条：字母页 34 键、index 29，切到表情页只剩 27/28 键
        // （底行那颗地球按 needsInputModeSwitchKey 决定在不在）。
        let action = keyViews[index].spec.action
        press(index)

        // 退格长按连删：先等一下再开始重复，不然轻点会多删
        if action == .backspace {
            startBackspaceRepeat()
        }
        // 「中英」长按 = 切下一个输入法。地球键是按下即切，不能再挂长按，
        // 不然一次按出两次。只有一套输入法时没得切，也就不起计时器
        if action == .toggleLanguage, needsInputModeSwitchKey {
            startInputModeTimer()
        }
    }

    /// 模拟器自检第一段：真的走一遍「从字母页点第四行的表情键」。
    /// 越界那条要是回来了，这里会直接崩，CI 就看不到结果文件。
    ///
    /// 自己作判定，不只是把数字打出来 —— 光打印的话，哪天 `perform(.toEmoji)`
    /// 里的切页被改坏，文本照样好看（`34 键 -> 34 键，停在 letters 页`），
    /// CI 照样绿。一个自己不作判定的测试比没有测试更坏。
    func runEmojiTapSelfTest() -> [String] {
        guard page == .letters else { return ["SELFTEST FAIL 自检要在字母页起跑，当前是 \(page)"] }
        guard let index = keyViews.firstIndex(where: { $0.spec.action == .toEmoji }) else {
            return ["SELFTEST FAIL 字母页里找不到表情键"]
        }

        let before = keyViews.count
        tapKey(at: index)
        guard page == .emoji, keyViews.count != before else {
            return ["SELFTEST FAIL 点了表情键没切页：\(before) 键 -> \(keyViews.count) 键，停在 \(page) 页"]
        }
        let line = "SELFTEST OK 点第 \(index) 颗（表情）\(before) 键 -> \(keyViews.count) 键，停在 \(page) 页"
        print(line)
        return [line]
    }

    /// 第二段：地球键的去留是 `buildRows()` 里定死的键集合，`didSet` 得把已经
    /// 建好的表情页重建掉。宿主故意晚 10 秒才跑这段 —— 中间那张截图要拍到
    /// 「底行带地球」那版，两张都留证据。
    func runGlobeRecheckSelfTest() -> [String] {
        guard page == .emoji, needsInputModeSwitchKey else {
            return ["SELFTEST FAIL 第二段要在带地球的表情页上跑，当前 \(page) 页 / 地球 \(needsInputModeSwitchKey)"]
        }
        let withGlobe = keyViews.count
        needsInputModeSwitchKey = false
        guard keyViews.count == withGlobe - 1 else {
            return ["SELFTEST FAIL 关掉地球后底行没按预期变：\(withGlobe) 键 -> \(keyViews.count) 键（应少一颗）"]
        }
        let line = "SELFTEST OK2 关掉地球 \(withGlobe) 键 -> \(keyViews.count) 键（已重建）"
        print(line)
        return [line]
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let pressed = pressedIndex, pressed < keyViews.count,
              let point = touches.first?.location(in: self) else { return }
        // 手指滑走就撤掉高亮；滑到别的键不重复上字（按下即上字，滑动手势不补刀）
        let stillIn = keyViews[pressed].frame.contains(point)
        keyViews[pressed].setPressed(stillIn)
        if !stillIn {
            stopBackspaceRepeat()
            // 手指滑走了就别再切输入法
            stopInputModeTimer()
        }
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

    /// 键盘在按住的时候被系统收掉，Timer 还挂在 runloop 上会继续删字；
    /// pressedIndex 是唯一会跨 rebuild() 活下来的触摸状态，UIKit 不递
    /// touchesCancelled 的话高亮会留在键上，下次弹键盘那颗键还亮着
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            stopBackspaceRepeat()
            stopInputModeTimer()
            clearPress()
        }
    }

    private func index(at point: CGPoint) -> Int? {
        keyViews.firstIndex { $0.frame.contains(point) }
    }

    private func press(_ index: Int) {
        // 按下后可能已经切页重建过 keyViews，兜一道免得越界
        guard index < keyViews.count else { return }
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
            guard let self else { return }
            // 长按是「换输入法」，不该顺带把标点模式翻掉 —— 按下的那一瞬间
            // perform(.toggleLanguage) 已经翻过一次了，这里翻回来。
            // 用户换完输入法再切回来，标点还是他原来那个模式。
            self.chinesePunctuation.toggle()
            self.rebuild()
            self.onNextKeyboard?()
        }
        if let t = inputModeTimer { RunLoop.main.add(t, forMode: .common) }
    }

    private func stopInputModeTimer() {
        inputModeTimer?.invalidate()
        inputModeTimer = nil
    }

    // MARK: - 按键行为

    private func handle(_ spec: KeySpec) { perform(spec.action) }

    /// 按键行为。按键和工具条按钮共用这一份，所以吃的是 KeyAction 不是 KeySpec
    private func perform(_ action: KeyAction) {
        switch action {
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

    private func handleTool(_ action: KeyAction) { perform(action) }

    // MARK: - 重建 / 主题

    private func buildRows() -> [KeyboardRow] {
        switch page {
        case .letters:     return KeyboardPages.letterPage(shift: shift, chinese: chinesePunctuation)
        case .symbols:     return KeyboardPages.symbolPage(chinese: chinesePunctuation)
        case .moreSymbols: return KeyboardPages.moreSymbolPage(chinese: chinesePunctuation)
        case .emoji:       return KeyboardPages.emojiPage(showInputModeSwitchKey: needsInputModeSwitchKey)
        }
    }

    private func rebuild() {
        // 重建后按下那颗键换了对象，高亮按 action 找回来；
        // 不然轻则高亮消失、重则 pressedIndex 指到新页的另一颗键
        let keep = pressedIndex.flatMap { $0 < keyViews.count ? keyViews[$0].spec.action : nil }
        buildKeys()
        // 新键的 frame 还是 .zero，不立刻排一次的话 touchesMoved 拿到的
        // 是零矩形，按下的高亮会瞬间消失
        layoutIfNeeded()
        if let keep, let idx = keyViews.firstIndex(where: { $0.spec.action == keep }) {
            pressedIndex = idx
            keyViews[idx].setPressed(true)
        } else {
            pressedIndex = nil
        }
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
