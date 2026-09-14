#!/usr/bin/env bash
# 把每个状态的 SVG 按**动画中的某一刻**烘成静态 PNG。
#
# 为什么需要这个脚本：
#   `svg-src/*.svg` 是「一套静态矩形 + CSS 动画」，状态之间的差异大部分写在
#   `@keyframes` 里。`tools/export-assets.sh` 用 rsvg-convert 渲染，只出**基础姿** ——
#   于是 idle / roam / yawning / thinking / notification 渲出来逐像素完全相同，
#   collapsing / waking 也一样（实测：不透明像素 63180 vs 63180、外接框全等）。
#   16 个状态实际只剩 11 张不同的图，和 README 第 7 节「每个状态选一张最合适的 SVG」
#   的设计意图不符。
#
#   这里改用真 CSS 引擎（Chromium headless）配 `--virtual-time-budget` 把动画推进到
#   指定时刻再截图。虚拟时间让结果可复现，不依赖真实等待。
#
# 依赖：chromium（Debian: apt-get install chromium）、python3 + Pillow（降采样用）。
# 用法：
#   ./tools/bake-state-frames.sh              # 渲染 svg-src/clawd-*.svg 里的 18 张大图
#   BUDGET=5000 ./tools/bake-state-frames.sh  # 指定虚拟时间（ms，默认 5000）
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
CATALOG="Resources/Assets.xcassets"
BUDGET="${BUDGET:-5000}"     # 要大于最长的一次性动画（3.8s），否则烘到一半
HI="${HI:-864}"              # 先渲这么大，再降采样出 1x/2x/3x
BASE="${BASE:-144}"          # 1x 点尺寸，与现有资产一致（3x = 432）
PY="${PYTHON:-python3}"

command -v chromium >/dev/null || { echo "缺 chromium" >&2; exit 1; }
"$PY" -c 'import PIL' 2>/dev/null || { echo "缺 Pillow（用 PYTHON=... 指一个带它的解释器）" >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

n=0
for svg in svg-src/clawd-*.svg; do
  name="$(basename "$svg" .svg)"
  case "$name" in *-mini-*) continue ;; esac   # mini/di 是 9 张按码位共享的小图，不在这里重渲
  set="$CATALOG/$name.imageset"
  [ -d "$set" ] || { echo "跳过没有 imageset 的 $name"; continue; }

  chromium --headless --no-sandbox --disable-gpu --hide-scrollbars \
    --force-device-scale-factor=1 \
    --default-background-color=00000000 \
    --virtual-time-budget="$BUDGET" \
    --window-size="$HI,$HI" \
    --screenshot="$TMP/$name.png" "file://$PWD/$svg" >/dev/null 2>&1

  [ -s "$TMP/$name.png" ] || { echo "渲染失败：$name" >&2; exit 1; }

  # 降采样出三档。渲染时窗口是正方形，SVG 的 viewBox 也是正方形，几何与旧资产一致。
  "$PY" - "$TMP/$name.png" "$set/$name" "$BASE" <<'PY'
import sys
from PIL import Image
src, stem, base = sys.argv[1], sys.argv[2], int(sys.argv[3])
im = Image.open(src).convert("RGBA")
for tag, mul in (("1x", 1), ("2x", 2), ("3x", 3)):
    px = base * mul
    out = im.resize((px, px), Image.LANCZOS) if im.size != (px, px) else im
    out.save(f"{stem}-{tag}.png", "PNG")
PY
  n=$((n + 1))
  echo "已烘 $name"
done

echo "完成：$n 个状态。Contents.json 没动（档位和 filename 本来就对），"
echo "但改动后必须重跑 CI 的资源尺寸守卫 —— 尺寸守卫看的是声明，看不出姿态。"
