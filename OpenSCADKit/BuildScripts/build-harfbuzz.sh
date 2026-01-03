#!/bin/bash
# Build HarfBuzz for iOS/macOS
#
# HarfBuzz is a text shaping engine, depends on FreeType
#
# Usage: ./build-harfbuzz.sh [platform-arch]
# Example: ./build-harfbuzz.sh ios-arm64
# Without arguments: builds for all platforms

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

DEP_NAME="harfbuzz"

# Download HarfBuzz source
download_harfbuzz() {
    local url="https://github.com/harfbuzz/harfbuzz/releases/download/${HARFBUZZ_VERSION}/harfbuzz-${HARFBUZZ_VERSION}.tar.xz"

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

# Build HarfBuzz for a single platform/arch
build_harfbuzz_platform() {
    local platform=$1
    local arch=$2
    local toolchain=$3
    local sdk=$4

    local build_dir=$(get_build_dir "$DEP_NAME" "$platform" "$arch")
    local install_dir=$(get_install_dir "$platform" "$arch")
    local source_dir="$SOURCES_DIR/$DEP_NAME"
    local toolchain_file=$(get_toolchain_file "$toolchain")

    # Check if already built
    if [ -f "$install_dir/lib/libharfbuzz.a" ]; then
        log_info "HarfBuzz already built for $platform-$arch"
        return 0
    fi

    # Check FreeType dependency
    if [ ! -f "$install_dir/lib/libfreetype.a" ]; then
        log_error "FreeType not found for $platform-$arch. Build FreeType first."
        exit 1
    fi

    log_info "Building HarfBuzz for $platform-$arch..."

    ensure_dir "$build_dir"

    cd "$build_dir"

    # Configure with CMake
    cmake "$source_dir" \
        -DCMAKE_TOOLCHAIN_FILE="$toolchain_file" \
        -DCMAKE_OSX_ARCHITECTURES="$arch" \
        -DCMAKE_INSTALL_PREFIX="$install_dir" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
        -DCMAKE_PREFIX_PATH="$install_dir" \
        -DBUILD_SHARED_LIBS=OFF \
        -DHB_HAVE_FREETYPE=ON \
        -DHB_HAVE_CORETEXT=OFF \
        -DHB_HAVE_GLIB=OFF \
        -DHB_HAVE_GOBJECT=OFF \
        -DHB_HAVE_ICU=OFF \
        -DHB_BUILD_UTILS=OFF \
        -DHB_BUILD_SUBSET=OFF \
        -DFREETYPE_INCLUDE_DIRS="$install_dir/include/freetype2" \
        -DFREETYPE_LIBRARY="$install_dir/lib/libfreetype.a"

    # Build and install
    cmake --build . --parallel $JOBS
    cmake --install .

    log_success "Built HarfBuzz for $platform-$arch"
}

# Build for all platforms or specific one
build_harfbuzz() {
    download_harfbuzz

    if [ -n "$1" ]; then
        # Build specific platform
        for p in "${PLATFORMS[@]}"; do
            parse_platform "$p"
            if [ "$PLATFORM-$ARCH" == "$1" ]; then
                build_harfbuzz_platform "$PLATFORM" "$ARCH" "$TOOLCHAIN" "$SDK"
                return 0
            fi
        done
        log_error "Unknown platform: $1"
        exit 1
    else
        # Build all platforms
        for p in "${PLATFORMS[@]}"; do
            parse_platform "$p"
            build_harfbuzz_platform "$PLATFORM" "$ARCH" "$TOOLCHAIN" "$SDK"
        done
    fi
}

# Run
build_harfbuzz "$1"
