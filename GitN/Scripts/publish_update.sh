#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

PUBLISHER_SCRIPT="${UPDATE_PUBLISHER_SCRIPT:-${SCRIPT_DIR}/publishers/s3.sh}"
UPDATES_DIR="${1:-${PROJECT_DIR}/build/updates}"

if [ ! -x "$PUBLISHER_SCRIPT" ]; then
    echo "Publisher script is not executable: $PUBLISHER_SCRIPT" >&2
    exit 1
fi

if [ ! -d "$UPDATES_DIR" ]; then
    echo "Updates directory not found: $UPDATES_DIR" >&2
    exit 1
fi

"$PUBLISHER_SCRIPT" "$UPDATES_DIR"
