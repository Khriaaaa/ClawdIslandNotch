#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""往 Clawd Island（iOS）推送一条桌宠状态。

协议完全照抄 reference/clawd-on-desk-android/openclaw-plugin/index.js：
  - POST /state
  - 端口从 23333 到 23337 依次探测，命中后用响应头 x-clawd-server: clawd-on-desk 确认
  - body 是 buildPayload() 那套字段（agent_id / state / event / session_id / ...），
    可选字段缺省即不出现

用法示例：
  # 先看会发什么（不联网）
  python3 send_state.py --dry-run --state working --event PreToolUse

  # 发一条到手机（手机 IP 换成实际值）
  python3 send_state.py --host 192.168.1.23 --state working --event PreToolUse

  # 只给事件，状态自动按映射推
  python3 send_state.py --host 192.168.1.23 --event UserPromptSubmit --session-title "重构支付模块"

  # 依次发一串状态，肉眼验证灵动岛变化
  python3 send_state.py --host 192.168.1.23 --demo

只依赖 Python 标准库。默认端口列表和探测顺序与插件一致。
"""

import argparse
import http.client
import json
import sys
import time

PORTS = [23333, 23334, 23335, 23336, 23337]
SERVER_HEADER = "x-clawd-server"
SERVER_VALUE = "clawd-on-desk"
TIMEOUT = 3.0

STATES = [
    "idle", "roam", "yawning", "dozing", "collapsing",
    "thinking", "working", "juggling", "sweeping",
    "error", "attention", "notification", "carrying",
    "sleeping", "waking", "dizzy",
]

# 与 Core/ClawdState.swift、agents/hermes.js、openclaw-plugin/index.js 对齐。
EVENT_TO_STATE = {
    "SessionStart": "idle",
    "UserPromptSubmit": "thinking",
    "PreToolUse": "working",
    "PostToolUse": "working",
    "PostToolUseFailure": "error",
    "Stop": "attention",
    "StopFailure": "error",
    "SessionEnd": "sleeping",
    "PreCompact": "sweeping",
    "PostCompact": "attention",
    "Notification": "notification",
    "Elicitation": "notification",
    "SubagentStart": "juggling",
    "SubagentStop": "working",
    "WorktreeCreate": "carrying",
}

DEMO_SEQUENCE = [
    ("idle", "SessionStart"),
    ("thinking", "UserPromptSubmit"),
    ("working", "PreToolUse"),
    ("working", "PostToolUse"),
    ("attention", "Stop"),
    ("error", "StopFailure"),
    ("sleeping", "SessionEnd"),
]


def build_payload(args, state, event):
    """字段与 openclaw-plugin/index.js 的 buildPayload() 一致，空值不写。"""
    payload = {
        "agent_id": args.agent_id,
        "hook_source": args.hook_source,
        "state": state,
        "event": event,
        "session_id": args.session_id,
        "session_title": args.session_title,
        "cwd": args.cwd,
        "tool_name": args.tool_name,
        "tool_use_id": args.tool_use_id,
        "editor": args.editor,
        "openclaw_run_id": args.run_id,
    }
    if args.error_present:
        payload["error_present"] = True
    return {k: v for k, v in payload.items() if v not in (None, "")}


def post(host, port, payload):
    """POST 到指定端口。返回 (是否命中 Clawd, 说明文本)。"""
    body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    conn = http.client.HTTPConnection(host, port, timeout=TIMEOUT)
    try:
        conn.request(
            "POST",
            "/state",
            body=body,
            headers={
                "Content-Type": "application/json",
                "Content-Length": str(len(body)),
            },
        )
        resp = conn.getresponse()
        resp_body = resp.read().decode("utf-8", "replace")
        header = resp.getheader(SERVER_HEADER)
        if header == SERVER_VALUE:
            return True, "HTTP %s  %s  body=%s" % (resp.status, header, resp_body)
        return False, "端口 %d 不是 Clawd（%s: %s）" % (port, SERVER_HEADER, header)
    except (OSError, http.client.HTTPException) as exc:
        return False, "端口 %d 连不上：%s" % (port, exc)
    finally:
        conn.close()


def send_once(args, payload, ports):
    last = ""
    for port in ports:
        ok, message = post(args.host, port, payload)
        if ok:
            return True, port, message
        last = message
    return False, None, last


def select_state(args, event):
    if args.state:
        state = args.state
        if state not in STATES:
            sys.exit("未知状态 %r。可用：%s" % (state, ", ".join(STATES)))
    elif event in EVENT_TO_STATE:
        state = EVENT_TO_STATE[event]
    else:
        sys.exit("要么给 --state，要么给能识别的事件名；未知事件 %r" % event)
    return state


def main():
    parser = argparse.ArgumentParser(description="推送 Clawd 状态到 iOS 桌宠")
    parser.add_argument("--host", default="127.0.0.1", help="桌宠设备地址（手机局域网 IP）")
    parser.add_argument("--port", type=int, default=None, help="指定端口；不给就按 23333-23337 探测")
    parser.add_argument("--state", choices=STATES, help="直接指定状态")
    parser.add_argument("--event", default="PreToolUse", help="事件名，用于辅助推断状态")
    parser.add_argument("--agent-id", default="openclaw")
    parser.add_argument("--hook-source", default="send_state.py")
    parser.add_argument("--session-id", default="")
    parser.add_argument("--session-title", default="")
    parser.add_argument("--cwd", default="")
    parser.add_argument("--tool-name", default="")
    parser.add_argument("--tool-use-id", default="")
    parser.add_argument("--editor", choices=["code", "cursor"], default=None)
    parser.add_argument("--run-id", default="")
    parser.add_argument("--error-present", action="store_true")
    parser.add_argument("--dry-run", action="store_true", help="只打印 payload，不发请求")
    parser.add_argument("--demo", action="store_true", help="依次发一串状态，间隔 2 秒")
    args = parser.parse_args()

    ports = [args.port] if args.port else PORTS

    if args.demo:
        if args.dry_run:
            for state, event in DEMO_SEQUENCE:
                print(json.dumps(build_payload(args, state, event), ensure_ascii=False))
            return 0
        print("向 %s 依次推送 %d 个状态…" % (args.host, len(DEMO_SEQUENCE)))
        for index, (state, event) in enumerate(DEMO_SEQUENCE):
            payload = build_payload(args, state, event)
            ok, port, message = send_once(args, payload, ports)
            mark = "OK" if ok else "FAIL"
            print("[%s] %-10s %-18s %s" % (mark, state, event, message))
            if not ok:
                return 1
            if args.port is None and port:
                ports = [port]  # 命中后缓存，跟插件一样
            if index != len(DEMO_SEQUENCE) - 1:
                time.sleep(2.0)
        return 0

    state = select_state(args, args.event)
    payload = build_payload(args, state, args.event)

    if args.dry_run:
        print(json.dumps(payload, ensure_ascii=False, indent=2))
        print("--dry-run：没有发送。目标 %s，端口 %s" % (args.host, ports))
        return 0

    ok, port, message = send_once(args, payload, ports)
    if ok:
        print("已推送到 %s:%s  state=%s event=%s" % (args.host, port, state, args.event))
        print(message)
        return 0
    print("推送失败：%s" % message, file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
