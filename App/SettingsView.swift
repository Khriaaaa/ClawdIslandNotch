import SwiftUI

/// 设置页：端口 / 监听开关 / 是否自动开实时活动 / 推送地址。
struct SettingsView: View {
    @EnvironmentObject var coordinator: ClawdCoordinator
    @EnvironmentObject var server: StateServer

    var body: some View {
        NavigationStack {
            List {
                Section("监听") {
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
                }

                Section("实时活动") {
                    Toggle(isOn: $coordinator.autoStartLiveActivity) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("收到状态时自动开启实时活动")
                            Text("关闭后仍可在状态页手动开启")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("本机地址") {
                    TextField("例如 192.168.1.23", text: $coordinator.advertisedHost)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("外部代理推送命令")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(coordinator.pushCommandExample)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }

                Section("App Group") {
                    HStack {
                        Text("标识")
                        Spacer()
                        Text(ClawdStore.appGroupID)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Text("App 与 Widget 扩展靠它共享状态。若你改了 bundle id，这里和 entitlements 要一起改。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("能力边界") {
                    Text("App 退到后台后，iOS 会挂起进程，本地 HTTP 监听也随之停止。这一版只在 App 处于前台时可靠接收状态；息屏/长期后台更新需要走 APNs 推送（push-to-start / update token），属于后续阶段，本版本未实现。")
                        .font(.footnote)
                }

                Section("状态映射参考") {
                    ForEach(ClawdState.allCases) { state in
                        HStack(spacing: 10) {
                            Image(state.islandGlyph)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 28, height: 28)
                            Text(state.title)
                            Spacer()
                            Text("优先级 \(String(state.priority))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
