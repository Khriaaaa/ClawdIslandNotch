import Foundation

/// CI 判据用的标记文件。只在 `CLAWD_LA_MARKER=1` 时写。
///
/// 为什么要有这个：**推送端拿到 200 只能证明「有人收了」；App 收到 HTTP 也只能证明
/// 「HTTP 到了这个 App」，都证明不了「灵动岛上画的就是它」** —— 中间还有
/// `ActivityController` 里 `await activity.update(...)` 这一步，异步、无回执，
/// 失败或没生效时前面的证据照样成立。
///
/// 所以这里在 update/request 返回之后追加一笔，证明「ActivityKit 收下了这次更新」。
/// 严格说它仍然不是「系统已经重画了」（那只有看图才算），但比收条更近一步。
enum Diag {
    static var enabled: Bool {
        ProcessInfo.processInfo.environment["CLAWD_LA_MARKER"] == "1"
    }

    /// 追加一行到 Documents/<file>。
    ///
    /// 语义是「追加」：正常路径都走 FileHandle 的 seekToEndOfFile。
    /// 只有「文件还不存在」才落到新建那一支 —— 那一支是**非原子的截断重写**，
    /// 万一文件存在却打不开（权限/占位），会把已有内容盖掉。CI 每次全新安装，
    /// 走不到那一步；真要复用容器，就别指望这一支保内容。
    static func append(_ line: String, to file: String) {
        guard enabled else { return }
        guard let docs = FileManager.default.urls(for: .documentDirectory,
                                                  in: .userDomainMask).first else { return }
        try? FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        let url = docs.appendingPathComponent(file)
        let data = Data((line + "\n").utf8)
        if let fh = try? FileHandle(forWritingTo: url) {
            defer { try? fh.close() }
            fh.seekToEndOfFile()
            fh.write(data)
        } else {
            try? data.write(to: url)
        }
    }

    /// 实时活动「这次更新被 ActivityKit 收下了」。两个写入点：
    /// `start()` 里 `Activity.request` 之后、`update()` 里 `activity.update` 之后。
    static func appliedLiveActivity(_ stateRaw: String) {
        append("LA APPLIED \(stateRaw)", to: "la-applied.txt")
    }
}
