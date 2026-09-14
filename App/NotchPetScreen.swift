import SwiftUI

/// 刘海栖木：App 在前台时的「从刘海后面探头」舞台。
///
/// 原理：把桌宠的顶部用负向 `offset` 压进 `[0, safeAreaInsets.top]` 这条带子。
/// 落在刘海挖孔范围内的像素被硬件遮住（挖孔不发光），两侧露出来的就是「探头」的效果。
/// 不需要任何私有 API，也读不到刘海矩形（见 `NotchGeometry` 的说明）。
///
/// 硬限制：iOS 不允许 App 画在别的 App 之上（Android 的 `SYSTEM_ALERT_WINDOW` 没有对应物），
/// 所以这个舞台只在本 App 处于前台时可见。想常驻只能靠锁屏实时活动 / 锁屏小组件。
struct NotchPetScreen: View {
    @EnvironmentObject var coordinator: ClawdCoordinator
    @Environment(\.scenePhase) private var scenePhase

    @State private var geometry: NotchGeometry = .unknown
    @State private var revealed = false
    @State private var bobUp = false
    @State private var popped = true

    var body: some View {
        ZStack(alignment: .top) {
            background

            VStack(spacing: 0) {
                perch
                    .offset(y: revealed ? 0 : -160)
                    .animation(.spring(response: 0.65, dampingFraction: 0.72), value: revealed)
                Spacer(minLength: 12)
                controls
            }
            .padding(.top, stageTop)
            .padding(.bottom, max(20, geometry.bottomInset + 12))
        }
        // 整块舞台忽略安全区：坐标系原点就是物理屏幕左上角，
        // 顶部留白由 stageTop 显式算出，不依赖容器的隐式对齐。
        .ignoresSafeArea()
        .onAppear {
            geometry = NotchProbe.current()
            revealed = true
            bobUp = true
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { geometry = NotchProbe.current() }
        }
        .onChange(of: coordinator.snapshot.updatedAt) { _, _ in
            pop()
        }
    }

    // MARK: - 舞台

    /// 栖木的静止位置：顶部压在刘海带里，让挖孔吃掉那一截。
    private var stageTop: CGFloat {
        max(0, geometry.topInset - geometry.peekDepth)
    }

    private var background: some View {
        LinearGradient(
            colors: [Color(white: 0.07), Color.black],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var perch: some View {
        VStack(spacing: 6) {
            Image(coordinator.snapshot.state.imageName)
                .resizable()
                .scaledToFit()
                .frame(width: 148, height: 148)
                .shadow(color: .black.opacity(0.55), radius: 12, y: 6)
                .scaleEffect(popped ? 1.0 : 0.88)
                .offset(y: bobUp ? -5 : 5)
                .animation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true), value: bobUp)

            Text(coordinator.snapshot.stateTitle)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
        }
    }

    private var subtitle: String {
        var parts: [String] = []
        if !coordinator.snapshot.sessionTitle.isEmpty { parts.append(coordinator.snapshot.sessionTitle) }
        if !coordinator.snapshot.detail.isEmpty { parts.append(coordinator.snapshot.detail) }
        if parts.isEmpty { parts.append("没有会话在跑") }
        return parts.joined(separator: " · ")
    }

    // MARK: - 控制区

    private var controls: some View {
        VStack(spacing: 12) {
            Picker("手动切换状态", selection: Binding(
                get: { coordinator.snapshot.state },
                set: { coordinator.manualSet($0) }
            )) {
                ForEach(ClawdState.allCases) { state in
                    Text(state.title).tag(state)
                }
            }
            .pickerStyle(.menu)
            .tint(.white)

            HStack(spacing: 12) {
                Button {
                    coordinator.wake()
                } label: {
                    Label("唤醒", systemImage: "sun.max.fill")
                }
                .buttonStyle(.bordered)

                Button {
                    coordinator.sleep()
                } label: {
                    Label("睡觉", systemImage: "moon.zzz.fill")
                }
                .buttonStyle(.bordered)
            }
            .tint(.white)

            Text(geometry.summary)
                .font(.caption2.monospaced())
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)

            Text(noteText)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.45))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24)
    }

    private var noteText: String {
        switch geometry.kind {
        case .notch:
            return "顶上那截压在刘海挖孔上：挖孔范围内的像素被硬件遮住，所以看着像从刘海后面探出头。刘海矩形读不到，靠安全区上沿定位。"
        case .dynamicIsland:
            return "这台是灵动岛机型：栖木照常能用，但真正贴硬件的是灵动岛，实时活动会自动走 DynamicIsland 布局。"
        case .plain:
            return "没检测到刘海：栖木贴在屏幕顶端，效果等同普通的顶部挂件。"
        case .unknown:
            return "还没读到窗口安全区。模拟器或扩展进程里会出现这种情况。"
        }
    }

    /// 状态变化时缩一下，让「探头」有反应。
    private func pop() {
        popped = false
        withAnimation(.spring(response: 0.28, dampingFraction: 0.5)) { popped = true }
    }
}
