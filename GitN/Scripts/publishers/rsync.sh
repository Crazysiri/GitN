#!/bin/bash
set -euo pipefail

UPDATES_DIR="${1:?Usage: rsync.sh <updates-dir>}"

: "${RSYNC_DESTINATION:?Set RSYNC_DESTINATION, for example deploy@example.com:/var/www/updates/gitn}"

RSYNC_FLAGS="${RSYNC_FLAGS:--avz --delete}"

rsync ${RSYNC_FLAGS} "${UPDATES_DIR}/" "${RSYNC_DESTINATION}/"
echo "Published updates to ${RSYNC_DESTINATION}"
