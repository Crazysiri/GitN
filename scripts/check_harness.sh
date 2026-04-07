#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

BASE_REF="${1:-${HARNESS_DIFF_BASE:-}}"

collect_changed_files() {
    if [[ -n "$BASE_REF" ]]; then
        local merge_base
        merge_base="$(git merge-base HEAD "$BASE_REF")"
        git diff --name-only "$merge_base"...HEAD
        return
    fi

    git status --short --untracked-files=all | awk '{print $2}'
}

declare -a CHANGED_FILES=()
while IFS= read -r file; do
    CHANGED_FILES+=("$file")
done < <(collect_changed_files | sed '/^$/d' | sort -u)

if [[ "${#CHANGED_FILES[@]}" -eq 0 ]]; then
    echo "Harness check: no changed files detected."
    exit 0
fi

is_code_change=false
declare -a INTAKE_FILES=()

for file in "${CHANGED_FILES[@]}"; do
    case "$file" in
        GitN/Sources/GitN/*|GitN/Tests/GitNTests/*|GitN/Package.swift)
            is_code_change=true
            ;;
    esac

    case "$file" in
        docs/intake/*.md)
            if [[ "$file" != "docs/intake/README.md" ]]; then
                INTAKE_FILES+=("$file")
            fi
            ;;
    esac
done

if [[ "$is_code_change" == false ]]; then
    echo "Harness check: no app code changes require intake."
    exit 0
fi

if [[ "${#INTAKE_FILES[@]}" -eq 0 ]]; then
    echo "Harness check failed."
    echo "Code changes require a filled feature intake in docs/intake/."
    echo "Start from docs/templates/feature-intake-template.md."
    exit 1
fi

validate_intake_file() {
    local file="$1"
    local failed=false

    local required_headers=(
        "## Summary"
        "## Behavior Change"
        "## Non-Goals"
        "## Change Boundary"
        "## Ownership"
        "## Test Scope"
        "## Design Records"
        "## Completion Criteria"
    )

    for header in "${required_headers[@]}"; do
        if ! rg -q "^${header}$" "$file"; then
            echo "Harness check failed: missing '${header}' in ${file}"
            failed=true
        fi
    done

    local required_fields=(
        "^- Status: .+"
        "^- Owner: .+"
        "^- Date: [0-9]{4}-[0-9]{2}-[0-9]{2}$"
        "^- In scope: .+"
        "^- Out of scope: .+"
        "^- Protected hotspots reviewed: .+"
        "^- Primary owner layer: .+"
        "^- Why this layer is the right owner: .+"
        "^- Which larger type is intentionally not taking more responsibility: .+"
        "^- Unit tests: .+"
        "^- Manual verification: .+"
        "^- Failure modes / edge cases: .+"
        "^- Known coverage blockers: .+"
        "^- RFC required\\? .+"
        "^- ADR required\\? .+"
    )

    for pattern in "${required_fields[@]}"; do
        if ! rg -q "$pattern" "$file"; then
            echo "Harness check failed: missing required filled field matching '${pattern}' in ${file}"
            failed=true
        fi
    done

    local placeholder_strings=(
        "YYYY-MM-DD"
        "Describe the change in one paragraph."
        "What is intentionally not changing?"
        "Any unresolved product or technical questions:"
        "What must be true before implementation is considered done?"
    )

    for placeholder in "${placeholder_strings[@]}"; do
        if rg -F -q "$placeholder" "$file"; then
            echo "Harness check failed: template placeholder '${placeholder}' still present in ${file}"
            failed=true
        fi
    done

    if [[ "$failed" == true ]]; then
        exit 1
    fi
}

for intake in "${INTAKE_FILES[@]}"; do
    validate_intake_file "$intake"
done

echo "Harness check passed:"
printf ' - %s\n' "${INTAKE_FILES[@]}"
