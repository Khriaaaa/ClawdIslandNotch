import Foundation
import Network

/// 最小的本地 HTTP 状态服务器。
///
/// 对照实现：reference/clawd-on-desk-android/src/com/clawd/android/StateServer.java
/// 协议（BRIEF 第二节）：
///   - 端口 23333 → 23337 依次探测，命中后缓存
///   - POST /state，body 是 JSON
///   - 响应必须带 `x-clawd-server: clawd-on-desk`，body 任意 JSON
///   - GET /health 返回自身信息（方便先用 curl 自检）
///
/// 只用了 Network.framework 的 NWListener / NWConnection，没有任何第三方依赖，
/// 也不依赖 Network.framework 里可能不存在的便捷 API。
final class StateServer: ObservableObject {

    static let candidatePorts: [UInt16] = [23333, 23334, 23335, 23336, 23337]

    @Published private(set) var isRunning = false
    @Published private(set) var boundPort: UInt16?
    @Published private(set) var lastError: String?
    @Published private(set) var requestCount = 0

    /// 收到一条合法状态事件时回调（已切到主线程）。
    var onEvent: ((ClawdEvent) -> Void)?

    private let queue = DispatchQueue(label: "com.clawd.island.state-server")
    private var listener: NWListener?
    private var candidateIndex = 0
    private var wantedStart = false

    // MARK: - 启停

    func start() {
        wantedStart = true
        lastError = nil
        candidateIndex = 0
        tryBind()
    }

    func stop() {
        wantedStart = false
        listener?.stateUpdateHandler = nil
        listener?.newConnectionHandler = nil
        listener?.cancel()
        listener = nil
        DispatchQueue.main.async {
            self.isRunning = false
            self.boundPort = nil
        }
    }

    private func tryBind() {
        guard wantedStart else { return }
        guard candidateIndex < Self.candidatePorts.count else {
            DispatchQueue.main.async {
                self.isRunning = false
                self.boundPort = nil
                self.lastError = "23333-23337 全部被占用，没有可用端口"
            }
            return
        }

        let port = Self.candidatePorts[candidateIndex]
        candidateIndex += 1

        let parameters = NWParameters.tcp
        // 允许端口快速重用（App 重启后不用等 TIME_WAIT）。
        parameters.allowLocalEndpointReuse = true
        // 注意：这里刻意不设 acceptLocalOnly，否则只能被本机连上；
        // 而 NAS 上的代理是通过局域网 IP 推过来的。

        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            tryBind()
            return
        }

        let newListener: NWListener
        do {
            newListener = try NWListener(using: parameters, on: nwPort)
        } catch {
            // 参数非法之类的硬失败，换下一个端口。
            tryBind()
            return
        }

        newListener.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            guard self.listener === newListener else { return }
            switch state {
            case .ready:
                DispatchQueue.main.async {
                    self.isRunning = true
                    self.boundPort = port
                    self.lastError = nil
                }
            case .failed(let error):
                DispatchQueue.main.async {
                    self.isRunning = false
                    self.boundPort = nil
                    self.lastError = "端口 \(port) 绑定失败：\(error.localizedDescription)"
                }
                newListener.stateUpdateHandler = nil
                newListener.newConnectionHandler = nil
                newListener.cancel()
                self.listener = nil
                self.tryBind()
            default:
                break
            }
        }

        newListener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }

        listener = newListener
        newListener.start(queue: queue)
    }

    // MARK: - 连接处理

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(connection, buffer: Data())
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else {
                connection.cancel()
                return
            }
            var accumulated = buffer
            if let data = data, !data.isEmpty {
                accumulated.append(data)
            }

            // 防御：一个请求不该无限大。
            if accumulated.count > 1_048_576 {
                connection.cancel()
                return
            }

            if let request = HTTPRequest.parse(accumulated) {
                self.respond(to: connection, request: request)
                return
            }

            if isComplete || error != nil {
                connection.cancel()
                return
            }

            self.receive(connection, buffer: accumulated)
        }
    }

    private func respond(to connection: NWConnection, request: HTTPRequest) {
        let isStatePush = request.method.uppercased() == "POST" && request.path == "/state"
        let isHealth = request.method.uppercased() == "GET" && request.path == "/health"

        var statusCode = 404
        var body = #"{"error":"not found"}"#

        if isStatePush {
            statusCode = 200
            body = #"{"ok":true}"#
            if let json = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any] {
                let event = ClawdEvent.from(json: json)
                DispatchQueue.main.async {
                    self.requestCount += 1
                    self.onEvent?(event)
                }
            }
            // body 不是合法 JSON 时也回 200：协议只约定响应头，body 任意。
        } else if isHealth {
            statusCode = 200
            body = #"{"ok":true,"app":"clawd-island","port":\#(boundPort ?? 0)}"#
        }

        let bodyData = Data(body.utf8)
        var header = "HTTP/1.1 \(statusCode) \(statusCode == 200 ? "OK" : "Not Found")\r\n"
        header += "Content-Type: application/json; charset=utf-8\r\n"
        // 这一行是协议的关键：外部插件靠它确认对端是 Clawd。
        header += "x-clawd-server: clawd-on-desk\r\n"
        header += "Content-Length: \(bodyData.count)\r\n"
        header += "Connection: close\r\n\r\n"

        var response = Data(header.utf8)
        response.append(bodyData)

        connection.send(content: response, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}

// MARK: - 极简 HTTP 解析

/// 只解析「请求行 + 头 + 可选 body」的够用版本。
/// 返回 nil 表示数据还不够，需要继续 receive。
struct HTTPRequest {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data

    static func parse(_ buffer: Data) -> HTTPRequest? {
        let separator = Data([0x0D, 0x0A, 0x0D, 0x0A]) // \r\n\r\n
        guard let separatorRange = buffer.range(of: separator) else { return nil }

        let headerData = buffer.subdata(in: buffer.startIndex..<separatorRange.lowerBound)
        guard let headerText = String(data: headerData, encoding: .utf8) else { return nil }

        var lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }

        let method = String(parts[0])
        let path = String(parts[1])

        lines.removeFirst()
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[line.startIndex..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }

        let contentLength = Int(headers["content-length"] ?? "0") ?? 0
        let bodyStart = separatorRange.upperBound
        let availableBody = buffer.distance(from: bodyStart, to: buffer.endIndex)
        if availableBody < contentLength { return nil }

        let bodyEnd = buffer.index(bodyStart, offsetBy: contentLength)
        let body = buffer.subdata(in: bodyStart..<bodyEnd)

        return HTTPRequest(method: method, path: path, headers: headers, body: body)
    }
}
