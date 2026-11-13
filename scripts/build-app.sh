#!/usr/bin/env bash
# Builds Grip.app (universal: Apple Silicon + Intel) and zips it into dist/.
# Runs on macOS (GitHub Actions or locally): ./scripts/build-app.sh [version]
set -euo pipefail

cd "$(dirname "$0")/.."
VERSION="${1:-0.1.0}"
BUILD="${GITHUB_RUN_NUMBER:-1}"
APP="dist/Grip.app"

echo "▶ Building Grip $VERSION ($BUILD)"
swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/Grip"

rm -rf dist
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Grip"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" Resources/Info.plist > "$APP/Contents/Info.plist"

# App icon (.icns) from the 1024px PNG
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s Resources/AppIcon.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s * 2)) $((s * 2)) Resources/AppIcon.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

# Ad-hoc signature (required to run on Apple Silicon; not notarized)
codesign --force --deep --sign - "$APP"
codesign --verify --verbose "$APP"

ditto -c -k --keepParent "$APP" "dist/Grip-$VERSION.zip"
echo "✔ dist/Grip-$VERSION.zip"
