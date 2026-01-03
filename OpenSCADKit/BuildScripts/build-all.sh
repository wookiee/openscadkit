#!/bin/bash
# Build all dependencies for all platforms
#
# This is the master build script that builds all dependencies in order
#
# Usage: ./build-all.sh [platform-arch]
# Example: ./build-all.sh ios-arm64
# Without arguments: builds for all platforms

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

log_info "=========================================="
log_info "OpenSCADKit Dependency Build"
log_info "=========================================="

PLATFORM_ARG="$1"

# Build order (dependencies first)
DEPS=(
    "double-conversion"
    "boost"
    "freetype"
    "harfbuzz"
    "manifold"
)

for dep in "${DEPS[@]}"; do
    log_info "=========================================="
    log_info "Building $dep..."
    log_info "=========================================="

    "$SCRIPT_DIR/build-${dep}.sh" $PLATFORM_ARG

    log_success "Completed $dep"
done

log_info "=========================================="
log_success "All dependencies built successfully!"
log_info "=========================================="

# Summary
log_info ""
log_info "Install locations:"
for p in "${PLATFORMS[@]}"; do
    parse_platform "$p"
    if [ -z "$PLATFORM_ARG" ] || [ "$PLATFORM-$ARCH" == "$PLATFORM_ARG" ]; then
        install_dir=$(get_install_dir "$PLATFORM" "$ARCH")
        log_info "  $PLATFORM-$ARCH: $install_dir"
    fi
done

log_info ""
log_info "Next step: Run ./build-openscad.sh to build the OpenSCAD library"
