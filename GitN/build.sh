#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

APP_NAME="GitN"
BUILD_CONFIG="${BUILD_CONFIG:-release}"
BUILD_DIR=".build/${BUILD_CONFIG}"
OUTPUT_DIR="build"
BUNDLE_DIR="${OUTPUT_DIR}/${APP_NAME}.app"
ICON_SCRIPT="Scripts/generate_icon.swift"
APP_BUNDLE_IDENTIFIER="${APP_BUNDLE_IDENTIFIER:-com.gitn.app}"
APP_VERSION="${APP_VERSION:-1.1.0}"
APP_BUILD="${APP_BUILD:-0}"
SPARKLE_FEED_URL="${SPARKLE_FEED_URL:-}"
SPARKLE_PUBLIC_ED_KEY="${SPARKLE_PUBLIC_ED_KEY:-}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"

xml_escape() {
    /usr/bin/python3 -c 'import html, sys; print(html.escape(sys.argv[1], quote=True), end="")' "${1:-}"
}

echo "=========================================="
echo "  Building ${APP_NAME}.app ..."
echo "=========================================="

echo ""
echo "[0/4] Ensuring libgit2 source..."
"${SCRIPT_DIR}/Scripts/ensure_libgit2.sh"

# ──────────────────────────────────────────────
# Step 1: Build Monaco editor bundle
# ──────────────────────────────────────────────
echo ""
echo "[1/4] Building Monaco editor..."
"${SCRIPT_DIR}/Scripts/build_monaco.sh"

# ──────────────────────────────────────────────
# Step 2: Generate app icon
# ──────────────────────────────────────────────
echo ""
echo "[2/4] Generating app icon..."

ICONSET_DIR="${OUTPUT_DIR}/${APP_NAME}.iconset"
ICNS_FILE="${OUTPUT_DIR}/AppIcon.icns"
ICON_1024="${OUTPUT_DIR}/icon_1024.png"

mkdir -p "$OUTPUT_DIR"

if [ ! -f "$ICNS_FILE" ] || [ "$ICON_SCRIPT" -nt "$ICNS_FILE" ]; then
    swift "$ICON_SCRIPT" "$ICON_1024"

    mkdir -p "$ICONSET_DIR"
    sips -z 16 16     "$ICON_1024" --out "${ICONSET_DIR}/icon_16x16.png"      > /dev/null
    sips -z 32 32     "$ICON_1024" --out "${ICONSET_DIR}/icon_16x16@2x.png"   > /dev/null
    sips -z 32 32     "$ICON_1024" --out "${ICONSET_DIR}/icon_32x32.png"      > /dev/null
    sips -z 64 64     "$ICON_1024" --out "${ICONSET_DIR}/icon_32x32@2x.png"   > /dev/null
    sips -z 128 128   "$ICON_1024" --out "${ICONSET_DIR}/icon_128x128.png"    > /dev/null
    sips -z 256 256   "$ICON_1024" --out "${ICONSET_DIR}/icon_128x128@2x.png" > /dev/null
    sips -z 256 256   "$ICON_1024" --out "${ICONSET_DIR}/icon_256x256.png"    > /dev/null
    sips -z 512 512   "$ICON_1024" --out "${ICONSET_DIR}/icon_256x256@2x.png" > /dev/null
    sips -z 512 512   "$ICON_1024" --out "${ICONSET_DIR}/icon_512x512.png"    > /dev/null
    sips -z 1024 1024 "$ICON_1024" --out "${ICONSET_DIR}/icon_512x512@2x.png" > /dev/null

    iconutil -c icns "$ICONSET_DIR" -o "$ICNS_FILE"
    rm -rf "$ICONSET_DIR" "$ICON_1024"
    echo "       Icon generated: ${ICNS_FILE}"
else
    echo "       Icon up to date, skipping."
fi

# ──────────────────────────────────────────────
# Step 3: Build Swift package (release)
# ──────────────────────────────────────────────
echo ""
echo "[3/4] Building Swift package (${BUILD_CONFIG})..."

echo "       Cleaning previous build..."
swift package clean 2>/dev/null || true
rm -rf .build

swift build -c "$BUILD_CONFIG" 2>&1

BINARY="${BUILD_DIR}/${APP_NAME}"
if [ ! -f "$BINARY" ]; then
    echo "ERROR: Binary not found at ${BINARY}"
    exit 1
fi
echo "       Binary built: ${BINARY}"

