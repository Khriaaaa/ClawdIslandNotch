import SwiftUI
import Foundation

@main
struct ClawdIslandApp: App {
    @StateObject private var coordinator = ClawdCoordinator()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(coordinator)
                .environmentObject(coordinator.server)
                .environmentObject(coordinator.activities)
                .onAppear { coordinator.bootstrap() }
                .onChange(of: scenePhase) { _, phase in
                    // 回到前台时重读 App Group：Widget 的交互按钮可能已经改过状态。
                    if phase == .active {
                        coordinator.reloadFromStore()
                    }
                }
        }
    }
}

/// App 的装配层：把 StateServer / ActivityController / ClawdStore 串起来。
///
/// 数据流：
///   外部代理 --HTTP POST /state--> StateServer
///        --> ClawdEvent
///        --> StateGate（最小展示时长 + 优先级）
///        --> ClawdSnapshot
///        --> ClawdStore（App Group，落盘给 Widget）
///        --> ActivityController（Live Activity update）
///        --> WidgetCenter.reloadAllTimelines()
@MainActor
final class ClawdCoordinator: ObservableObject {

    @Published private(set) var snapshot: ClawdSnapshot
    @Published private(set) var events: [ClawdEvent]

    /// 设置项。持久化在 App 自己的 UserDefaults（Widget 不需要）。
    @Published var serverEnabled: Bool {
        didSet {
            UserDefaults.standard.set(serverEnabled, forKey: Keys.serverEnabled)
            syncServer()
        }
    }
    @Published var autoStartLiveActivity: Bool {
        didSet {
            UserDefaults.standard.set(autoStartLiveActivity, forKey: Keys.autoStartLiveActivity)
        }
    }
    /// 设置页展示用：外部代理应该往哪个地址推。
    @Published var advertisedHost: String {
        didSet { UserDefaults.standard.set(advertisedHost, forKey: Keys.advertisedHost) }
    }

    let server = StateServer()
    let activities = ActivityController()

    private var gate: StateGate
    private var fallbackTimer: Timer?
    private var sessionStartedAt: Date
    private var sessionId: String = "clawd:default"

    private enum Keys {
        static let serverEnabled = "clawd.serverEnabled"
        static let autoStartLiveActivity = "clawd.autoStartLiveActivity"
        static let advertisedHost = "clawd.advertisedHost"
    }

    init() {
        let stored = ClawdStore.loadSnapshot()
        let hasStored = stored.updatedAt != Date(timeIntervalSince1970: 0)
        let initial = hasStored ? stored.state : ClawdState.sleeping
        self.snapshot = hasStored ? stored : .empty
        self.events = ClawdStore.loadEvents()
        self.gate = StateGate(initial: initial)
        self.sessionStartedAt = hasStored ? stored.sessionStartedAt : Date()

        let defaults = UserDefaults.standard
        self.serverEnabled = defaults.object(forKey: Keys.serverEnabled) as? Bool ?? true
        self.autoStartLiveActivity = defaults.object(forKey: Keys.autoStartLiveActivity) as? Bool ?? true
        self.advertisedHost = defaults.string(forKey: Keys.advertisedHost) ?? ""

        server.onEvent = { [weak self] event in
            // StateServer 已经从主队列回调；这里显式跳到 MainActor，
            // 免得依赖非 Sendable 闭包的隐式 isolation 推断。
            Task { @MainActor in
                self?.handle(event)
            }
        }
    }

    // 注：coordinator 生命周期与 App 相同，不需要 deinit 清理 Timer。

    // MARK: - 生命周期

    func bootstrap() {
        activities.adoptExistingActivity()
        if serverEnabled && !server.isRunning {
            server.start()
        }
        if autoStartLiveActivity && !activities.isActive {
            activities.start(snapshot: snapshot, sessionId: sessionId)
        }
        startFallbackTimer()
    }

