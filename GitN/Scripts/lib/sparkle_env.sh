#!/bin/bash

set -euo pipefail

is_sparkle_bin_dir() {
    local candidate="${1:-}"
    [ -n "$candidate" ] || return 1
    [ -f "${candidate}/generate_appcast" ] && [ -x "${candidate}/generate_appcast" ]
}

resolve_sparkle_bin_candidate() {
    local candidate="${1:-}"
    [ -n "$candidate" ] || return 1

    if is_sparkle_bin_dir "$candidate"; then
        printf '%s\n' "$candidate"
        return 0
    fi

    if is_sparkle_bin_dir "${candidate}/bin"; then
        printf '%s\n' "${candidate}/bin"
        return 0
    fi

    return 1
}

resolve_sparkle_bin_dir() {
    if [ -n "${SPARKLE_BIN_DIR:-}" ]; then
        if resolve_sparkle_bin_candidate "${SPARKLE_BIN_DIR}"; then
            return 0
        fi
    fi

    local source_path script_dir project_dir candidate
    source_path="${BASH_SOURCE[0]:-$0}"
    script_dir="$(cd "$(dirname "$source_path")" && pwd)"
    project_dir="$(cd "${script_dir}/../.." && pwd)"

    for candidate in \
        "${project_dir}/.build/artifacts/sparkle/Sparkle/bin" \
        "${project_dir}/.build/artifacts/sparkle/Sparkle" \
        "${project_dir}/.build/artifacts/sparkle/bin" \
        "${project_dir}/.build/checkouts/sparkle" \
        "${project_dir}/.build/checkouts/Sparkle" \
        "${project_dir}/.build/checkouts/sparkle/bin" \
        "${project_dir}/.build/checkouts/Sparkle/bin" \
        "/Applications/Sparkle/bin"
    do
        if resolve_sparkle_bin_candidate "$candidate"; then
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
- GitN/.build/checkouts/sparkle
- GitN/.build/checkouts/Sparkle
- /Applications/Sparkle/bin
EOF
    return 1
}
