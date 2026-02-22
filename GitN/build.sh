#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

APP_NAME="GitN"
BUILD_CONFIG="release"
BUILD_DIR=".build/${BUILD_CONFIG}"
OUTPUT_DIR="build"
BUNDLE_DIR="${OUTPUT_DIR}/${APP_NAME}.app"
ICON_SCRIPT="Scripts/generate_icon.swift"

echo "=========================================="
echo "  Building ${APP_NAME}.app"
echo "=========================================="

# ──────────────────────────────────────────────
# Step 1: Generate app icon
# ──────────────────────────────────────────────
echo ""
echo "[1/4] Generating app icon..."

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
# Step 2: Build Swift package (release)
# ──────────────────────────────────────────────
echo ""
echo "[2/4] Building Swift package (${BUILD_CONFIG})..."

swift build -c "$BUILD_CONFIG" 2>&1

BINARY="${BUILD_DIR}/${APP_NAME}"
if [ ! -f "$BINARY" ]; then
    echo "ERROR: Binary not found at ${BINARY}"
    exit 1
fi
echo "       Binary built: ${BINARY}"

# ──────────────────────────────────────────────
# Step 3: Create .app bundle
# ──────────────────────────────────────────────
echo ""
echo "[3/4] Creating app bundle..."

rm -rf "$BUNDLE_DIR"
mkdir -p "${BUNDLE_DIR}/Contents/MacOS"
mkdir -p "${BUNDLE_DIR}/Contents/Resources"

cp "$BINARY" "${BUNDLE_DIR}/Contents/MacOS/${APP_NAME}"
cp "$ICNS_FILE" "${BUNDLE_DIR}/Contents/Resources/AppIcon.icns"

YEAR=$(date +%Y)
cat > "${BUNDLE_DIR}/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>com.gitn.app</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © ${YEAR}. All rights reserved.</string>
    <key>NSSupportsAutomaticTermination</key>
    <false/>
    <key>NSSupportsSuddenTermination</key>
    <false/>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.developer-tools</string>
</dict>
</plist>
PLIST

echo "       Bundle created: ${BUNDLE_DIR}"

# ──────────────────────────────────────────────
# Step 4: Ad-hoc code sign
# ──────────────────────────────────────────────
echo ""
echo "[4/4] Code signing (ad-hoc)..."

codesign --force --deep --sign - "$BUNDLE_DIR" 2>&1
echo "       Signed."

# ──────────────────────────────────────────────
# Done
# ──────────────────────────────────────────────
BUNDLE_SIZE=$(du -sh "$BUNDLE_DIR" | cut -f1)
echo ""
echo "=========================================="
echo "  Build complete!"
echo "  ${BUNDLE_DIR}  (${BUNDLE_SIZE})"
echo "=========================================="
echo ""
echo "Run with:  open ${BUNDLE_DIR}"
