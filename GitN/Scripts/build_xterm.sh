#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
XTERM_DIR="${SCRIPT_DIR}/../Xterm"
OUT_DIR="${SCRIPT_DIR}/../Sources/GitN/Resources/Xterm"
DIST_DIR="${XTERM_DIR}/dist"

needs_build=1
if [ -f "${DIST_DIR}/app.js" ] &&
   [ "${DIST_DIR}/app.js" -nt "${XTERM_DIR}/package.json" ] &&
   [ "${DIST_DIR}/app.js" -nt "${XTERM_DIR}/package-lock.json" ] &&
   [ "${DIST_DIR}/app.js" -nt "${XTERM_DIR}/webpack.config.js" ] &&
   [ -z "$(find "${XTERM_DIR}/src" -type f -newer "${DIST_DIR}/app.js" -print -quit)" ]; then
    needs_build=0
fi

if [ "$needs_build" -eq 1 ]; then
    echo "       Installing xterm dependencies..."
    cd "$XTERM_DIR"
    npm ci --prefer-offline --ignore-scripts

    echo "       Building xterm bundle..."
    npm run build
else
    echo "       xterm bundle up to date."
fi

echo "       Syncing to Resources..."
echo "       (Preserving host.css, index.html)"

mkdir -p "$OUT_DIR"

# Sync generated bundle files; the hand-crafted host files live directly in
# Resources/Xterm/ and must never be overwritten by the generated output.
rsync -a --delete \
    --exclude='host.css' \
    --exclude='index.html' \
    "${DIST_DIR}/" "${OUT_DIR}/"

# Copy the hand-crafted host files from src into Resources on first run / when changed.
cp "${XTERM_DIR}/src/index.html" "${OUT_DIR}/index.html"
cp "${XTERM_DIR}/src/host.css" "${OUT_DIR}/host.css"

echo "       xterm synced to ${OUT_DIR}"
