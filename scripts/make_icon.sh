#!/bin/sh
# Build assets/icon.icns from assets/icon-1024.png (rounded-square mask, macOS icon grid).
set -e
cd "$(dirname "$0")/.."
python3 - <<'PY'
from PIL import Image, ImageDraw
src = Image.open("assets/icon-1024.png").convert("RGBA").resize((824, 824), Image.LANCZOS)
mask = Image.new("L", (824 * 4, 824 * 4), 0)
ImageDraw.Draw(mask).rounded_rectangle([0, 0, 824 * 4 - 1, 824 * 4 - 1], radius=185 * 4, fill=255)
mask = mask.resize((824, 824), Image.LANCZOS)
canvas = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
canvas.paste(src, (100, 100), mask)
canvas.save("/tmp/cs-icon-1024.png")
PY
SET=/tmp/ClaudeSwitcher.iconset
rm -rf "$SET"; mkdir "$SET"
for s in 16 32 128 256 512; do
  sips -z $s $s /tmp/cs-icon-1024.png --out "$SET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) /tmp/cs-icon-1024.png --out "$SET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$SET" -o assets/icon.icns
echo built assets/icon.icns
