#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

PREFERRED_ICON_SOURCE="/Users/mikeonator/Pictures/MacOSTypingSoundsIcon.icon"
ICON_SOURCE="${1:-$PREFERRED_ICON_SOURCE}"
DEFAULT_MENU_SVG_SOURCE="${REPO_ROOT}/Branding/MacOSTypingSoundsMenuBarIcon.svg"
LEGACY_MENU_SVG_SOURCE="/Users/mikeonator/Pictures/MacOSTypingSoundsIconEnclosed.svg"
MENU_SVG_SOURCE="${2:-$DEFAULT_MENU_SVG_SOURCE}"

ICON_TOOL="/Applications/Icon Composer.app/Contents/Executables/ictool"
ACTOOL="/Applications/Xcode.app/Contents/Developer/usr/bin/actool"

BRANDING_ICON_DEST="${REPO_ROOT}/Branding/AppIcon.icon"
REPO_FALLBACK_ICON_SOURCE="${REPO_ROOT}/Branding/AppIcon.icon"

APP_ASSET_CATALOG_DEST="${REPO_ROOT}/MacOSTypingSounds/Images.xcassets"
OUTPUT_DIR="${REPO_ROOT}/MacOSTypingSounds/GeneratedIcons"
MENU_VECTOR_OUTPUT="${REPO_ROOT}/MacOSTypingSounds/MenuBarIconTemplate.pdf"
MENU_RASTER_OUTPUT="${REPO_ROOT}/MacOSTypingSounds/MenuBarIconTemplate.png"
DISTRIBUTION_ICNS_OUTPUT="${OUTPUT_DIR}/MacOSTypingSounds.icns"

if [[ ! -d "$ICON_SOURCE" && -d "$REPO_FALLBACK_ICON_SOURCE" ]]; then
  ICON_SOURCE="$REPO_FALLBACK_ICON_SOURCE"
fi

if [[ ! -d "$ICON_SOURCE" ]]; then
  echo "Icon source package not found: $ICON_SOURCE" >&2
  exit 1
fi

if [[ ! -f "$ICON_SOURCE/icon.json" ]]; then
  echo "Icon source package is missing icon.json: $ICON_SOURCE" >&2
  exit 1
fi

if [[ ! -x "$ICON_TOOL" ]]; then
  echo "Icon Composer tool not found: $ICON_TOOL" >&2
  exit 1
fi

if [[ ! -x "$ACTOOL" ]]; then
  echo "actool not found: $ACTOOL" >&2
  exit 1
fi

if [[ ! -f "$MENU_SVG_SOURCE" ]]; then
  if [[ -f "$DEFAULT_MENU_SVG_SOURCE" ]]; then
    MENU_SVG_SOURCE="$DEFAULT_MENU_SVG_SOURCE"
  elif [[ -f "$LEGACY_MENU_SVG_SOURCE" ]]; then
    MENU_SVG_SOURCE="$LEGACY_MENU_SVG_SOURCE"
  fi
fi

rm -rf "$BRANDING_ICON_DEST"
mkdir -p "$(dirname "$BRANDING_ICON_DEST")"
cp -R "$ICON_SOURCE" "$BRANDING_ICON_DEST"

# Ensure icon package schema is at current tool version.
"$ICON_TOOL" "$BRANDING_ICON_DEST" --upgrade >/dev/null || true

rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

ICON_BASENAME="$(basename "$BRANDING_ICON_DEST" .icon)"
IR_OUTPUT_DIR="${OUTPUT_DIR}/IconIR"
mkdir -p "$IR_OUTPUT_DIR"
"$ICON_TOOL" "$BRANDING_ICON_DEST" --export-intermediate-representation --output-directory "$IR_OUTPUT_DIR" --platform macOS >/dev/null

EXPORTED_CATALOG="${IR_OUTPUT_DIR}/${ICON_BASENAME}.icon.xcassets"
if [[ ! -d "$EXPORTED_CATALOG" ]]; then
  echo "Expected Icon Composer export not found: $EXPORTED_CATALOG" >&2
  exit 1
fi

mkdir -p "$APP_ASSET_CATALOG_DEST"
# Remove legacy/incorrect app-icon payloads first.
rm -rf \
  "${APP_ASSET_CATALOG_DEST}/AppIcon.icon" \
  "${APP_ASSET_CATALOG_DEST}/AppIcon.appiconset" \
  "${APP_ASSET_CATALOG_DEST}/LegacyAppIcon.appiconset" \
  "${APP_ASSET_CATALOG_DEST}/${ICON_BASENAME}.iconstack" \
  "${APP_ASSET_CATALOG_DEST}/${ICON_BASENAME}_Assets"

