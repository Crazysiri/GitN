#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MONACO_DIR="${SCRIPT_DIR}/../Monaco"
OUT_DIR="${SCRIPT_DIR}/../Sources/GitN/Resources/Monaco"
DIST_DIR="${MONACO_DIR}/dist"

# Skip rebuild if dist is newer than package.json (version unchanged)
if [ -d "$DIST_DIR" ] && [ -f "${DIST_DIR}/app.js" ]; then
    if [ "${DIST_DIR}/app.js" -nt "${MONACO_DIR}/package.json" ]; then
        echo "       Monaco bundle up to date, skipping."
        exit 0
    fi
fi

echo "       Installing Monaco dependencies..."
cd "$MONACO_DIR"
npm install --prefer-offline

echo "       Building Monaco (this may take a minute)..."
npm run build

echo "       Syncing to Resources..."
echo "       (Preserving host.js, host.css, index.html)"

# Sync all generated files; explicitly exclude hand-crafted files
rsync -a --delete \
    --exclude='host.js' \
    --exclude='host.css' \
    --exclude='index.html' \
    "${DIST_DIR}/" "${OUT_DIR}/"

echo "       Monaco synced to ${OUT_DIR}"
