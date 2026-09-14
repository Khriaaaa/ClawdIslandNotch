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
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                let lines = view.runEmojiTapSelfTest()
                guard let dir = FileManager.default.urls(for: .documentDirectory,
                                                         in: .userDomainMask).first else { return }
                try? lines.joined(separator: "\n").write(
                    to: dir.appendingPathComponent("selftest.txt"),
                    atomically: true, encoding: .utf8)
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