# ──────────────────────────────────────────────
# Step 4: Create .app bundle & sign
# ──────────────────────────────────────────────
echo ""
echo "[4/4] Creating app bundle..."

rm -rf "$BUNDLE_DIR"
mkdir -p "${BUNDLE_DIR}/Contents/MacOS"
mkdir -p "${BUNDLE_DIR}/Contents/Resources"
mkdir -p "${BUNDLE_DIR}/Contents/Frameworks"

cp "$BINARY" "${BUNDLE_DIR}/Contents/MacOS/${APP_NAME}"
cp "$ICNS_FILE" "${BUNDLE_DIR}/Contents/Resources/AppIcon.icns"

python3 - <<'PY' | while IFS= read -r bundle; do
import glob
import os

seen = set()
for pattern in ('.build/release/*.bundle', '.build/*/release/*.bundle'):
    for path in sorted(glob.glob(pattern)):
        real = os.path.realpath(path)
        if real in seen:
            continue
        seen.add(real)
        print(path)
PY
    [ -n "$bundle" ] || continue
    dest="${BUNDLE_DIR}/Contents/Resources/$(basename "$bundle")"
    rm -rf "$dest"
    cp -R "$bundle" "$dest"
done

SPARKLE_FRAMEWORK="$(find .build -type d -name Sparkle.framework -print -quit 2>/dev/null || true)"
if [ -n "$SPARKLE_FRAMEWORK" ]; then
    rm -rf "${BUNDLE_DIR}/Contents/Frameworks/Sparkle.framework"
    cp -R "$SPARKLE_FRAMEWORK" "${BUNDLE_DIR}/Contents/Frameworks/"

    if ! otool -l "${BUNDLE_DIR}/Contents/MacOS/${APP_NAME}" | grep -q "@executable_path/../Frameworks"; then
        install_name_tool -add_rpath "@executable_path/../Frameworks" "${BUNDLE_DIR}/Contents/MacOS/${APP_NAME}"
    fi
fi

YEAR=$(date +%Y)
APP_NAME_XML="$(xml_escape "${APP_NAME}")"
APP_BUNDLE_IDENTIFIER_XML="$(xml_escape "${APP_BUNDLE_IDENTIFIER}")"
APP_VERSION_XML="$(xml_escape "${APP_VERSION}")"
APP_BUILD_XML="$(xml_escape "${APP_BUILD}")"
SPARKLE_FEED_URL_XML="$(xml_escape "${SPARKLE_FEED_URL}")"
SPARKLE_PUBLIC_ED_KEY_XML="$(xml_escape "${SPARKLE_PUBLIC_ED_KEY}")"
YEAR_XML="$(xml_escape "${YEAR}")"
cat > "${BUNDLE_DIR}/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME_XML}</string>
    <key>CFBundleIdentifier</key>
    <string>${APP_BUNDLE_IDENTIFIER_XML}</string>
    <key>CFBundleName</key>
    <string>${APP_NAME_XML}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME_XML}</string>
    <key>CFBundleVersion</key>
    <string>${APP_BUILD_XML}</string>
    <key>CFBundleShortVersionString</key>
    <string>${APP_VERSION_XML}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon.icns</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © ${YEAR_XML}. All rights reserved.</string>
    <key>NSSupportsAutomaticTermination</key>
    <false/>
    <key>NSSupportsSuddenTermination</key>
    <false/>
    <key>SUFeedURL</key>
    <string>${SPARKLE_FEED_URL_XML}</string>
    <key>SUPublicEDKey</key>
    <string>${SPARKLE_PUBLIC_ED_KEY_XML}</string>
    <key>SUEnableAutomaticChecks</key>
    <true/>
    <key>SUAutomaticallyUpdate</key>
    <true/>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.developer-tools</string>
</dict>
</plist>
PLIST

if [ -n "$SPARKLE_FRAMEWORK" ]; then
    codesign --force --sign "$SIGNING_IDENTITY" "${BUNDLE_DIR}/Contents/Frameworks/Sparkle.framework" 2>&1
fi

codesign --force --deep --sign "$SIGNING_IDENTITY" "$BUNDLE_DIR" 2>&1

BUNDLE_SIZE=$(du -sh "$BUNDLE_DIR" | cut -f1)
echo ""
echo "=========================================="
echo "  Build complete!"
echo "  ${BUNDLE_DIR}  (${BUNDLE_SIZE})"
echo "=========================================="
echo ""
echo "Run with:  open ${BUNDLE_DIR}"
