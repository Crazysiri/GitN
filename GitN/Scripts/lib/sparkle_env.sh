#!/bin/bash

set -euo pipefail

resolve_sparkle_bin_dir() {
    if [ -n "${SPARKLE_BIN_DIR:-}" ]; then
        if [ -f "${SPARKLE_BIN_DIR}/generate_appcast" ] && [ -x "${SPARKLE_BIN_DIR}/generate_appcast" ]; then
            printf '%s\n' "$SPARKLE_BIN_DIR"
            return 0
        fi

        if [ -f "${SPARKLE_BIN_DIR}/bin/generate_appcast" ] && [ -x "${SPARKLE_BIN_DIR}/bin/generate_appcast" ]; then
            printf '%s\n' "${SPARKLE_BIN_DIR}/bin"
            return 0
        fi
    fi

    local source_path script_dir project_dir candidate
    source_path="${BASH_SOURCE[0]:-$0}"
    script_dir="$(cd "$(dirname "$source_path")" && pwd)"
    project_dir="$(cd "${script_dir}/../.." && pwd)"

    for candidate in \
        "${project_dir}/.build/artifacts/sparkle/Sparkle/bin" \
        "${project_dir}/.build/checkouts/Sparkle" \
        "/Applications/Sparkle/bin"
    do
        if [ -f "${candidate}/generate_appcast" ] && [ -x "${candidate}/generate_appcast" ]; then
            printf '%s\n' "$candidate"
            return 0
        fi

        if [ -f "${candidate}/bin/generate_appcast" ] && [ -x "${candidate}/bin/generate_appcast" ]; then
            printf '%s\n' "${candidate}/bin"
            return 0
        fi
    done

    return 1
}

require_sparkle_bin_dir() {
    local resolved
    if resolved="$(resolve_sparkle_bin_dir)"; then
        printf '%s\n' "$resolved"
        return 0
    fi

    cat >&2 <<'EOF'
Unable to locate Sparkle tools.

Set SPARKLE_BIN_DIR explicitly, or let the script auto-detect one of:
- GitN/.build/artifacts/sparkle/Sparkle/bin
- GitN/.build/checkouts/Sparkle
- /Applications/Sparkle/bin
EOF
    return 1
}
