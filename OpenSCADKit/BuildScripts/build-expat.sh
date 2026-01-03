#!/bin/bash
# Build expat for iOS/macOS
#
# Expat is an XML parser library.
# Required by FontConfig for reading configuration files.
# Uses CMake for building.
#
# Usage: ./build-expat.sh [platform-arch]
# Example: ./build-expat.sh ios-arm64
# Without arguments: builds for all platforms

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

DEP_NAME="expat"
EXPAT_VERSION="2.6.2"

# Download expat source
download_expat() {
    local url="https://github.com/libexpat/libexpat/releases/download/R_${EXPAT_VERSION//./_}/expat-${EXPAT_VERSION}.tar.xz"
    local dest="$SOURCES_DIR/$DEP_NAME"

    if [ -d "$dest" ]; then
        log_info "Source $DEP_NAME already exists"
        return 0
    fi

    ensure_dir "$SOURCES_DIR"
    log_info "Downloading $DEP_NAME..."

    local archive="$SOURCES_DIR/${DEP_NAME}.tar.xz"
    curl -L "$url" -o "$archive"

    log_info "Extracting $DEP_NAME..."
    mkdir -p "$dest"
    tar -xJf "$archive" -C "$dest" --strip-components=1
    rm "$archive"

    log_success "Downloaded and extracted $DEP_NAME"
}

# Build expat for a single platform/arch
build_expat_platform() {
    local platform=$1
    local arch=$2
    local toolchain=$3
    local sdk=$4

    local build_dir=$(get_build_dir "$DEP_NAME" "$platform" "$arch")
    local install_dir=$(get_install_dir "$platform" "$arch")
    local source_dir="$SOURCES_DIR/$DEP_NAME"
    local toolchain_file=$(get_toolchain_file "$toolchain")

    # Check if already built
    if [ -f "$install_dir/lib/libexpat.a" ]; then
        log_info "expat already built for $platform-$arch"
        return 0
    fi

    log_info "Building expat for $platform-$arch..."

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
        -DEXPAT_BUILD_TOOLS=OFF \
        -DEXPAT_BUILD_EXAMPLES=OFF \
        -DEXPAT_BUILD_TESTS=OFF \
        -DEXPAT_BUILD_DOCS=OFF \
        -DEXPAT_SHARED_LIBS=OFF

    # Build and install
    cmake --build . --parallel $JOBS
    cmake --install .

    log_success "Built expat for $platform-$arch"
}

# Build for all platforms or specific one
build_expat() {
    download_expat

    if [ -n "$1" ]; then
        # Build specific platform
        for p in "${PLATFORMS[@]}"; do
            parse_platform "$p"
            if [ "$PLATFORM-$ARCH" == "$1" ]; then
                build_expat_platform "$PLATFORM" "$ARCH" "$TOOLCHAIN" "$SDK"
                return 0
            fi
        done
        log_error "Unknown platform: $1"
        exit 1
    else
        # Build all platforms
        for p in "${PLATFORMS[@]}"; do
            parse_platform "$p"
            build_expat_platform "$PLATFORM" "$ARCH" "$TOOLCHAIN" "$SDK"
        done
    fi
}

# Run
build_expat "$1"
