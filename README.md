# Clawd Island

把 Clawd 螃蟹做成 iOS 的**灵动岛 / 锁屏实时活动 + 主屏小组件**桌宠。状态由外部代理
（NAS 上的 OpenClaw / Hermes 等）通过本地 HTTP 推送给手机，手机端换图、换文案。

这是一个可以直接用 Xcode 打开、生成、编译、跑到真机的完整工程。

---

## 1. 环境

- **Xcode 15 或更高**（本工程用到 iOS 17 的 `Button(intent:)` 与 `LiveActivityIntent`）
- **部署目标 iOS 17.0**
- **真机**：灵动岛只在 iPhone 14 Pro / 14 Pro Max 及以后的机型上有；其他机型仍然能看到
  锁屏实时活动和主屏小组件
- 手机上需要装一个能连到 NAS 的局域网环境，且 NAS 能访问手机 IP
- 生成工程需要 [XcodeGen](https://github.com/yonaskolb/XcodeGen)：
  `brew install xcodegen`，或 `mint install yonaskolb/XcodeGen`

---

## 2. 用 XcodeGen 生成工程（推荐）

```bash
cd ClawdIsland
xcodegen generate
open ClawdIsland.xcodeproj
```

生成三个 target：

| target | 类型 | 内容 |
|---|---|---|
| `ClawdIsland` | App | `App/` + `Core/` + `Shared/` + `Resources/` + `Keyboard/Shared` + `Keyboard/Sprites` |
| `ClawdKeyboard` | 键盘扩展 | `Keyboard/` + 只借 `Core/ClawdState.swift`、`Core/ClawdStore.swift` |
| `ClawdWidgetExtension` | Widget 扩展 | `Widget/` + `Core/` + `Shared/` + `Resources/` |

`Core/` 和 `Shared/` 被 App 与 Widget 两个 target 同时编译，这是有意的：中间层和类型契约
必须两边一致。键盘扩展**不**整个挂 `Core/`：那会把 `StateServer`（Network）和
`ActivityController` 一起编进扩展，而键盘扩展内存限额只有几十 MB、ActivityKit 在扩展里也用不了。

然后：

1. Xcode 里选 `ClawdIsland` scheme，选中你的开发团队
   （Signing & Capabilities → Team；或在 `project.yml` 里把 `DEVELOPMENT_TEAM` 打开填上）
2. 两个 target 都应该已经有 **App Groups** capability，值 `group.com.clawd.island.clawd`
3. 选中真机，Run

---

## 3. 不用 XcodeGen 的手工步骤

1. Xcode → File → New → Project → iOS → App
   - Product Name: `ClawdIsland`
   - Interface: SwiftUI，Language: Swift
   - Bundle Identifier 例如 `com.yourname.clawdisland`
2. File → New → Target → iOS → **Widget Extension**
   - Product Name: `ClawdWidgetExtension`
   - **不要**勾 "Include Live Activity"（我们自己的文件已经包含它），不勾 "Include Configuration App Intent"
   - 生成后删掉 Xcode 模板自带的 `*Widget.swift` / `*Bundle.swift` / `*LiveActivity.swift` / `Info.plist` 之外的东西，或直接不用模板文件
3. 把本工程的文件按目录拖进对应 target：
   - `App/`、`Core/`、`Shared/`、`Resources/` → `ClawdIsland`
   - `Widget/`、`Core/`、`Shared/`、`Resources/` → `ClawdWidgetExtension`
     （`Core/`、`Shared/`、`Resources/` 要**同时**勾选两个 target 的 Target Membership）
4. 两个 target 都加 App Group：Signing & Capabilities → + Capability → App Groups →
   `group.<你的bundleid>.clawd`（例如 `group.com.yourname.clawdisland.clawd`）。
   同时把 `Core/ClawdStore.swift` 里的 `appGroupID` 改成同一个字符串。
5. App target 的 Info 里加（见下一节）：`NSSupportsLiveActivities`、
   `NSSupportsLiveActivitiesFrequentUpdates`、`NSLocalNetworkUsageDescription`。
6. Widget 扩展 target 的 Info.plist 里确认：
   `NSExtension.NSExtensionPointIdentifier = com.apple.widgetkit-extension`

---

## 4. Info.plist / 权限 / App Group

App target（`project.yml` 已生成到 `App/Info.plist`）：

| key | 值 | 作用 |
|---|---|---|
| `NSSupportsLiveActivities` | `YES` | 允许使用 ActivityKit |
| `NSSupportsLiveActivitiesFrequentUpdates` | `YES` | 允许较高频率更新（仍受系统预算限制） |
| `NSLocalNetworkUsageDescription` | 一句说明 | iOS 14+ 局域网监听/连接需要用户授权，否则外部推不进来 |

App Group：`group.com.clawd.island.clawd`，两个 target 的 entitlements 里都声明。
App 与 Widget 扩展靠它共享当前状态快照和最近事件环形缓冲。

---

## 5. 跑起来验证

1. 手机和 NAS / Mac 在同一局域网
2. 打开 App，确认「状态」页显示 **本地监听中** 和端口号（23333 起，占用则顺延）
3. 保持 App 在前台，从另一台机器推一条：

```bash
# 最省事：用仓库自带的推送脚本（无第三方依赖）
python3 tools/send_state.py --host <手机IP> --state thinking --event UserPromptSubmit

# 只给事件，脚本按映射自动推状态
python3 tools/send_state.py --host <手机IP> --event PreToolUse --tool-name Bash

# 依次发一串状态，肉眼验证灵动岛切换
python3 tools/send_state.py --host <手机IP> --demo

# 原生 curl，验证协议（重点看响应头 x-clawd-server）
curl -i -X POST http://<手机IP>:23333/state \
  -H 'Content-Type: application/json' \
  -d '{"agent_id":"openclaw","state":"working","event":"PreToolUse","session_title":"测试会话"}'
```

预期：

- curl 的响应头里有 `x-clawd-server: clawd-on-desk`
- App 的状态页换成对应图片和标题
- 实时活动已开启时，灵动岛 compact 区出现 Clawd 小图；长按展开出现状态、
  会话标题和「唤醒 / 睡觉」按钮；锁屏上出现同款卡片
- 主屏加小组件（长按桌面 → 加号 → Clawd 桌宠），能看到状态和两个按钮

让 OpenClaw 插件指向手机：给插件进程设 `CLAWD_HOST=<手机IP>`，它就会把
`/state` POST 到手机而不是 `127.0.0.1`（插件原逻辑见
`reference/clawd-on-desk-android/openclaw-plugin/index.js` 的 `postStateToClawd()`）。

自检命令：

```bash
python3 tools/send_state.py --dry-run --state working --event PreToolUse   # 看 payload，不联网
curl http://<手机IP>:23333/health                                         # {"ok":true,"app":"clawd-island",...}
```

---

## 6. 能力边界（重要）

- **App 退到后台 / 息屏后，iOS 会挂起进程，本地 HTTP 监听随之停止。** 这一版的
  「实时」只在 App 处于前台时可靠。这是 iOS 平台约束，不是实现取舍。
- App 被挂起时，已经开启的实时活动仍会显示最后一次推送的状态，但不会再更新。
- 长期后台 / 息屏更新需要走 **APNs**：push-to-start（用推送直接开实时活动）和
  实时活动 update token（用推送更新状态），配合服务端。**本版本不做**，属于阶段 2。
  后续路径：`Activity.request(..., pushType: .token)` 拿 push token → 服务端下发
  `apns-push-type: liveactivity` 的推送 → 服务端还需要 APNs 证书/密钥。
- 灵动岛 / 实时活动**不能跑持续动画**，系统对更新频率也有限流预算。工程里每个状态
  只配一张静态图 + 一次进场动效，这是刻意为之，不要改成 `TimelineView` 高频刷新。
- 实时活动有 **8 小时上限**，到点系统会让它过期。`ActivityController` 在接近上限
  （7 小时）时会自动 end + 重新 start，确保不会"卡在过期状态"。
- 端口探测只覆盖 23333–23337（与插件约定一致）。全部被占用时会报错，可在设置页看到。

---

## 7. 设计决策

**为什么用静态图，不做动画。** 灵动岛空间小、更新受限流预算，而且 Live Activity 禁止
持续动画。SVG 素材里的 SMIL / CSS 动画在 iOS 上本来也不会动。所以每个状态选一张最合适
的 SVG 进 Assets，进场只用 SwiftUI 的 `scaleEffect` + `opacity` 做一次缩放淡入。
资源是**栅格 PNG**：`svg-src/*.svg` 由 `tools/export-assets.sh` 用 `rsvg-convert` 导出，
每个 imageset 在 `Contents.json` 里显式写 1x/2x/3x 三档。整目录没有
`preserves-vector-representation`（0 处）—— 别按「矢量、任意尺寸都不糊」理解这套资源。
漏写 `scale` 时同一张 900px 图会被当成 900pt，灵动岛上直接渲染成一块灰方块
（实测：run 34852382516 的 shot-8，60x60px 纯 (81,81,81)）；CI 里有资源尺寸守卫拦这一类。

**状态切换的最小展示时长。** 抄 `theme.json` 的 `timings.minDisplay`：
`attention` 4s、`error` 5s、`sweeping` 5.5s、`notification` 5s、`carrying` 3s、
`working` / `thinking` 各 1s。逻辑在 `StateGate.accept()`：当前状态还在窗口内且新状态
优先级不高于它，就先把新状态记成 pending，窗口过去后由每秒的 tick 补上；优先级更高
（比如突然 `error`）永远立刻打断。`autoReturn` 同样照抄 `theme.json`，到点回落到 idle。

**多会话并发怎么取状态。** 外部代理是每个会话各自 POST，桌宠只维护一个展示状态，
按 `src/state-priority.js` 的 `STATE_PRIORITY` 取最高优先级；同为 working 的并发会话数
越多，图片越"壮观"（`clawd-working` → `clawd-working-juggling` →
`clawd-working-building`，对应 `theme.json` 的 `workingTiers`）。当前实现用最近 60 秒内
出现过的不同 session_id 数近似这个并发度。

**灵动岛的小图。** 每个状态映射到一张 `clawd-mini-*` 小尺寸素材（`ClawdState.islandGlyph`），
拿不到对应 mini 就退回同名的迷你映射。小图和大图分开，是为了在极小空间里还能看清。

**交互按钮。** 用 `LiveActivityIntent`（继承自 `AppIntent`），这样点按钮在 App 进程内执行，
不用把 App 拉到前台；主屏小组件的 `Button(intent:)` 也接受同一类型。按钮只写 App Group
存储 + 刷新时间线，App 回到前台时再对齐（`ClawdCoordinator.reloadFromStore()`）。

**为什么选择端口探测而不是固定端口。** 与现有 OpenClaw 插件协议一致：插件按
23333→23337 顺序探测，靠响应头 `x-clawd-server: clawd-on-desk` 确认对端是 Clawd，
命中后缓存。手机端反过来做同样的候选列表，插件侧不需要为新平台改任何东西。

---

## 8. 目录结构

```
ClawdIsland/
  project.yml                        XcodeGen 定义（App + 键盘扩展 + Widget 扩展三个 target）
  README.md
  REPORT.md
  Shared/ClawdAttributes.swift       ActivityAttributes（App 与扩展共用）
  App/ClawdIslandApp.swift           @main + ClawdCoordinator（装配/事件流）
  App/ContentView.swift              状态面板 + 事件流水
  App/SettingsView.swift             端口/监听/自动实时活动/本机地址
  App/KeyboardPreviewScreen.swift    键盘扩展那块视图原样跑在 App 里（CI 靠它截图 + 自检）
  Core/ClawdState.swift              状态枚举 + 事件/JSON 映射 + StateGate
  Core/StateServer.swift             NWListener 极简 HTTP 服务（23333-23337）
  Core/ActivityController.swift      ActivityKit start/update/end + 8 小时重建
  Core/ClawdStore.swift              App Group 存储 + 最近事件环形缓冲
  Widget/ClawdWidgetBundle.swift     @main WidgetBundle
  Widget/ClawdLiveActivity.swift     灵动岛（compact/minimal/expanded）+ 锁屏
  Widget/ClawdHomeWidget.swift       主屏小组件（小/中）
  Widget/ClawdIntents.swift          LiveActivityIntent：唤醒 / 让它睡
  Resources/Assets.xcassets/         36 个 imageset（18 大图 + 9 mini + 9 di）+ AppIcon.appiconset
  svg-src/                           上述素材的矢量源（静态基础姿；状态差异写在 CSS 动画里）
  tools/send_state.py                命令行推状态 / 自测（纯标准库）
  tools/export-assets.sh             可选：macOS 上把 SVG 批量转 PNG
```

---

## 9. 协议与状态映射速查

外部代理 POST `http://<手机IP>:23333/state`，响应头带 `x-clawd-server: clawd-on-desk`。

请求体字段（与 `openclaw-plugin/index.js` 的 `buildPayload()` 一致，可选字段缺省即不出现）：
`agent_id` `hook_source` `state` `event` `session_id` `session_title` `cwd` `agent_pid`
`source_pid` `pid_chain` `editor` `tool_name` `tool_use_id` `openclaw_run_id`
`openclaw_call_id` `error_present` `session_end_reason`

事件 → 状态：

| 事件 | 状态 |
|---|---|
| `SessionStart` | `idle` |
| `UserPromptSubmit` | `thinking` |
| `PreToolUse` / `PostToolUse` / `SubagentStop` | `working` |
| `PostToolUseFailure` / `StopFailure` | `error` |
| `Stop` / `PostCompact` | `attention` |
| `SessionEnd` | `sleeping` |
| `PreCompact` | `sweeping` |
| `Notification` / `Elicitation` | `notification` |
| `SubagentStart` | `juggling` |
| `WorktreeCreate` | `carrying` |

状态全集 16 个：`idle` `roam` `yawning` `dozing` `collapsing` `thinking` `working`
`juggling` `sweeping` `error` `attention` `notification` `carrying` `sleeping` `waking` `dizzy`。

`state` 字段优先；认不出来再按 `event` 推断；都没有则按 `idle`。

---

## 10. 常见问题

**灵动岛没反应。** 确认是三件事：App 在前台；实时活动已开启（状态页按钮或设置项）；
机型支持灵动岛（iPhone 14 Pro 及以后）。不支持灵动岛的机型看锁屏和主屏小组件。

**curl 超时 / 连不上。** 手机和电脑不在同一网段，或第一次访问被 iOS 的本地网络权限拦了
（同意一次即可）。先在 App 里确认端口，再 `curl http://<手机IP>:<端口>/health`。

**改了 bundle id 之后 Widget 读不到状态。** App Group 字符串要三处一起改：
两个 target 的 entitlements、`Core/ClawdStore.swift` 的 `appGroupID`、Xcode 的
Signing & Capabilities。

**Xcode 提示 App Group 不可用。** 免费开发者账号需要在 Xcode 里选好 Team，
App Group 由 Xcode 自动创建；跨账号时手动在 Apple Developer 后台登记
`group.com.clawd.island.clawd`。

**想换成 PNG 素材。** 正常不需要（Xcode 12+ 原生支持 SVG）。确实要的话在 macOS 上跑
`tools/export-assets.sh`（依赖 `rsvg-convert` 或 `inkscape`），它会生成 1x/2x/3x PNG
并重写 `Contents.json`，原文件备份为 `Contents.json.svg-backup`。
