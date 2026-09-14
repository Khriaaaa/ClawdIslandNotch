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
                .onAppear {
                    coordinator.bootstrap()
                    // CI 用：实时活动起没起来，光看一张静止截图判不了，也没法问系统。
                    // 打开 CLAWD_LA_MARKER=1 就让 App 把结果写进 Documents，CI 读它判定 ——
                    // 起不来的话这一步直接红，不会「图看着像那么回事、job 却是绿的」。
                    // 延迟 3 秒：bootstrap 之后每秒还有一次 tick 兜底，等它走完再判。
                    if ProcessInfo.processInfo.environment["CLAWD_LA_MARKER"] == "1" {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                            Self.writeLiveActivityMarker(coordinator.activities)
                        }
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    // 回到前台时重读 App Group：Widget 的交互按钮可能已经改过状态。
                    if phase == .active {
                        coordinator.reloadFromStore()
                    }
                }
        }
    }
}

extension ClawdIslandApp {
    /// 把「实时活动到底起没起来」写进 Documents 给 CI 读。
    /// 写不进去不吞错 —— 吞了以后错的是图、绿的是 job。
    static func writeLiveActivityMarker(_ activities: ActivityController) {
        guard let docs = FileManager.default.urls(for: .documentDirectory,
                                                  in: .userDomainMask).first else { return }
        try? FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        let line = activities.isActive
            ? "LIVEACTIVITY ACTIVE"
            : "LIVEACTIVITY INACTIVE \(activities.lastError ?? "没有错误信息")"
        do {
            try (line + "\n").write(to: docs.appendingPathComponent("live-activity.txt"),
                           atomically: true, encoding: .utf8)
        } catch {
            NSLog("实时活动标记写入失败：\(error)")
        }
    }

    /// CI 用：把「App 真的收到过这条状态」落到 Documents，供 CI 断言。
    ///
    /// 只看推送端拿到 200 不算证据 —— StateServer 的候选端口是一段
    /// （23333…23337），另一台模拟器上的 App 可能正占着 23333，推送会打进它，
    /// 目标 App 一个字节都没收到，而推送端照样拿到 200。
    static func recordReceived(_ event: ClawdEvent) {
        Diag.append("RECEIVED \(event.state.rawValue) \(event.event ?? "-")", to: "received.txt")
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
        // 收条先写：CI 靠它证明状态真的进了这个 App，而不是进了隔壁模拟器那台。
        // 注意别写成 `Self.` —— 这里是 ClawdCoordinator，收条挂在 ClawdIslandApp 上。
        ClawdIslandApp.recordReceived(event)
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
