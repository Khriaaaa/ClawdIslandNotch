import SwiftUI

/// 设置页：作息表 / 实时活动 / 外部推送（可选，默认关）/ App Group / 素材一览。
struct SettingsView: View {
    @EnvironmentObject var coordinator: ClawdCoordinator
    @EnvironmentObject var server: StateServer

    var body: some View {
        NavigationStack {
            List {
                Section("作息") {
                    HStack {
                        Text("现在")
                        Spacer()
                        Text(ClawdBiorhythm.shift(at: Date()).title)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(ClawdBiorhythm.Shift.allCases, id: \.self) { shift in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(shift.title)
                                Spacer()
                                Text(shift.hours)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text(shift.summary)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Text("按真实时钟掷节拍，一段演完再掷下一段。键盘上那一路是打字跟随：每敲一个键它跟着敲一下，停手就回到当时的节拍。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("实时活动") {
                    Toggle(isOn: $coordinator.autoStartLiveActivity) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("自动开启实时活动")
                            Text("锁屏 / 灵动岛跟着作息换姿势")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text("实时活动最快 45 秒换一次：系统对更新有预算，按秒换会被降频。这一面也跑不了持续动画，每个状态是一张静态图加一次进场缩放。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("外部状态推送（可选，默认关）") {
                    Toggle(isOn: Binding(
                        get: { coordinator.serverEnabled },
                        set: { coordinator.setServerEnabled($0) }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("启动本地状态服务器")
                            Text("在 23333-23337 里挑一个可用端口")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack {
                        Text("当前端口")
                        Spacer()
                        Text(server.boundPort.map { String($0) } ?? (server.isRunning ? "绑定中…" : "未运行"))
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    TextField("例如 192.168.1.23", text: $coordinator.advertisedHost)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("推送命令")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(coordinator.pushCommandExample)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }

                    Text("Clawd 不靠这个活着 —— 打开它只意味着「别人推来的状态会被记进流水」，姿势仍旧按作息走。这是留给以后想接代理干活的钩子。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("App Group") {
                    HStack {
                        Text("标识")
                        Spacer()
                        Text(ClawdStore.appGroupID)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Text("App 与 Widget 扩展靠它共享姿势。若你改了 bundle id，这里和 entitlements 要一起改。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("素材一览") {
                    ForEach(ClawdState.allCases) { state in
                        HStack(spacing: 10) {
                            Image(state.islandGlyph)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 28, height: 28)
                            Text(state.title)
                            Spacer()
                            Text(state.rawValue)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("能力边界") {
                    Text("App 退到后台后 iOS 会挂起进程，主屏 / 锁屏的刷新靠系统时间线预算，不会按秒跟上。想要「切到别的 App 也贴着屏幕」在 iPhone 上没有公开 API，这一版不做。")
                        .font(.footnote)
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
