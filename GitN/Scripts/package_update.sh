#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

APP_PATH="${1:-${PROJECT_DIR}/build/GitN.app}"
OUTPUT_DIR="${2:-${PROJECT_DIR}/build/updates}"
INFO_PLIST="${APP_PATH}/Contents/Info.plist"

if [ ! -d "$APP_PATH" ]; then
    echo "App bundle not found: $APP_PATH" >&2
    exit 1
fi

if [ ! -f "$INFO_PLIST" ]; then
    echo "Info.plist not found: $INFO_PLIST" >&2
    exit 1
fi

APP_NAME="$(basename "$APP_PATH" .app)"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST")"
ZIP_NAME="${APP_NAME}-${VERSION}-${BUILD_NUMBER}.zip"

mkdir -p "$OUTPUT_DIR"
rm -f "${OUTPUT_DIR}/${ZIP_NAME}"

ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "${OUTPUT_DIR}/${ZIP_NAME}"
echo "${OUTPUT_DIR}/${ZIP_NAME}"
