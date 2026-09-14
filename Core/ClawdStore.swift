import Foundation

/// 一条来自外部代理的状态事件。
///
/// 字段名对齐 reference/clawd-on-desk-android/openclaw-plugin/index.js 的 `buildPayload()`
/// （见 BRIEF 第二节）。可选字段在协议里是「缺省即不出现」，所以这里全部 optional。
struct ClawdEvent: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var receivedAt: Date

    var agentId: String?
    var hookSource: String?
    var stateRaw: String?
    var event: String?
    var sessionId: String?
    var sessionTitle: String?
    var cwd: String?
    var agentPid: Int?
    var sourcePid: Int?
    var pidChain: [Int]?
    var editor: String?
    var toolName: String?
    var toolUseId: String?
    var openclawRunId: String?
    var openclawCallId: String?
    var errorPresent: Bool?

    /// 解析后的状态。
    var state: ClawdState { ClawdState.resolve(stateRaw: stateRaw, event: event) }

    /// 给 UI 看的一句话摘要。
    var detail: String {
        var parts: [String] = []
        if let event = event, !event.isEmpty { parts.append(event) }
        if let tool = toolName, !tool.isEmpty { parts.append(tool) }
        if let editor = editor, !editor.isEmpty { parts.append(editor) }
        return parts.joined(separator: " · ")
    }

    /// 从 HTTP body 解出来的 JSON 字典构造。字段名是下划线风格，逐个取值。
    /// 用 JSONSerialization 而不是 JSONDecoder，是为了容忍任意未声明的字段和类型。
    static func from(json: [String: Any], now: Date = Date()) -> ClawdEvent {
        func str(_ key: String) -> String? {
            if let s = json[key] as? String, !s.isEmpty { return s }
            if let n = json[key] as? NSNumber { return n.stringValue }
            return nil
        }
        func int(_ key: String) -> Int? {
            if let n = json[key] as? NSNumber { return n.intValue }
            if let s = json[key] as? String { return Int(s) }
            return nil
        }

        let runId = str("openclaw_run_id")
        let callId = str("openclaw_call_id")
        let session = str("session_id")
        let stableId = [session, runId, callId, str("event")].compactMap { $0 }.joined(separator: ":")
        let id = stableId.isEmpty ? UUID().uuidString : "\(stableId)@\(now.timeIntervalSince1970)"

        return ClawdEvent(
            id: id,
            receivedAt: now,
            agentId: str("agent_id"),
            hookSource: str("hook_source"),
            stateRaw: str("state"),
            event: str("event"),
            sessionId: session,
            sessionTitle: str("session_title"),
            cwd: str("cwd"),
            agentPid: int("agent_pid"),
            sourcePid: int("source_pid"),
            pidChain: json["pid_chain"] as? [Int],
            editor: str("editor"),
            toolName: str("tool_name"),
            toolUseId: str("tool_use_id"),
            openclawRunId: runId,
            openclawCallId: callId,
            errorPresent: json["error_present"] as? Bool
        )
    }
}

/// 当前状态的快照。写进 App Group，App 与 Widget 扩展共享。
struct ClawdSnapshot: Codable, Hashable, Sendable {
    var stateRaw: String
    var stateTitle: String
    var imageName: String
    var islandGlyph: String
    var sessionTitle: String
    var agentId: String
    var detail: String
    var updatedAt: Date
    /// 同一个会话已持续多久（秒）。用于小组件显示"进行中 3 分钟"。
    var sessionStartedAt: Date

    static let empty = ClawdSnapshot(
        stateRaw: ClawdState.sleeping.rawValue,
        stateTitle: ClawdState.sleeping.title,
        imageName: ClawdState.sleeping.imageName,
        islandGlyph: ClawdState.sleeping.islandGlyph,
        sessionTitle: "",
        agentId: "",
        detail: "",
        updatedAt: Date(timeIntervalSince1970: 0),
        sessionStartedAt: Date(timeIntervalSince1970: 0)
    )

