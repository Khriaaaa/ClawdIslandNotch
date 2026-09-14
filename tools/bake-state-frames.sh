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
HI="${HI:-1800}"             # 先渲这么大，再降采样出 1x/2x/3x
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

  # SVG 里写死了 width="500" height="500"，光把窗口开大内容不会跟着变大
  # （实测 864 窗口里蟹体只占 ~210px）。先把这两个属性换成渲染尺寸再渲。
  sed "s/width=\"500\" height=\"500\"/width=\"$HI\" height=\"$HI\"/" "$svg" > "$TMP/$name.svg"

  chromium --headless --no-sandbox --disable-gpu --hide-scrollbars \
    --force-device-scale-factor=1 \
    --default-background-color=00000000 \
    --virtual-time-budget="$BUDGET" \
    --window-size="$HI,$HI" \
    --screenshot="$TMP/$name.png" "file://$TMP/$name.svg" >/dev/null 2>&1

  [ -s "$TMP/$name.png" ] || { echo "渲染失败：$name" >&2; exit 1; }

  # 裁切 + 降采样出三档。
  #
  # 裁切这一步不能省，而且不能交给 librsvg —— 旧资产就是 rsvg-convert 渲的，
  # 它对 CSS transform-origin 的解释和浏览器不一致：dozing 那双靠 scaleY(0.1)
  # 压扁的眼睛被甩到了身体上方，再按「内容 bbox」裁切，错误就被切成定局
  #（眼睛贴在图顶、身体被缩小下移，钳子也跟着没了）。
  "$PY" - "$TMP/$name.png" "$set/$name" "$BASE" <<'PY'
import sys
from PIL import Image
src, stem, base = sys.argv[1], sys.argv[2], int(sys.argv[3])
im = Image.open(src).convert("RGBA")

# 按内容 bbox 做方形裁切、留 10% 边距：位置要按真实内容算，
# 否则眼睛一旦出错，裁切框会跟着错误一起走，把 bug 固化成构图。
box = im.getchannel("A").point(lambda v: 255 if v > 8 else 0).getbbox()
if not box:
    sys.exit(f"{stem} 渲出来是全透明的，拒绝覆盖")
x0, y0, x1, y1 = box
side = max(x1 - x0, y1 - y0) * 1.1
half = side / 2
cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
l, t = round(cx - half), round(cy - half)
r, b = l + round(side), t + round(side)
canvas = Image.new("RGBA", (r - l, b - t), (0, 0, 0, 0))
canvas.paste(im, (-l, -t))
im = canvas

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