    private func startFallbackTimer() {
        fallbackTimer?.invalidate()
        fallbackTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    /// 每秒检查一次性状态是否该回落（对应 theme.json 的 autoReturn）。
    private func tick() {
        guard let next = gate.fallback() else { return }
        apply(next, event: nil, imageOverride: nil)
    }

    // MARK: - 事件处理

    func handle(_ event: ClawdEvent) {
        events = ClawdStore.append(event)

        if let sid = event.sessionId, !sid.isEmpty {
            sessionId = sid
        }
        if event.event == "SessionStart" {
            sessionStartedAt = event.receivedAt
        }

        let newState = event.state
        let image = newState == .working ? ClawdState.workingImageName(activeSessions: activeWorkingCount()) : nil

        guard gate.accept(newState, now: event.receivedAt) else {
            // 被最小展示时长挡住：只更新小组件里的会话标题之类，不换主状态。
            refreshOnlyTitle(event)
            return
        }
        apply(newState, event: event, imageOverride: image)
    }

    /// 手动切换状态（ContentView 的下拉框）。
    func manualSet(_ state: ClawdState) {
        gate = StateGate(initial: state)
        sessionStartedAt = Date()
        apply(state, event: nil, imageOverride: state == .working ? ClawdState.workingImageName(activeSessions: 1) : nil)
    }

    /// 从 App Group 重新读一次。Widget 的交互按钮只写存储，App 回到前台时靠它对齐。
    func reloadFromStore() {
        let stored = ClawdStore.loadSnapshot()
        guard stored.updatedAt != Date(timeIntervalSince1970: 0) else { return }
        guard stored.updatedAt != snapshot.updatedAt else { return }
        snapshot = stored
        gate = StateGate(initial: stored.state)
        events = ClawdStore.loadEvents()
    }

    /// 唤醒 / 让它睡：给 Widget 的 AppIntent 用。
    func wake() {
        manualSet(.idle)
    }

    func sleep() {
        manualSet(.sleeping)
    }

    private func refreshOnlyTitle(_ event: ClawdEvent) {
        var updated = snapshot
        if let title = event.sessionTitle, !title.isEmpty { updated.sessionTitle = title }
        if let agent = event.agentId, !agent.isEmpty { updated.agentId = agent }
        if !event.detail.isEmpty { updated.detail = event.detail }
        snapshot = updated
        ClawdStore.save(updated)
        activities.refreshWidgets()
    }

    private func apply(_ state: ClawdState, event: ClawdEvent?, imageOverride: String?) {
        let newSnapshot = ClawdSnapshot(
            state: state,
            event: event,
            imageName: imageOverride,
            sessionStartedAt: sessionStartedAt
        )
        snapshot = newSnapshot
        ClawdStore.save(newSnapshot)

        if activities.isActive || autoStartLiveActivity {
            activities.update(snapshot: newSnapshot, sessionId: sessionId)
        } else {
            activities.refreshWidgets()
        }
    }

    private func activeWorkingCount() -> Int {
        // 最近 60 秒内出现过 working/thinking 的不同会话数，近似 theme.json 的 workingTiers。
        let cutoff = Date().addingTimeInterval(-60)
        var sessions = Set<String>()
        for event in events where event.receivedAt >= cutoff {
            let state = event.state
            if state == .working || state == .thinking || state == .juggling {
                sessions.insert(event.sessionId ?? "unknown")
            }
        }
        return max(1, sessions.count)
    }

    // MARK: - 开关

    func setServerEnabled(_ enabled: Bool) {
        // 即便值没变也走一遍 didSet：外部可能已经把监听停掉了，需要重新 start。
        serverEnabled = enabled
    }

    private func syncServer() {
        if serverEnabled {
            if !server.isRunning { server.start() }
        } else {
            server.stop()
        }
    }

    func toggleLiveActivity() {
        if activities.isActive {
            activities.end(snapshot: snapshot)
        } else {
            activities.start(snapshot: snapshot, sessionId: sessionId)
        }
    }

    func clearHistory() {
        ClawdStore.clearEvents()
        events = []
    }

    /// 给设置页/README 用的推荐推送命令。
    var pushCommandExample: String {
        let host = advertisedHost.isEmpty ? "<手机局域网IP>" : advertisedHost
        return "CLAWD_HOST=\(host) python3 tools/send_state.py --state working --event PreToolUse"
    }
}
