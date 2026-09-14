import WidgetKit
import SwiftUI

/// 锁屏 accessory 家族。
///
/// 这三个 family 是「不用打开 App 也能看到 Clawd」的常驻面之一 —— 另一处是主屏小组件
/// `ClawdHomeWidget`（刘海机、灵动岛机都能加）：
/// `WidgetFamily.accessoryInline` / `.accessoryRectangular` / `.accessoryCircular`
/// （WidgetKit，iOS 16+，用户在锁屏自定义里添加）。
///
/// 它们和灵动岛无关：刘海机型、灵动岛机型、甚至无刘海机型都支持。
/// 锁屏上系统按 **vibrant** 方式呈现：保留亮度、明显去饱和/变淡，自定义彩色图不会
/// 原样显示。想更完整地保留原色要用 iOS 18 的 widget accent 一族，部署目标 iOS 17，不引。
/// （旧写法是「会被压成单色/半透明」，不准 —— 真做单色就看不出宠物了；这句也没有
///   Apple 文档原句，HIG 只说 vibrant 用于锁屏/StandBy 这类低光场景。）
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
            // 用 144pt 的大图（`imageName`）下采样到 60pt，不用 52pt 的 `islandGlyph`。
            // 实测：`clawd-mini-sleep-3x.png` 里宠物本体只有 146x98px（+5+29），
            // 即 48.7x32.7pt —— 放进 72/76pt 的圆面只占 68% 宽、45% 高，看着偏小。
            // 144 → 60 是下采样，不会软；圆面尺寸取自 HIG live-activities 的
            // Specifications 表（72x72 @393x852 / 76x76 @430x932）。
            // （原来只写 `.padding(6)`，图会跟圆面撑到 60–64pt，把 52pt 素材上采样。）
            Image(snapshot.state.imageName)
                .resizable()
                .scaledToFit()
                .frame(width: 60, height: 60)
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