    var state: ClawdState { ClawdState(rawValue: stateRaw) ?? .idle }

    init(state: ClawdState, event: ClawdEvent?, imageName: String? = nil, sessionStartedAt: Date) {
        self.stateRaw = state.rawValue
        self.stateTitle = state.title
        self.imageName = imageName ?? state.imageName
        self.islandGlyph = state.islandGlyph
        self.sessionTitle = event?.sessionTitle ?? ""
        self.agentId = event?.agentId ?? ""
        self.detail = event?.detail ?? ""
        self.updatedAt = event?.receivedAt ?? Date()
        self.sessionStartedAt = sessionStartedAt
    }

    init(stateRaw: String, stateTitle: String, imageName: String, islandGlyph: String,
         sessionTitle: String, agentId: String, detail: String,
         updatedAt: Date, sessionStartedAt: Date) {
        self.stateRaw = stateRaw
        self.stateTitle = stateTitle
        self.imageName = imageName
        self.islandGlyph = islandGlyph
        self.sessionTitle = sessionTitle
        self.agentId = agentId
        self.detail = detail
        self.updatedAt = updatedAt
        self.sessionStartedAt = sessionStartedAt
    }
}

/// 存储层。App 与 Widget 扩展共用同一份实现（两个 target 都编进 Core/）。
///
/// 这里刻意不做成 ObservableObject：App 侧由 ClawdCoordinator 负责发通知，
/// Widget 侧只需要一个纯读接口。
enum ClawdStore {

    /// App Group。必须与 project.yml 里两个 target 的 entitlements 一致，
    /// 也要和 README 里让用户替换的 bundle id 对应。
    static let appGroupID = "group.com.clawd.island.clawd"

    private static let snapshotKey = "clawd.snapshot.v1"
    private static let eventsKey = "clawd.events.v1"
    private static let ringCapacity = 50

    static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    // MARK: - 快照

    static func loadSnapshot() -> ClawdSnapshot {
        guard let data = defaults.data(forKey: snapshotKey),
              let snapshot = try? JSONDecoder().decode(ClawdSnapshot.self, from: data) else {
            return .empty
        }
        return snapshot
    }

    static func save(_ snapshot: ClawdSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: snapshotKey)
    }

    // MARK: - 事件环形缓冲

    static func loadEvents() -> [ClawdEvent] {
        guard let data = defaults.data(forKey: eventsKey),
              let events = try? JSONDecoder().decode([ClawdEvent].self, from: data) else {
            return []
        }
        return events
    }

    /// 追加一条事件并返回新的环形缓冲（最新在前，最多 ringCapacity 条）。
    @discardableResult
    static func append(_ event: ClawdEvent) -> [ClawdEvent] {
        var events = loadEvents()
        events.insert(event, at: 0)
        if events.count > ringCapacity {
            events.removeLast(events.count - ringCapacity)
        }
        if let data = try? JSONEncoder().encode(events) {
            defaults.set(data, forKey: eventsKey)
        }
        return events
    }

    static func clearEvents() {
        defaults.removeObject(forKey: eventsKey)
    }
}

extension ClawdEvent {
    /// 由 App 内按钮 / Widget 交互按钮产生的本地事件。
    static func manual(state: ClawdState, at date: Date) -> ClawdEvent {
        ClawdEvent(
            id: "manual:\(state.rawValue)@\(date.timeIntervalSince1970)",
            receivedAt: date,
            agentId: "user",
            hookSource: "app-intent",
            stateRaw: state.rawValue,
            event: "Manual",
            sessionId: nil,
            sessionTitle: nil,
            cwd: nil,
            agentPid: nil,
            sourcePid: nil,
            pidChain: nil,
            editor: nil,
            toolName: nil,
            toolUseId: nil,
            openclawRunId: nil,
            openclawCallId: nil,
            errorPresent: nil
        )
    }
}
