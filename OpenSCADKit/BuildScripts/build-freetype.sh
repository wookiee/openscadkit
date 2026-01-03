#!/bin/bash
# Build FreeType for iOS/macOS
#
# FreeType is a font rendering library required by HarfBuzz and OpenSCAD
#
# Usage: ./build-freetype.sh [platform-arch]
# Example: ./build-freetype.sh ios-arm64
# Without arguments: builds for all platforms

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

DEP_NAME="freetype"

# Download FreeType source
download_freetype() {
    local url="https://download.savannah.gnu.org/releases/freetype/freetype-${FREETYPE_VERSION}.tar.gz"
    download_source "$DEP_NAME" "$url"
}

# Build FreeType for a single platform/arch
build_freetype_platform() {
    local platform=$1
    local arch=$2
    local toolchain=$3
    local sdk=$4

    local build_dir=$(get_build_dir "$DEP_NAME" "$platform" "$arch")
    local install_dir=$(get_install_dir "$platform" "$arch")
    local source_dir="$SOURCES_DIR/$DEP_NAME"
    local toolchain_file=$(get_toolchain_file "$toolchain")

    # Check if already built
    if [ -f "$install_dir/lib/libfreetype.a" ]; then
        log_info "FreeType already built for $platform-$arch"
        return 0
    fi

    log_info "Building FreeType for $platform-$arch..."

    ensure_dir "$build_dir"
    ensure_dir "$install_dir"

    cd "$build_dir"

    # Configure with CMake
    cmake "$source_dir" \
        -DCMAKE_TOOLCHAIN_FILE="$toolchain_file" \
        -DCMAKE_OSX_ARCHITECTURES="$arch" \
        -DCMAKE_INSTALL_PREFIX="$install_dir" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
        -DBUILD_SHARED_LIBS=OFF \
        -DFT_DISABLE_ZLIB=ON \
        -DFT_DISABLE_BZIP2=ON \
        -DFT_DISABLE_PNG=ON \
        -DFT_DISABLE_HARFBUZZ=ON \
        -DFT_DISABLE_BROTLI=ON

    # Build and install
    cmake --build . --parallel $JOBS
    cmake --install .

    log_success "Built FreeType for $platform-$arch"
}

# Build for all platforms or specific one
build_freetype() {
    download_freetype

    if [ -n "$1" ]; then
        # Build specific platform
        for p in "${PLATFORMS[@]}"; do
            parse_platform "$p"
            if [ "$PLATFORM-$ARCH" == "$1" ]; then
                build_freetype_platform "$PLATFORM" "$ARCH" "$TOOLCHAIN" "$SDK"
                return 0
            fi
        done
        log_error "Unknown platform: $1"
        exit 1
    else
        # Build all platforms
        for p in "${PLATFORMS[@]}"; do
            parse_platform "$p"
            build_freetype_platform "$PLATFORM" "$ARCH" "$TOOLCHAIN" "$SDK"
        done
    fi
}

# Run
build_freetype "$1"
