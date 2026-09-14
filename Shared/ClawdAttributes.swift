import Foundation
import ActivityKit

/// ActivityAttributes 是 App 与 Widget 扩展之间唯一的类型契约，
/// 必须同时编译进两个 target（见 project.yml 里 Shared/ 的 sources）。
///
/// 设计要点：
/// - 外层属性（sessionId）在 Live Activity start 之后不可变，用来标记这是哪个会话的活动。
/// - ContentState 每次 update 都会替换，只放「会变的、可编码的」小字段。
/// - 所有字段都是 String / Date，避免让 ActivityKit 去编码自定义类型。
struct ClawdAttributes: ActivityAttributes, Sendable {

    public struct ContentState: Codable, Hashable, Sendable {
        /// ClawdState.rawValue，例如 "working"。
        var stateRaw: String
        /// 面板上显示的状态中文名，避免 Widget 里再查一次表。
        var stateTitle: String
        /// 资源目录里的图片名（灵动岛/锁屏用）。
        var imageName: String
        /// 会话标题，来自 payload.session_title。
        var sessionTitle: String
        /// 代理 id，来自 payload.agent_id。
        var agentId: String
        /// 附加说明：工具名 / 事件名 / cwd 摘要。
        var detail: String
        /// 这次状态被接收的时间。
        var updatedAt: Date
    }

    /// 会话标识：payload.session_id。空时由 App 填 "clawd:default"。
    var sessionId: String
}
