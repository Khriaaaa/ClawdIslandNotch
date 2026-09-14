import SwiftUI

/// 主界面：当前状态面板 + 会话信息 + 启停按钮 + 手动切状态 + 最近事件。
struct ContentView: View {
    @EnvironmentObject var coordinator: ClawdCoordinator
    @State private var selection = 0

    var body: some View {
        TabView(selection: $selection) {
            StatusTab()
                .tag(0)
                .tabItem { Label("状态", systemImage: "pawprint.fill") }
            NotchPetScreen()
                .tag(1)
                .tabItem { Label("刘海", systemImage: "iphone") }
            SettingsView()
                .tag(2)
                .tabItem { Label("设置", systemImage: "gearshape.fill") }
        }
        // 锁屏小组件 / 实时活动里的 widgetURL 落到这里。
        .onOpenURL { url in
            if url.scheme == NotchDeepLink.scheme { selection = 1 }
        }
    }
}

struct StatusTab: View {
    @EnvironmentObject var coordinator: ClawdCoordinator
    @EnvironmentObject var server: StateServer
    @EnvironmentObject var activities: ActivityController

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    petCard
                    controlCard
                    serverCard
                    eventCard
                }
                .padding()
            }
            .navigationTitle("Clawd Island")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - 桌宠卡片

    private var petCard: some View {
        VStack(spacing: 12) {
            Image(coordinator.snapshot.imageName)
                .resizable()
                .scaledToFit()
                .frame(height: 140)
                .padding(.top, 8)

            Text(coordinator.snapshot.stateTitle)
                .font(.title2)
                .fontWeight(.semibold)

            if !coordinator.snapshot.sessionTitle.isEmpty {
                Text(coordinator.snapshot.sessionTitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if !coordinator.snapshot.detail.isEmpty {
                Text(coordinator.snapshot.detail)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            HStack(spacing: 16) {
                Label(coordinator.snapshot.agentId.isEmpty ? "未知来源" : coordinator.snapshot.agentId,
                      systemImage: "person.crop.circle")
                Label {
                    if coordinator.snapshot.updatedAt == Date(timeIntervalSince1970: 0) {
                        Text("尚未收到推送")
                    } else {
                        Text(coordinator.snapshot.updatedAt, style: .relative)
                    }
                } icon: {
                    Image(systemName: "clock")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Picker("手动切换状态", selection: Binding(
                get: { coordinator.snapshot.state },
                set: { coordinator.manualSet($0) }
            )) {
                ForEach(ClawdState.allCases) { state in
                    Text(state.title).tag(state)
                }
            }
            .pickerStyle(.menu)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    // MARK: - 控制卡片

    private var controlCard: some View {
        VStack(spacing: 12) {
            HStack {
                Label(coordinator.serverEnabled ? "本地监听已开启" : "监听已停止",
                      systemImage: coordinator.serverEnabled ? "dot.radiowaves.left.and.right" : "wifi.slash")
                Spacer()
                Text(server.boundPort.map { "\($0)" } ?? "—")
                    .font(.system(.body, design: .monospaced))
            }

            Button {
                coordinator.setServerEnabled(!coordinator.serverEnabled)
            } label: {
                Label(coordinator.serverEnabled ? "停止监听" : "启动监听",
                      systemImage: coordinator.serverEnabled ? "stop.circle" : "play.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Button {
                coordinator.toggleLiveActivity()
            } label: {
                Label(activities.isActive ? "结束实时活动" : "开启实时活动",
                      systemImage: activities.isActive ? "stop.circle" : "bolt.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            if let error = server.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let error = activities.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    // MARK: - 服务器卡片

    private var serverCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("推送地址")
                .font(.headline)
            Text("POST  http://<本机局域网IP>:\(server.boundPort.map { String($0) } ?? "23333")/state")
                .font(.system(.footnote, design: .monospaced))
                .textSelection(.enabled)
            Text("响应头会带 x-clawd-server: clawd-on-desk，代理插件靠它确认对端。已接收 \(server.requestCount) 条。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    // MARK: - 最近事件

    private var eventCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("最近事件")
                    .font(.headline)
                Spacer()
                Button("清空") { coordinator.clearHistory() }
                    .font(.caption)
            }

            if coordinator.events.isEmpty {
                Text("还没有收到任何状态推送。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(coordinator.events.prefix(20)) { event in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: event.state.symbolName)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(event.state.title) · \(event.event ?? "-")")
                                .font(.subheadline)
                            Text(eventRowDetail(event))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Text(event.receivedAt, style: .time)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Divider()
                }
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    private func eventRowDetail(_ event: ClawdEvent) -> String {
        var parts: [String] = []
        if let agent = event.agentId, !agent.isEmpty { parts.append(agent) }
        if let session = event.sessionTitle, !session.isEmpty { parts.append(session) }
        if let tool = event.toolName, !tool.isEmpty { parts.append(tool) }
        if parts.isEmpty, let cwd = event.cwd { parts.append(cwd) }
        return parts.joined(separator: " · ")
    }
}
