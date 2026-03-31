#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPT_DIR}/lib/sparkle_env.sh"

: "${APP_VERSION:?Set APP_VERSION, for example 1.2.0}"
: "${APP_BUILD:?Set APP_BUILD, for example 1200}"
: "${SPARKLE_PUBLIC_ED_KEY:?Set SPARKLE_PUBLIC_ED_KEY from Sparkle generate_keys}"

UPDATES_DIR="${UPDATES_DIR:-${PROJECT_DIR}/build/updates}"
APPCAST_FILENAME="${APPCAST_FILENAME:-appcast.xml}"
APPCAST_OUTPUT_PATH="${UPDATES_DIR}/${APPCAST_FILENAME}"
SPARKLE_TOOLS_BIN="$(require_sparkle_bin_dir)"

derive_download_url_prefix() {
    local feed_url="${1:-}"

    if [[ "$feed_url" == *"/download?"* ]] && [[ "$feed_url" == *"source="* ]] && [[ "$feed_url" == *"/appcast.xml" ]]; then
        printf '%s\n' "${feed_url%/appcast.xml}"
        return 0
    fi

    return 1
}

rewrite_appcast_enclosure_urls() {
    local appcast_path="${1:?}"
    local download_prefix="${2:?}"

    /usr/bin/python3 - "$appcast_path" "$download_prefix" <<'PY'
import sys
import urllib.parse
import xml.etree.ElementTree as ET

appcast_path = sys.argv[1]
download_prefix = sys.argv[2].rstrip("/")

tree = ET.parse(appcast_path)
root = tree.getroot()

for enclosure in root.iter("enclosure"):
    current_url = enclosure.attrib.get("url", "")
    parsed = urllib.parse.urlparse(current_url)
    filename = parsed.path.rsplit("/", 1)[-1]
    if not filename:
        continue
    enclosure.set("url", f"{download_prefix}/{filename}")

tree.write(appcast_path, encoding="utf-8", xml_declaration=True)
PY
}

export BUILD_CONFIG=release
export SIGNING_IDENTITY="${SIGNING_IDENTITY-}"
export APP_VERSION
export APP_BUILD
export SPARKLE_PUBLIC_ED_KEY
export SPARKLE_FEED_URL

cd "$PROJECT_DIR"

rm -rf "$UPDATES_DIR"
./build.sh
"${SCRIPT_DIR}/package_update.sh" "${PROJECT_DIR}/build/GitN.app" "$UPDATES_DIR" >/dev/null

GENERATE_APPCAST_ARGS=(-o "$APPCAST_OUTPUT_PATH")
DOWNLOAD_URL_PREFIX_TO_USE=""
if [ -n "${SPARKLE_DOWNLOAD_URL_PREFIX:-}" ]; then
    DOWNLOAD_URL_PREFIX_TO_USE="$SPARKLE_DOWNLOAD_URL_PREFIX"
    GENERATE_APPCAST_ARGS+=(--download-url-prefix "$SPARKLE_DOWNLOAD_URL_PREFIX")
elif DERIVED_DOWNLOAD_URL_PREFIX="$(derive_download_url_prefix "${SPARKLE_FEED_URL}")"; then
    echo "Derived SPARKLE_DOWNLOAD_URL_PREFIX from SPARKLE_FEED_URL:" >&2
    echo "         ${DERIVED_DOWNLOAD_URL_PREFIX}" >&2
    DOWNLOAD_URL_PREFIX_TO_USE="$DERIVED_DOWNLOAD_URL_PREFIX"
    GENERATE_APPCAST_ARGS+=(--download-url-prefix "$DERIVED_DOWNLOAD_URL_PREFIX")
elif [[ "${SPARKLE_FEED_URL}" == *\?* ]]; then
    echo "Warning: SPARKLE_FEED_URL contains query parameters." >&2
    echo "         Set SPARKLE_DOWNLOAD_URL_PREFIX explicitly so generated zip URLs are correct." >&2
fi

"${SPARKLE_TOOLS_BIN}/generate_appcast" "${GENERATE_APPCAST_ARGS[@]}" "$UPDATES_DIR"
if [ -n "$DOWNLOAD_URL_PREFIX_TO_USE" ]; then
    rewrite_appcast_enclosure_urls "$APPCAST_OUTPUT_PATH" "$DOWNLOAD_URL_PREFIX_TO_USE"
fi

INFO_PLIST="${PROJECT_DIR}/build/GitN.app/Contents/Info.plist"
ICON_FILE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$INFO_PLIST")"
PUBLIC_KEY="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$INFO_PLIST")"
FEED_URL="$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$INFO_PLIST")"

echo ""
echo "Prepared Sparkle release artifacts:"
echo "  App:      ${PROJECT_DIR}/build/GitN.app"
echo "  Updates:  ${UPDATES_DIR}"
echo "  Appcast:  ${APPCAST_OUTPUT_PATH}"
echo "  Icon:     ${ICON_FILE}"
echo "  Feed URL: ${FEED_URL}"
echo "  Ed Key:   ${PUBLIC_KEY}"