cp "${EXPORTED_CATALOG}/Contents.json" "${APP_ASSET_CATALOG_DEST}/Contents.json"
for entry in "${EXPORTED_CATALOG}"/*; do
  base="$(basename "$entry")"
  cp -R "$entry" "${APP_ASSET_CATALOG_DEST}/$base"
done

# Build a distribution .icns artifact directly from the generated icon stack catalog.
ACTOOL_TMP="${OUTPUT_DIR}/Actool"
mkdir -p "${ACTOOL_TMP}/build"
"$ACTOOL" "$APP_ASSET_CATALOG_DEST" \
  --compile "${ACTOOL_TMP}/build" \
  --output-format human-readable-text \
  --notices \
  --warnings \
  --app-icon "$ICON_BASENAME" \
  --platform macosx \
  --target-device mac \
  --minimum-deployment-target 26.2 \
  --development-region English \
  --enable-on-demand-resources NO \
  --output-partial-info-plist "${ACTOOL_TMP}/partial.plist" >/dev/null

if [[ -f "${ACTOOL_TMP}/build/${ICON_BASENAME}.icns" ]]; then
  cp "${ACTOOL_TMP}/build/${ICON_BASENAME}.icns" "$DISTRIBUTION_ICNS_OUTPUT"
fi

MENU_REGULAR_S_SVG="$OUTPUT_DIR/Menu-Regular-S.svg"
MENU_BASE_PNG="$OUTPUT_DIR/Menu-64.png"
MENU_BASE_PNG_RAW="$OUTPUT_DIR/Menu-512-raw.png"

if [[ -f "$MENU_SVG_SOURCE" ]]; then
  python3 - "$MENU_SVG_SOURCE" "$MENU_REGULAR_S_SVG" <<'PY'
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

SVG_NS = "http://www.w3.org/2000/svg"
NS = {"svg": SVG_NS}


def parse_matrix_transform(transform: str):
    if not transform:
        return transform
    match = re.match(r"matrix\(([^)]+)\)", transform.strip())
    if not match:
        return transform
    values = [v for v in re.split(r"[,\s]+", match.group(1).strip()) if v]
    if len(values) != 6:
        return transform
    return f"matrix({values[0]} {values[1]} {values[2]} {values[3]} {values[4]} {values[5]})"


src_path = Path(sys.argv[1])
out_path = Path(sys.argv[2])

tree = ET.parse(src_path)
root = tree.getroot()

left_line = root.find(".//svg:line[@id='left-margin-Regular-S']", NS)
right_line = root.find(".//svg:line[@id='right-margin-Regular-S']", NS)
regular_group = root.find(".//svg:g[@id='Regular-S']", NS)

if left_line is None or right_line is None or regular_group is None:
    raise SystemExit(f"Could not find Regular-S guides/group in {src_path}")

left = float(left_line.get("x1"))
right = float(right_line.get("x1"))
top = float(left_line.get("y1"))
bottom = float(left_line.get("y2"))

path_nodes = regular_group.findall(".//svg:path", NS)
filtered_nodes = []
for path in path_nodes:
    class_attr = path.get("class", "")
    if len(path_nodes) > 1 and ("monochrome-0" in class_attr or "hierarchical-0" in class_attr):
        continue
    filtered_nodes.append(path)

if not filtered_nodes:
    filtered_nodes = path_nodes

symbol_paths = []
for path in filtered_nodes:
    d_attr = path.get("d")
    if not d_attr:
        continue
    symbol_paths.append(d_attr)

if not symbol_paths:
    raise SystemExit(f"No path content found in Regular-S group for {src_path}")

cx = (left + right) / 2.0
cy = (top + bottom) / 2.0
w = abs(right - left)
h = abs(bottom - top)
side = max(w, h)
view_left = cx - side / 2.0
view_top = cy - side / 2.0
transform = parse_matrix_transform(regular_group.get("transform", ""))

out_root = ET.Element(
    "svg",
    {
        "xmlns": SVG_NS,
        "version": "1.1",
        "viewBox": f"{view_left:.6f} {view_top:.6f} {side:.6f} {side:.6f}",
    },
)
out_group = ET.SubElement(out_root, "g")
if transform:
    out_group.set("transform", transform)

for d_attr in symbol_paths:
    ET.SubElement(
        out_group,
        "path",
        {
            "d": d_attr,
            "fill": "#000000",
            "stroke": "none",
        },
    )

ET.ElementTree(out_root).write(out_path, encoding="utf-8", xml_declaration=True)
PY
else
  cat > "$MENU_REGULAR_S_SVG" <<'SVG'
<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" version="1.1" viewBox="0 0 64 64">
  <rect x="6" y="16" width="52" height="32" rx="6" ry="6" fill="none" stroke="#000000" stroke-width="4"/>
  <g fill="#000000">
    <rect x="14" y="24" width="6" height="6" rx="1"/>
    <rect x="24" y="24" width="6" height="6" rx="1"/>
    <rect x="34" y="24" width="6" height="6" rx="1"/>
    <rect x="44" y="24" width="6" height="6" rx="1"/>
    <rect x="14" y="34" width="24" height="6" rx="1"/>
    <rect x="42" y="34" width="8" height="6" rx="1"/>
  </g>
</svg>
SVG
fi

sips -s format pdf "$MENU_REGULAR_S_SVG" --out "$MENU_VECTOR_OUTPUT" >/dev/null
sips -s format png --resampleHeightWidth 512 512 "$MENU_REGULAR_S_SVG" --out "$MENU_BASE_PNG_RAW" >/dev/null
python3 - "$MENU_BASE_PNG_RAW" "$MENU_BASE_PNG" <<'PY'
import sys
from PIL import Image

src = Image.open(sys.argv[1]).convert("RGBA")
alpha = src.getchannel("A")
bbox = alpha.getbbox()
if not bbox:
    Image.new("RGBA", (64, 64), (0, 0, 0, 0)).save(sys.argv[2])
    raise SystemExit(0)

crop = src.crop(bbox)
cw, ch = crop.size
target_canvas = 64
target_max_side = 62
scale = target_max_side / float(max(cw, ch))
new_w = max(1, int(round(cw * scale)))
new_h = max(1, int(round(ch * scale)))
resized = crop.resize((new_w, new_h), Image.Resampling.LANCZOS)

canvas = Image.new("RGBA", (target_canvas, target_canvas), (0, 0, 0, 0))
offset = ((target_canvas - new_w) // 2, (target_canvas - new_h) // 2)
canvas.alpha_composite(resized, dest=offset)
canvas.save(sys.argv[2])
PY
cp "$MENU_BASE_PNG" "$MENU_RASTER_OUTPUT"

echo "Using icon source: $ICON_SOURCE"
echo "Updated Icon Composer app icon assets (iconstack xcassets), menu template assets (PNG/PDF), and distribution icns artifact."
