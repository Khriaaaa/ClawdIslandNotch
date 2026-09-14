import WidgetKit
import SwiftUI

/// 锁屏 accessory 家族。
///
/// 这三个 family 是刘海机上唯一「不用打开 App 也能看到 Clawd」的常驻面：
/// `WidgetFamily.accessoryInline` / `.accessoryRectangular` / `.accessoryCircular`
/// （WidgetKit，iOS 16+，用户在锁屏自定义里添加）。
///
/// 它们和灵动岛无关：刘海机型、灵动岛机型、甚至无刘海机型都支持。
/// 锁屏上系统会统一做 vibrancy 处理，自定义彩色图会被压成单色/半透明；
/// 想完全保留原色需要 iOS 18 的 widget accent 一族，部署目标是 iOS 17，这里不引。
struct ClawdLockAccessoryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ClawdLockAccessoryWidget", provider: ClawdTimelineProvider()) { entry in
            ClawdAccessoryView(entry: entry)
                .containerBackground(Color.clear, for: .widget)
        }
        .configurationDisplayName("Clawd 锁屏")
        .description("在锁屏上显示 Clawd 的当前状态，点一下打开 App。")
        .supportedFamilies([.accessoryRectangular, .accessoryInline, .accessoryCircular])
    }
}

struct ClawdAccessoryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ClawdEntry

    private var snapshot: ClawdSnapshot { entry.snapshot }

    var body: some View {
        switch family {
        case .accessoryInline:
            inline
        case .accessoryCircular:
            circular
        default:
            rectangular
        }
    }

    /// accessoryInline 只接受单行文本 + SF Symbol，不支持自定义图片。
    private var inline: some View {
        Label {
            Text(inlineText)
        } icon: {
            Image(systemName: snapshot.state.symbolName)
        }
    }

    private var inlineText: String {
        if snapshot.sessionTitle.isEmpty { return snapshot.stateTitle }
        return "\(snapshot.stateTitle) · \(snapshot.sessionTitle)"
    }

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            // 显式把渲染尺寸钉在 52pt（= 素材的点尺寸）。原来只写 `.padding(6)`，
            // 图会跟着圆形面撑到 60–64pt，把 52pt 的素材**上采样**、发软。
            // accessory 圆形面是 76x76（430x932）/ 72x72（393x852），52 放得下。
            Image(snapshot.state.islandGlyph)
                .resizable()
                .scaledToFit()
                .frame(width: 52, height: 52)
        }
        .widgetURL(NotchDeepLink.url)
    }

    private var rectangular: some View {
        HStack(spacing: 8) {
            // 用 52pt 的小图而不是 144pt 的大图，渲染 32pt —— 下采样，不会软。
            // accessory 各面：矩形 172x76 / 160x72 / 157x72，圆形 76x76 / 72x72。
            Image(snapshot.state.islandGlyph)
                .resizable()
                .scaledToFit()
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 1) {
                Text(snapshot.stateTitle)
                    .font(.headline)
                Text(detailText)
                    .font(.caption2)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            // 主屏/锁屏小组件里的 AppIntent 按钮（iOS 17）在 accessory 家族上的可交互性
            // 需要真机确认；点击区域之外的整块仍然通过 widgetURL 打开 App。
            Button(intent: WakeClawdIntent()) {
                Image(systemName: "sun.max.fill")
            }
            .buttonStyle(.plain)
        }
        .widgetURL(NotchDeepLink.url)
    }

    private var detailText: String {
        if !snapshot.sessionTitle.isEmpty { return snapshot.sessionTitle }
        return snapshot.detail.isEmpty ? "Clawd" : snapshot.detail
    }
}
