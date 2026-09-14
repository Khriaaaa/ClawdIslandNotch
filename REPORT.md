# 交付报告

## 产物（相对 `/shared/clawd-ios/ClawdIsland/`）

`project.yml`、`README.md`、`REPORT.md`、
`Shared/ClawdAttributes.swift`、
`App/ClawdIslandApp.swift`、`App/ContentView.swift`、`App/SettingsView.swift`、
`Core/ClawdState.swift`、`Core/StateServer.swift`、`Core/ActivityController.swift`、`Core/ClawdStore.swift`、
`Widget/ClawdWidgetBundle.swift`、`Widget/ClawdLiveActivity.swift`、`Widget/ClawdHomeWidget.swift`、`Widget/ClawdIntents.swift`、
`Resources/Assets.xcassets/`（27 个 imageset，每个含手写 Contents.json）、
`tools/send_state.py`、`tools/export-assets.sh`。

## 依据

协议字段、端口探测顺序与响应头抄 `openclaw-plugin/index.js` 的 `buildPayload()` / `postJsonToPort()`；
事件→状态抄 `agents/hermes.js` 的 `eventMap`，并用 `index.js` 的 `handleHook()` 补全；
状态全集、`timings`、`workingTiers`、`autoReturn` 抄 `assets/theme.json`；
优先级与一次性状态抄 `src/state-priority.js`；HTTP 响应形态对照 Android `StateServer.java`。

## 保守简化

静态图 + 一次进场动效，无持续动画；并发度用最近 60 秒不同 session_id 数近似 `workingTiers`；
交互按钮只写 App Group 并刷新时间线，App 回前台再对齐；后台/息屏接收与 APNs 明确不做；
无 swiftc，只做了括号引号配平、文件清单核对、`send_state.py` 的 dry-run 与本地 mock 端到端（跳过非 Clawd 端口 23333，命中 23334）。

## 你要验证

1. `xcodegen generate` 后两个 target 能编译、真机 Run。
2. App 前台时 `python3 tools/send_state.py --host <手机IP> --state working --event PreToolUse` 能改灵动岛。
3. 实时活动 8 小时重建、设置页开关、小组件按钮。
4. 若改 bundle id，App Group 三处是否同步。

## 待你决定

真机用的 bundle id / Team；是否保留 App Group 名 `group.com.clawd.island.clawd`。
