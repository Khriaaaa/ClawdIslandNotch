import SwiftUI

/// 宿主 App 里的键盘预览页：把扩展里那份 ClawdKeyboardView 原样搬进来跑。
/// 一是真机上不用去设置里装键盘就能试手感，二是 CI 里能直接截图。
struct KeyboardPreviewScreen: View {
    @StateObject private var model = KeyboardPreviewModel()

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("这是键盘扩展里那块视图，原样搬进 App 跑")
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
                        Label("活动条 \(Int(KeyboardMetrics.stripHeight))pt", systemImage: "ruler")
                        Label("键盘总高 \(Int(KeyboardMetrics.totalHeight))pt", systemImage: "keyboard")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Text("点一下 Clawd 它会开心；连敲几个键看它敲键盘；放着不动 45 秒它会睡着")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
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
        view.onKeySound = { UIDevice.current.playInputClick() }
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
