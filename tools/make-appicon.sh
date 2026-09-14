#!/usr/bin/env bash
# 重新生成 Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png。
#
# 依赖：rsvg-convert（librsvg）+ python3 + Pillow。只在需要换图标时手动跑一次，
# CI 不跑它 —— CI 只校验那张图在不在、是不是 1024x1024（资源尺寸守卫）。
#
# 为什么从 SVG 出：仓库里的 PNG 资产本来就是 rsvg-convert 渲的（tools/export-assets.sh），
# 所以从同一个源渲染出来的图标跟 App 里的宠物是同一套线条，不会是另一种画风。
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# 先渲到 4096，再裁到宠物本体、按图标比例缩放 —— 直接渲 1024 会因为 SVG 的
# viewBox 留白很多而让宠物偏小、且边缘发软。
rsvg-convert -w 4096 -h 4096 svg-src/clawd-idle.svg -o "$TMP/pet.png"

# 需要 Pillow。系统 python3 没有时用 PYTHON=/path/to/python 指一个带 Pillow 的解释器。
PY="${PYTHON:-python3}"
"$PY" - "$TMP/pet.png" "Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png" <<'PY'
import sys
from PIL import Image, ImageDraw
import numpy as np

src = Image.open(sys.argv[1]).convert("RGBA")
a = np.asarray(src)
ys, xs = np.nonzero(a[..., 3] > 8)
pet = src.crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))

S = 1024
W = int(S * 0.80)                      # 宠物占图标宽度 72%，主屏上不至于单薄
pet = pet.resize((W, int(pet.height * W / pet.width)), Image.LANCZOS)

bg = Image.new("RGBA", (S, S))
d = ImageDraw.Draw(bg)
top, bot = (26, 26, 34), (9, 9, 13)    # 深色底：橘粉宠物对比强，比浅色底更像正经图标
for y in range(S):
    t = y / (S - 1)
    d.line([(0, y), (S, y)], fill=tuple(int(top[i] + (bot[i] - top[i]) * t) for i in range(3)) + (255,))
bg.alpha_composite(pet, ((S - pet.width) // 2, (S - pet.height) // 2))
bg.convert("RGB").save(sys.argv[2], "PNG")
print("写出", sys.argv[2], S, "x", S)
PY
