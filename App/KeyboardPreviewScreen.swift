import SwiftUI

/// 宿主 App 里的键盘预览页：把扩展里那份 ClawdKeyboardView 原样搬进来跑。
/// 一是真机上不用去设置里装键盘就能试手感，二是 CI 里能直接截图。
///
/// 注意这只进假 sink，不写进任何真实的输入框 —— 页面里写了说明，
/// 免得看着像真键盘却存不了字。
struct KeyboardPreviewScreen: View {
    @StateObject private var model = KeyboardPreviewModel()

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("这是键盘扩展里那块视图，原样搬进 App 跑。这里敲的键只进下面这个假输入框，不会写进别的 App。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("输入框")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(model.text.isEmpty ? "敲下面的键盘试试…" : model.text)
                            .font(.system(size: 16, design: .monospaced))
                            .foregroundStyle(model.text.isEmpty ? .secondary : .primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
                    }

                    HStack(spacing: 14) {
                        Label("活动条 \(String(Int(KeyboardMetrics.stripHeight)))pt", systemImage: "ruler")
                        Label("键盘总高 \(String(Int(KeyboardMetrics.totalHeight)))pt", systemImage: "keyboard")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("在真机上用真键盘：设置 → 通用 → 键盘 → 键盘 → 添加新键盘 → ClawdIsland")
                        Text("加完再点一次输入框，用左下角的地球切过来。想让它读 Claude Code 的状态，还要在这个键盘上打开「完全访问」")
                        Text("不过 ClawdIsland 退到后台收不到推送，那一格读到的是你离开时最后一帧 —— 想看实时状态得让 App 留在前台")
                        Text("点一下 Clawd 它会开心；连敲几个键看它敲键盘；放着不动 45 秒它会睡着")
                        Text("⇧ 按一下上档一次，连按两下锁住；退格长按连删；空格双击出句号；「中英」长按切输入法")
                    }
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Label("打开系统设置", systemImage: "gear")
                            .font(.footnote)
                    }
                }
                .padding()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            KeyboardHostView(model: model)
                .frame(height: KeyboardMetrics.totalHeight)
        }
        .background(Color(white: 0.09))
        .preferredColorScheme(.dark)
        .navigationTitle("键盘")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// 把 ClawdKeyboardView 塞进 SwiftUI
struct KeyboardHostView: UIViewRepresentable {
    let model: KeyboardPreviewModel

    func makeUIView(context: Context) -> ClawdKeyboardView {
        let view = ClawdKeyboardView(frame: .zero)
        view.sink = model.sink
        // 真机上系统多半会说要能切输入法，预览里也按 true 画，好让截图带上那颗地球角标
        view.needsInputModeSwitchKey = true
        view.onKeySound = { UIDevice.current.playInputClick() }

        // CI 自检：simctl 没有 tap 命令，截图又只是静止画面，「点第四行表情键」
        // 那条路径从来没被跑过 —— pi 第三轮抓到的越界崩就是这么漏出去的。
        // 打开 CLAWD_KB_SELFTEST=1 就让宿主真的走一遍那段代码，结果落盘给 CI 读。
        if ProcessInfo.processInfo.environment["CLAWD_KB_SELFTEST"] == "1" {
            // 别用 try? 吞错误。全新安装时 Documents 目录可能还没建出来，第一次写盘
            // 会失败而没人知道 —— 那份文件于是等到第二段才带着三行一起冒出来，
            // CI 把「等第一行」等成了「等第三行」，shot-6 拍的是关掉地球那版。
            // 建目录 + 不吞错，写不进去就让 CI 等超时变红。
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            if let docs {
                // 这里不吞错：建不出目录后面必然写不出文件，CI 会等超时变红。
                // 吞掉的话红的是「等不到那行」，看不出是权限/路径问题。
                do { try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true) }
                catch { NSLog("Clawd 自检建 Documents 目录失败：\(error)") }
            }
            let url = docs?.appendingPathComponent("selftest.txt")
            let goURL = docs?.appendingPathComponent("selftest-go2")
            var lines: [String] = []
            func flush() {
                guard let url else { return }
                do { try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8) }
                catch { NSLog("Clawd 自检落盘失败：\(error)") }
            }
            // 末行是终判，CI 只认这一行。判定用白名单，不是「找 SELFTEST FAIL」：
            // 后者是张已知失败清单，以后再加一段自检、返回一句别的失败文本
            // （SELFTEST ABORT …），它没在清单里，判定会算成 PASS —— 又是假绿灯。
            func runSecondAndVerdict() {
                lines.append(contentsOf: view.runGlobeRecheckSelfTest())
                let ok = !lines.isEmpty && lines.allSatisfy { $0.hasPrefix("SELFTEST OK") }
                lines.append("SELFTEST VERDICT " + (ok ? "PASS" : "FAIL"))
                flush()
            }
            // 第二段由 CI 放信号文件触发，不靠秒数。用计时器的话，第一次写盘要是慢了，
            // CI 等到第一行时第二段可能已经跑完，shot-6 拍到的就是关掉地球那版 ——
            // 信号握手之后，shot-6 必然拍在第二段之前。
            // 信号最多等 60 秒（0.5s × 120）。原来是无上限自递归：信号不来就永久轮询、
            // App 永不退出，只能靠 CI 那边的 40 秒超时兜底 —— 那等于把「自检卡死」
            // 伪装成「CI 超时」，看不出是谁的问题。超时后写一行明确的失败文本。
            func waitForGo(attempt: Int = 0) {
                guard let goURL else { return }
                if FileManager.default.fileExists(atPath: goURL.path) {
                    runSecondAndVerdict()
                    return
                }
                if attempt >= 120 {
                    lines.append("SELFTEST ABORT 等 selftest-go2 信号超时 60s")
                    flush()
                    return
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { waitForGo(attempt: attempt + 1) }
            }

            // 第一段跑完停在表情页（底行带地球），CI 等的就是这一行、拍的也是这个状态
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                lines.append(contentsOf: view.runEmojiTapSelfTest())
                flush()
                waitForGo()
            }
        }
        return view
    }

    func updateUIView(_ uiView: ClawdKeyboardView, context: Context) {
        uiView.sink = model.sink
    }
}

/// 预览用的假输入源：把上字送进 SwiftUI 的 @Published
final class PreviewTextSink: KeyboardTextSink {
    var onInsert: ((String) -> Void)?
    var onBackspace: (() -> Void)?

    func insert(_ text: String) { onInsert?(text) }
    func backspace() { onBackspace?() }

    var returnKeyTitle: String { "发送" }
    var isDarkAppearance: Bool { true }
}

final class KeyboardPreviewModel: ObservableObject {
    @Published var text: String = ""

    private(set) lazy var sink: PreviewTextSink = {
        let sink = PreviewTextSink()
        sink.onInsert = { [weak self] text in
            guard let self else { return }
            self.text += text.replacingOccurrences(of: "\n", with: "")
            if self.text.count > 160 { self.text = String(self.text.suffix(160)) }
        }
        sink.onBackspace = { [weak self] in
            guard let self, !self.text.isEmpty else { return }
            self.text.removeLast()
        }
        return sink
    }()
}
