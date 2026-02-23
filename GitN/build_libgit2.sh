#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

LIBGIT2_SRC="libgit2"
DIST_DIR="libgit2-dist"
XCFRAMEWORK="Clibgit2.xcframework"
STATIC_LIB="${DIST_DIR}/lib/libgit2.a"

# ──────────────────────────────────────────────
# Check: skip if already up to date
# ──────────────────────────────────────────────
if [ -f "${XCFRAMEWORK}/macos-arm64_x86_64/libgit2.a" ] && \
   [ "${XCFRAMEWORK}/macos-arm64_x86_64/libgit2.a" -nt "${LIBGIT2_SRC}/CMakeLists.txt" ]; then
    echo "Clibgit2.xcframework is up to date, skipping build."
    exit 0
fi

echo "Building libgit2 static library..."

# ──────────────────────────────────────────────
# Detect architecture & Homebrew paths
# ──────────────────────────────────────────────
ARCH=$(uname -m)
if [[ "$ARCH" == "arm64" ]]; then
    HOMEBREW_ROOT="/opt/homebrew"
else
    HOMEBREW_ROOT="/usr/local"
fi
export PATH="${HOMEBREW_ROOT}/bin:$PATH"

# ──────────────────────────────────────────────
# Check prerequisites
# ──────────────────────────────────────────────
if ! command -v cmake &> /dev/null; then
    echo "ERROR: cmake is required to build libgit2."
    echo "       Install with: brew install cmake"
    exit 1
fi

# ──────────────────────────────────────────────
# Build libgit2 as static library
# ──────────────────────────────────────────────
INSTALL_PREFIX="$(pwd)/${DIST_DIR}"
NCPU=$(sysctl -n hw.ncpu)

build_arch() {
    local arch=$1
    local build_dir="${LIBGIT2_SRC}/_build_${arch}"

    echo "  Building for ${arch}..."
    rm -rf "$build_dir"
    mkdir -p "$build_dir"

    cmake -S "$LIBGIT2_SRC" -B "$build_dir" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$INSTALL_PREFIX" \
        -DBUILD_SHARED_LIBS=OFF \
        -DBUILD_TESTS=OFF \
        -DBUILD_CLI=OFF \
        -DUSE_SSH=OFF \
        -DUSE_HTTPS=SecureTransport \
        -DTHREADSAFE=ON \
        -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
        -DCMAKE_OSX_ARCHITECTURES="$arch"

    cmake --build "$build_dir" --config Release -- -j"$NCPU"
}

build_arch "arm64"
build_arch "x86_64"

# ──────────────────────────────────────────────
# Install headers & create universal static library
# ──────────────────────────────────────────────
echo "  Installing headers and creating universal library..."
rm -rf "$DIST_DIR"

# Full install from arm64 build to get headers + lib structure
cmake --install "${LIBGIT2_SRC}/_build_arm64" --prefix "$INSTALL_PREFIX"

# Replace single-arch lib with universal (fat) binary
lipo -create \
    "${LIBGIT2_SRC}/_build_arm64/libgit2.a" \
    "${LIBGIT2_SRC}/_build_x86_64/libgit2.a" \
    -output "${DIST_DIR}/lib/libgit2.a"

# ──────────────────────────────────────────────
# Create XCFramework
# ──────────────────────────────────────────────
echo "  Creating Clibgit2.xcframework..."

# Prepare headers directory with our module map
HEADERS_DIR=$(mktemp -d)
cp -R "${DIST_DIR}/include/"* "$HEADERS_DIR/"

cat > "${HEADERS_DIR}/module.modulemap" << 'MODULEMAP'
module Clibgit2 [system] {
    header "shim.h"
    link "git2"
    export *
}
MODULEMAP

cat > "${HEADERS_DIR}/shim.h" << 'SHIM'
#ifndef CLIBGIT2_SHIM_H
#define CLIBGIT2_SHIM_H

#include <git2.h>

#endif
SHIM

rm -rf "$XCFRAMEWORK"
xcodebuild -create-xcframework \
    -library "${DIST_DIR}/lib/libgit2.a" \
    -headers "$HEADERS_DIR" \
    -output "$XCFRAMEWORK"

rm -rf "$HEADERS_DIR"

# ──────────────────────────────────────────────
# Clean up
# ──────────────────────────────────────────────
rm -rf "${LIBGIT2_SRC}/_build_arm64" "${LIBGIT2_SRC}/_build_x86_64" "$DIST_DIR"

# ──────────────────────────────────────────────
# Verify
# ──────────────────────────────────────────────
if [ ! -d "$XCFRAMEWORK" ]; then
    echo "ERROR: Failed to create ${XCFRAMEWORK}"
    exit 1
fi

FRAMEWORK_SIZE=$(du -sh "$XCFRAMEWORK" | cut -f1)
echo "Clibgit2.xcframework created (${FRAMEWORK_SIZE})"
