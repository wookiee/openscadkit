#!/bin/bash
# Build libzip for iOS/macOS
#
# libzip is a library for reading, creating, and modifying zip archives.
# Required by OpenSCAD for loading files from archives.
# Uses CMake for building. Depends on zlib (available in iOS/macOS SDK).
#
# Usage: ./build-libzip.sh [platform-arch]
# Example: ./build-libzip.sh ios-arm64
# Without arguments: builds for all platforms

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

DEP_NAME="libzip"
LIBZIP_VERSION="1.10.1"

# Download libzip source
download_libzip() {
    local url="https://github.com/nih-at/libzip/releases/download/v${LIBZIP_VERSION}/libzip-${LIBZIP_VERSION}.tar.xz"
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

# Build libzip for a single platform/arch
build_libzip_platform() {
    local platform=$1
    local arch=$2
    local toolchain=$3
    local sdk=$4

    local build_dir=$(get_build_dir "$DEP_NAME" "$platform" "$arch")
    local install_dir=$(get_install_dir "$platform" "$arch")
    local source_dir="$SOURCES_DIR/$DEP_NAME"
    local toolchain_file=$(get_toolchain_file "$toolchain")

    # Check if already built
    if [ -f "$install_dir/lib/libzip.a" ]; then
        log_info "libzip already built for $platform-$arch"
        return 0
    fi

    log_info "Building libzip for $platform-$arch..."

    ensure_dir "$build_dir"
    ensure_dir "$install_dir"

    cd "$build_dir"

    # Configure with CMake
    # libzip uses zlib from the SDK
    # Disable C11 Annex K functions (_s variants) which aren't available on Apple platforms
    cmake "$source_dir" \
        -DCMAKE_TOOLCHAIN_FILE="$toolchain_file" \
        -DCMAKE_OSX_ARCHITECTURES="$arch" \
        -DCMAKE_INSTALL_PREFIX="$install_dir" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
        -DBUILD_SHARED_LIBS=OFF \
        -DBUILD_TOOLS=OFF \
        -DBUILD_REGRESS=OFF \
        -DBUILD_EXAMPLES=OFF \
        -DBUILD_DOC=OFF \
        -DENABLE_COMMONCRYPTO=ON \
        -DENABLE_GNUTLS=OFF \
        -DENABLE_MBEDTLS=OFF \
        -DENABLE_OPENSSL=OFF \
        -DENABLE_WINDOWS_CRYPTO=OFF \
        -DENABLE_BZIP2=OFF \
        -DENABLE_LZMA=OFF \
        -DENABLE_ZSTD=OFF \
        -DHAVE_STRERRORLEN_S=OFF \
        -DHAVE_STRERROR_S=OFF \
        -DHAVE_MEMCPY_S=OFF \
        -DHAVE_STRNCPY_S=OFF

    # Build and install
    cmake --build . --parallel $JOBS
    cmake --install .

    log_success "Built libzip for $platform-$arch"
}

# Build for all platforms or specific one
build_libzip() {
    download_libzip

    if [ -n "$1" ]; then
        # Build specific platform
        for p in "${PLATFORMS[@]}"; do
            parse_platform "$p"
            if [ "$PLATFORM-$ARCH" == "$1" ]; then
                build_libzip_platform "$PLATFORM" "$ARCH" "$TOOLCHAIN" "$SDK"
                return 0
            fi
        done
        log_error "Unknown platform: $1"
        exit 1
    else
        # Build all platforms
        for p in "${PLATFORMS[@]}"; do
            parse_platform "$p"
            build_libzip_platform "$PLATFORM" "$ARCH" "$TOOLCHAIN" "$SDK"
        done
    fi
}

# Run
build_libzip "$1"
