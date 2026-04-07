#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ $# -lt 1 ]]; then
    echo "Usage: scripts/new_feature_intake.sh <short-slug>"
    exit 1
fi

SLUG="$1"
DATE_PREFIX="${2:-$(date +%F)}"
DESTINATION="docs/intake/${DATE_PREFIX}-${SLUG}.md"

if [[ -e "$DESTINATION" ]]; then
    echo "Refusing to overwrite existing file: $DESTINATION"
    exit 1
fi

cp "docs/templates/feature-intake-template.md" "$DESTINATION"
echo "Created $DESTINATION"
