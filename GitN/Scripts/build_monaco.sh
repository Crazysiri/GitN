#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MONACO_DIR="${SCRIPT_DIR}/../Monaco"
OUT_DIR="${SCRIPT_DIR}/../Sources/GitN/Resources/Monaco"
DIST_DIR="${MONACO_DIR}/dist"

needs_build=1
if [ -f "${DIST_DIR}/app.js" ] &&
   [ "${DIST_DIR}/app.js" -nt "${MONACO_DIR}/package.json" ] &&
   [ "${DIST_DIR}/app.js" -nt "${MONACO_DIR}/package-lock.json" ] &&
   [ "${DIST_DIR}/app.js" -nt "${MONACO_DIR}/webpack.config.js" ] &&
   [ "${DIST_DIR}/app.js" -nt "${MONACO_DIR}/webpack.worker.config.js" ] &&
   [ -z "$(find "${MONACO_DIR}/src" -type f -newer "${DIST_DIR}/app.js" -print -quit)" ]; then
    needs_build=0
fi

if [ "$needs_build" -eq 1 ]; then
    echo "       Installing Monaco dependencies..."
    cd "$MONACO_DIR"
    npm install --prefer-offline

    echo "       Building Monaco (this may take a minute)..."
    npm run build
else
    echo "       Monaco bundle up to date."
fi

echo "       Syncing to Resources..."
echo "       (Preserving host.js, host.css, index.html)"

# Sync all generated files; explicitly exclude hand-crafted files
rsync -a --delete \
    --exclude='host.js' \
    --exclude='host.css' \
    --exclude='index.html' \
    "${DIST_DIR}/" "${OUT_DIR}/"

echo "       Monaco synced to ${OUT_DIR}"
