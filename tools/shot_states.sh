#!/bin/bash
# 逐个状态推 + 截图。
#
# 用法: tools/shot_states.sh <设备UDID> <App容器的Documents目录> <文件名前缀>
# 前置: App 已安装并启动、实时活动已 ACTIVE、且已经处在想要的前后台状态
#       （要让灵动岛显示实时活动紧凑态，得先把 App 切到后台）。
#
# 为什么不能「推完就截」：
#   StateGate 在 `newState == current` 时返回 false，apply() 不跑，标记也不会写。
#   而且新状态优先级不高于当前状态时，要等当前状态过完 minDisplaySeconds 才接受。
#   所以这里的等待时间按每个状态的 minDisplaySeconds 给，不是拍脑袋的数。
set -u

UDID=$1
DOC=$2
PREFIX=$3
A="$DOC/la-applied.txt"

# SHOT_BACKGROUND=1：灵动岛紧凑态模式。
# 推送必须在 App 前台时发 —— iOS 会把后台 App 的网络挂起，推了也进不了端口
#（上一版 CI 就是先切后台再推，16 态一条都没生效）。
# 所以这个模式下每轮先把它拉回前台、推、等它认下，再切到设置 App 退到后台截图
#（App 在前台时，灵动岛不显示它自己的实时活动）。
# 默认 0：App 一直前台，拍 App 自己的页面。
BG=${SHOT_BACKGROUND:-0}

STATES="idle roam yawning dozing collapsing thinking working juggling sweeping error attention notification carrying sleeping waking dizzy"
FAIL=""
N=0

for S in $STATES; do
  N=$((N + 1))
  TAG=$(printf "%02d-%s" "$N" "$S")

  # LA APPLIED 是追加写的，不清掉就会读到上一轮那条，等于自欺。
  rm -f "$A"

  if [ "$BG" = "1" ]; then
    # 先回前台再推：后台的 App 收不到（见文件头）
    xcrun simctl launch "$UDID" com.clawd.island >/dev/null 2>&1
    sleep 2
  fi

  python3 tools/send_state.py --host 127.0.0.1 --state "$S" --event PreToolUse \
    --agent-id openclaw --hook-source send_state.py \
    --session-id sess-ci-la --session-title "重构支付模块" \
    --cwd "/Users/dev/pay" --tool-name "Bash" --tool-use-id "toolu_ct_$N" >/dev/null 2>&1 \
    || echo "  推送 $S 没打进端口（岛上不会变）"

  # 等 App 自己写「这一条 ActivityKit 收下了」。等不到就说明图上不是这个状态 ——
  # 记下来，最后一起红，不能当成功。
  W=0
  OK=0
  while [ "$W" -lt 15 ]; do
    if [ -s "$A" ] && grep -q "^LA APPLIED $S\$" "$A"; then OK=1; break; fi
    sleep 1
    W=$((W + 1))
  done
  if [ "$OK" -ne 1 ]; then
    FAIL="$FAIL $S"
    echo "  状态 $S 等 15s 没被应用。标记现有内容：$(tr '\n' '|' < "$A" 2>/dev/null)"
  fi

  if [ "$BG" = "1" ]; then
    # 退到后台：灵动岛这时才显示紧凑态，而且停在上一次 update 的状态上
    xcrun simctl launch "$UDID" com.apple.Preferences >/dev/null 2>&1
    sleep 2.5
  fi

  sleep 1.2   # 让图标那点弹簧缩放落定，别拍在半路上
  xcrun simctl io "$UDID" screenshot "state-$PREFIX-$TAG.png"

  # 给下一次推送留出当前状态的最小展示窗口，否则下一条会被门挡下（见文件头）。
  case "$S" in
    sweeping)     sleep 5.5 ;;
    error)        sleep 5 ;;
    notification) sleep 5 ;;
    attention)    sleep 4 ;;
    carrying)     sleep 3 ;;
    working|thinking) sleep 1 ;;
    *)            sleep 0.3 ;;
  esac
done

if [ -n "$FAIL" ]; then
  echo "这些状态没在图上生效，逐个状态图不完整：$FAIL"
  exit 1
fi
echo "16 个状态全部应用并截图完成"
