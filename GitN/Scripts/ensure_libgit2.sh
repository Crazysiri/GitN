#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

LIBGIT2_DIR="${LIBGIT2_DIR:-${REPO_ROOT}/Sources/Clibgit2/libgit2}"
LIBGIT2_VERSION="${LIBGIT2_VERSION:-v1.9.1}"
LIBGIT2_REPO="${LIBGIT2_REPO:-https://github.com/libgit2/libgit2.git}"

if [ -f "${LIBGIT2_DIR}/CMakeLists.txt" ]; then
    echo "libgit2 source already present at ${LIBGIT2_DIR}"
    exit 0
fi

if [ -e "${LIBGIT2_DIR}" ] && [ ! -d "${LIBGIT2_DIR}" ]; then
    echo "ERROR: ${LIBGIT2_DIR} exists but is not a directory."
    exit 1
fi

mkdir -p "$(dirname "${LIBGIT2_DIR}")"

if [ -d "${LIBGIT2_DIR}" ]; then
    if find "${LIBGIT2_DIR}" -mindepth 1 -maxdepth 1 | read -r _; then
        echo "ERROR: ${LIBGIT2_DIR} exists but does not look like a libgit2 checkout."
        echo "       Remove it or set LIBGIT2_DIR manually before retrying."
        exit 1
    fi
    rmdir "${LIBGIT2_DIR}"
fi

echo "Fetching libgit2 ${LIBGIT2_VERSION} into ${LIBGIT2_DIR} ..."
git clone --depth 1 --branch "${LIBGIT2_VERSION}" "${LIBGIT2_REPO}" "${LIBGIT2_DIR}"
