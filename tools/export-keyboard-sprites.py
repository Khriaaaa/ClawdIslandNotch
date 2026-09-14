#!/usr/bin/env python3
"""从 svg-src/ 生成键盘用的迷你精灵（紧凑裁切 + 统一画框）。

为什么不能直接用 Resources/Assets.xcassets 里那套：
  那套是 900x900 方图、内容只占高度 60% 且四周留白，键盘条只有 56pt 高，
  直接放进去螃蟹会小得看不见；而且 900x900 解进内存一张 3.2MB，
  键盘扩展的内存上限只有 30~50MB，放几张就被系统杀掉。

做法：
  1. rsvg-convert 把 9 张 mini SVG 渲成 900x900
  2. 取 9 张 alpha 包围盒的并集（保证换姿势时螃蟹不会跳位）
  3. 按并集裁切，等比缩到高度 SPRITE_H，输出成裸 PNG（不进 Asset Catalog）
     裸 PNG 才能用 CGImageSourceCreateThumbnailAtIndex 只解小图

用法：python3 tools/export-keyboard-sprites.py
"""
import os
import subprocess
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "svg-src")
OUT = os.path.join(ROOT, "Keyboard", "Sprites")
TMP = "/tmp/clawd-kb-sprites"

SPRITE_H = 200          # 输出高度（px）。条高 56pt，精灵画到约 40pt，@3x=120px，200 够用
RENDER = 900            # SVG 先渲成这个边长再裁
MARGIN = 0.03           # 并集包围盒四周再留 3%

NAMES = [
    "clawd-mini-idle",
    "clawd-mini-crabwalk",
    "clawd-mini-typing",
    "clawd-mini-happy",
    "clawd-mini-peek",
    "clawd-mini-alert",
    "clawd-mini-sleep",
    "clawd-mini-enter",
    "clawd-mini-enter-sleep",
]


def render(name, out_png):
    svg = os.path.join(SRC, name + ".svg")
    subprocess.run(
        ["rsvg-convert", "-w", str(RENDER), "-h", str(RENDER), svg, "-o", out_png],
        check=True,
    )


def main():
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(TMP, exist_ok=True)

    boxes = []
    for name in NAMES:
        png = os.path.join(TMP, name + ".png")
        render(name, png)
        im = Image.open(png).convert("RGBA")
        box = im.split()[3].getbbox()
        if box is None:
            print(f"  ! {name} 全透明，跳过", file=sys.stderr)
            continue
        boxes.append(box)
        print(f"  {name:24} 内容 {box[2]-box[0]}x{box[3]-box[1]}")

    if not boxes:
        sys.exit("没有可用画面")

    x0 = min(b[0] for b in boxes)
    y0 = min(b[1] for b in boxes)
    x1 = max(b[2] for b in boxes)
    y1 = max(b[3] for b in boxes)
    pad_x = int((x1 - x0) * MARGIN)
    pad_y = int((y1 - y0) * MARGIN)
    x0, y0 = max(0, x0 - pad_x), max(0, y0 - pad_y)
    x1, y1 = min(RENDER, x1 + pad_x), min(RENDER, y1 + pad_y)
    print(f"\n统一画框: ({x0},{y0})-({x1},{y1})  {x1-x0}x{y1-y0}")

    for name in NAMES:
        src = os.path.join(TMP, name + ".png")
        if not os.path.exists(src):
            continue
        im = Image.open(src).convert("RGBA").crop((x0, y0, x1, y1))
        w = max(1, round(im.width * SPRITE_H / im.height))
        im = im.resize((w, SPRITE_H), Image.Resampling.LANCZOS)
        dst = os.path.join(OUT, name + ".png")
        im.save(dst, optimize=True)
        print(f"  写出 {name}.png  {im.width}x{im.height}  {os.path.getsize(dst)//1024}KB")


if __name__ == "__main__":
    main()
