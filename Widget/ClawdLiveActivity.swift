import ActivityKit
import WidgetKit
import SwiftUI

/// 灵动岛 + 锁屏实时活动。
///
/// 布局对应活动状态：
///   compact(leading)  小图
///   compact(trailing) 状态短标签
///   minimal           只有小图（同时被两个活动占用时）
///   expanded          大图 + 状态 + 会话标题 + 唤醒/睡觉按钮
///
/// 注意机型差异（刘海机方案的核心事实）：`DynamicIsland` / `DynamicIslandExpandedRegion`
/// 以及 compact/minimal 这几个闭包只在**有灵动岛**的机型上渲染。刘海机型上同一个
/// Live Activity 只剩下面 `ClawdLockScreenView` 那一份呈现（锁屏 + 通知中心 + StandBy）。
/// `dynamicIsland` 闭包是 API 要求必须提供的，刘海机上被系统忽略，不能省。
///
/// 只做「一张静态图 + 一次进场动效」，不写持续动画：Live Activity 不允许
/// 持续动画，系统对更新频率也有限流预算（BRIEF 第五节）。
struct ClawdLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ClawdAttributes.self) { context in
            ClawdLockScreenView(state: context.state)
                .activityBackgroundTint(Color.black.opacity(0.85))
                .activitySystemActionForegroundColor(.white)
                // 点锁屏卡片直接进「刘海」页；scheme 见 Shared/NotchDeepLink.swift。
                .widgetURL(NotchDeepLink.url)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ClawdGlyph(stateRaw: context.state.stateRaw, size: 40)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(context.state.stateTitle)
                            .font(.headline)
                        if !context.state.sessionTitle.isEmpty {
                            Text(context.state.sessionTitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 12) {
                        Button(intent: WakeClawdIntent()) {
                            Label("唤醒", systemImage: "sun.max.fill")
                        }
                        Button(intent: SleepClawdIntent()) {
                            Label("睡觉", systemImage: "moon.zzz.fill")
                        }
                        Spacer()
                        Text(context.state.detail.isEmpty ? context.state.agentId : context.state.detail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            } compactLeading: {
                ClawdGlyph(stateRaw: context.state.stateRaw, size: 20)
            } compactTrailing: {
                Text(shortLabel(context.state.stateRaw))
                    .font(.caption2)
            } minimal: {
                ClawdGlyph(stateRaw: context.state.stateRaw, size: 20)
            }
        }
    }

    private func shortLabel(_ raw: String) -> String {
        ClawdState(rawValue: raw)?.title ?? "Clawd"
    }
}

/// 锁屏（以及不支持灵动岛的机型）上的样子。
struct ClawdLockScreenView: View {
    let state: ClawdAttributes.ContentState

    var body: some View {
        HStack(spacing: 14) {
            ClawdGlyph(stateRaw: state.stateRaw, size: 52)

            VStack(alignment: .leading, spacing: 3) {
                Text(state.stateTitle)
                    .font(.headline)
                if !state.sessionTitle.isEmpty {
                    Text(state.sessionTitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if !state.detail.isEmpty {
                    Text(state.detail)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Text(state.updatedAt, style: .relative)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(14)
    }
}

/// 统一的小图渲染：按 stateRaw 找资源名，找不到就退回睡眠图。
/// `scaleEffect` 只做一次进场放大，不参与循环动画。
struct ClawdGlyph: View {
    let stateRaw: String
    let size: CGFloat
    @State private var appeared = false

    private var imageName: String {
        (ClawdState(rawValue: stateRaw) ?? .idle).islandGlyph
    }

    var body: some View {
        Image(imageName)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .scaleEffect(appeared ? 1.0 : 0.75)
            .opacity(appeared ? 1.0 : 0.4)
            .onAppear {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                    appeared = true
                }
            }
    }
}
