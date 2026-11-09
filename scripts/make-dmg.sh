#!/bin/bash
# Build a drag-to-Applications DMG for Solara Display.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Solara Display.app"
VOLUME_NAME="Solara Display"
DIST="${ROOT}/dist"
APP="${DIST}/${APP_NAME}"
FINAL="${DIST}/Solara Display.dmg"
DESKTOP_DIR="${HOME}/Desktop/Solara Display"
DESKTOP_DMG="${DESKTOP_DIR}/Solara Display.dmg"
REPO_DMG="${ROOT}/Solara Display.dmg"
STAGING="$(mktemp -d /tmp/solara-dmg-XXXXXX)"
RW="${STAGING}/rw.dmg"
BG="${STAGING}/background.png"

cleanup() {
  if [[ -n "${MOUNT:-}" && -d "${MOUNT}" ]]; then
    hdiutil detach "${MOUNT}" -quiet -force || true
  fi
  rm -rf "${STAGING}"
}
trap cleanup EXIT

if [[ ! -d "${APP}" ]]; then
  echo "Missing ${APP}" >&2
  echo "Build first: xcodebuild -scheme Solara -configuration Release CONFIGURATION_BUILD_DIR=${DIST}" >&2
  exit 1
fi

python3 - "${BG}" <<'PY'
import struct, sys, zlib

path = sys.argv[1]
w, h = 540, 360

def lerp(a, b, t):
    return int(a + (b - a) * t)

pixels = bytearray()
for y in range(h):
    pixels.append(0)
    for x in range(w):
        t = y / max(h - 1, 1)
        r, g, b = lerp(22, 14, t), lerp(18, 11, t), lerp(16, 10, t)
        cx, cy = 270, 168
        dx, dy = x - cx, y - cy
        # chevron pointing to Applications
        if abs(dy) < 28 and abs(dx) < 34:
            if 0.45 * abs(dy) + 6 < dx < 0.45 * abs(dy) + 14:
                r, g, b = 250, 168, 48
        pixels.extend((r, g, b))

def chunk(tag, data):
    crc = zlib.crc32(tag + data) & 0xFFFFFFFF
    return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", crc)

ihdr = struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)
png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(bytes(pixels), 9)) + chunk(b"IEND", b"")
with open(path, "wb") as fh:
    fh.write(png)
PY

STAGE_VOL="${STAGING}/volume"
mkdir -p "${STAGE_VOL}/.background"
ditto "${APP}" "${STAGE_VOL}/${APP_NAME}"
ln -s /Applications "${STAGE_VOL}/Applications"
cp "${BG}" "${STAGE_VOL}/.background/background.png"

hdiutil create \
  -ov \
  -volname "${VOLUME_NAME}" \
  -fs HFS+ \
  -format UDRW \
  -srcfolder "${STAGE_VOL}" \
  "${RW}" >/dev/null

hdiutil resize -size 80m "${RW}" >/dev/null

ATTACH="$(hdiutil attach -readwrite -noverify -noautoopen "${RW}")"
MOUNT="$(python3 -c "
import sys
text = sys.argv[1]
for line in text.splitlines():
    idx = line.find('/Volumes/')
    if idx >= 0:
        print(line[idx:].strip())
        break
" "${ATTACH}")"

if [[ -z "${MOUNT}" || ! -d "${MOUNT}" ]]; then
  echo "Failed to mount disk image" >&2
  exit 1
fi

# Hide helper folder so only the app and Applications remain visible.
if command -v SetFile >/dev/null 2>&1; then
  SetFile -a V "${MOUNT}/.background" || true
else
  chflags hidden "${MOUNT}/.background" || true
fi

# Finder layout: app on the left, Applications on the right.
osascript <<EOF || true
tell application "Finder"
  tell disk "${VOLUME_NAME}"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set bounds of container window to {360, 180, 900, 540}
    set theViewOptions to the icon view options of container window
    set arrangement of theViewOptions to not arranged
    set icon size of theViewOptions to 128
    set background picture of theViewOptions to file ".background:background.png"
    delay 0.4
    set position of item "${APP_NAME}" to {140, 168}
    set position of item "Applications" to {400, 168}
    close
    open
    update without registering applications
    delay 1
  end tell
end tell
EOF

sync
hdiutil detach "${MOUNT}" -quiet
MOUNT=""

rm -f "${FINAL}" "${REPO_DMG}"
hdiutil convert "${RW}" -format UDZO -imagekey zlib-level=9 -o "${FINAL}" >/dev/null
mkdir -p "${DESKTOP_DIR}"
cp -f "${FINAL}" "${DESKTOP_DMG}"
cp -f "${FINAL}" "${REPO_DMG}"

echo "${FINAL}"
echo "${DESKTOP_DMG}"
echo "${REPO_DMG}"
du -sh "${FINAL}"
