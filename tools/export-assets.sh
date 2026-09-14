#!/usr/bin/env bash
# 可选：把 Resources/Assets.xcassets 里的 SVG 批量转成 PNG（1x/2x/3x），并重写 Contents.json。
#
# 只在 macOS 上有意义，而且需要一个 SVG 渲染器。Xcode 本身已经支持 SVG 资源
# （Contents.json 里开了 preserves-vector-representation），所以正常情况**不需要**跑这个。
# 什么时候用：想让小组件在旧工具链上更保险，或想自己微调栅格图。
#
# 依赖（任选其一）：
#   brew install librsvg     # 提供 rsvg-convert
#   brew install inkscape    # 提供 inkscape
#
# 用法：
#   ./tools/export-assets.sh            # 转 1x=96 / 2x=192 / 3x=288 像素
#   BASE=128 ./tools/export-assets.sh   # 自定义 1x 尺寸

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CATALOG="${SCRIPT_DIR}/../Resources/Assets.xcassets"
BASE="${BASE:-96}"

if [[ ! -d "$CATALOG" ]]; then
  echo "找不到资源目录：$CATALOG" >&2
  exit 1
fi

if command -v rsvg-convert >/dev/null 2>&1; then
  RENDER="rsvg"
elif command -v inkscape >/dev/null 2>&1; then
  RENDER="inkscape"
else
  echo "需要 rsvg-convert 或 inkscape。例：brew install librsvg" >&2
  exit 1
fi

render() {
  local svg="$1" out="$2" size="$3"
  if [[ "$RENDER" == "rsvg" ]]; then
    rsvg-convert -w "$size" -h "$size" "$svg" -o "$out"
  else
    inkscape "$svg" -w "$size" -h "$size" -o "$out" >/dev/null 2>&1
  fi
}

count=0
for imageset in "$CATALOG"/*.imageset; do
  [[ -d "$imageset" ]] || continue
  svg="$(find "$imageset" -maxdepth 1 -name '*.svg' | head -n1)"
  [[ -n "$svg" ]] || continue

  name="$(basename "$imageset" .imageset)"
  png1="${name}.png"
  png2="${name}@2x.png"
  png3="${name}@3x.png"

  render "$svg" "$imageset/$png1" "$BASE"
  render "$svg" "$imageset/$png2" "$((BASE * 2))"
  render "$svg" "$imageset/$png3" "$((BASE * 3))"

  [[ -f "$imageset/Contents.json" ]] && cp "$imageset/Contents.json" "$imageset/Contents.json.svg-backup"

  cat > "$imageset/Contents.json" <<JSON
{
  "images" : [
    { "filename" : "${png1}", "idiom" : "universal", "scale" : "1x" },
    { "filename" : "${png2}", "idiom" : "universal", "scale" : "2x" },
    { "filename" : "${png3}", "idiom" : "universal", "scale" : "3x" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON

  count=$((count + 1))
  echo "已转换 $name（1x=${BASE}px）"
done

echo "完成：$count 个 imageset。原 Contents.json 备份为 Contents.json.svg-backup。"
