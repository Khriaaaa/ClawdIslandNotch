import WidgetKit
import SwiftUI

/// 主屏小组件条目。
struct ClawdEntry: TimelineEntry {
    let date: Date
    let snapshot: ClawdSnapshot
}

struct ClawdTimelineProvider: TimelineProvider {

    /// 图库预览用的假数据。
    private static func demo() -> ClawdSnapshot {
        ClawdSnapshot(
            stateRaw: ClawdState.working.rawValue,
            stateTitle: ClawdState.working.title,
            imageName: ClawdState.working.imageName,
            islandGlyph: ClawdState.working.islandGlyph,
            sessionTitle: "clawd-on-desk",
            agentId: "openclaw",
            detail: "PreToolUse",
            updatedAt: Date(),
            sessionStartedAt: Date().addingTimeInterval(-180)
        )
    }

    private static func current() -> ClawdSnapshot {
        let stored = ClawdStore.loadSnapshot()
        if stored.updatedAt == Date(timeIntervalSince1970: 0) {
            return demo()
        }
        return stored
    }

    func placeholder(in context: Context) -> ClawdEntry {
        ClawdEntry(date: Date(), snapshot: Self.demo())
    }

    func getSnapshot(in context: Context, completion: @escaping (ClawdEntry) -> Void) {
        if context.isPreview {
            completion(ClawdEntry(date: Date(), snapshot: Self.demo()))
        } else {
            completion(ClawdEntry(date: Date(), snapshot: Self.current()))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ClawdEntry>) -> Void) {
        let entry = ClawdEntry(date: Date(), snapshot: Self.current())
        // 状态推送时会主动 reload；这里的 15 分钟只是兜底。
        let next = Date().addingTimeInterval(15 * 60)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

/// 主屏小组件（小 / 中）。显示当前状态与最近会话。
struct ClawdHomeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ClawdHomeWidget", provider: ClawdTimelineProvider()) { entry in
            ClawdHomeWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Clawd 桌宠")
        .description("显示 Clawd 的当前状态与最近会话，可直接唤醒或让它睡。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct ClawdHomeWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ClawdEntry

    private var snapshot: ClawdSnapshot { entry.snapshot }

    var body: some View {
        switch family {
        case .systemSmall:
            smallView
        default:
            mediumView
        }
    }

    private var smallView: some View {
        VStack(spacing: 4) {
            Image(snapshot.imageName)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 58)
            Text(snapshot.stateTitle)
                .font(.headline)
            if !snapshot.sessionTitle.isEmpty {
                Text(snapshot.sessionTitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(8)
    }

    private var mediumView: some View {
        HStack(spacing: 12) {
            Image(snapshot.imageName)
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)

            VStack(alignment: .leading, spacing: 3) {
                Text(snapshot.stateTitle)
                    .font(.headline)
                if !snapshot.sessionTitle.isEmpty {
                    Text(snapshot.sessionTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(snapshot.updatedAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            VStack(spacing: 8) {
                Button(intent: WakeClawdIntent()) {
                    Image(systemName: "sun.max.fill")
                }
                .buttonStyle(.bordered)

                Button(intent: SleepClawdIntent()) {
                    Image(systemName: "moon.zzz.fill")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(8)
    }
}
