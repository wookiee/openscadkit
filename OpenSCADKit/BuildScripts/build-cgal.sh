#!/bin/bash
# Build CGAL for iOS/macOS
#
# CGAL is the Computational Geometry Algorithms Library.
# It's required for minkowski() and hull() operations in OpenSCAD.
# CGAL is mostly header-only but we install headers and CMake config files.
# Depends on GMP, MPFR, and Boost.
#
# Usage: ./build-cgal.sh [platform-arch]
# Example: ./build-cgal.sh ios-arm64
# Without arguments: installs for all platforms

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

DEP_NAME="cgal"
CGAL_VERSION="5.6.1"

# Download CGAL source
download_cgal() {
    local url="https://github.com/CGAL/cgal/releases/download/v${CGAL_VERSION}/CGAL-${CGAL_VERSION}.tar.xz"
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

# Build CGAL for a single platform/arch
build_cgal_platform() {
    local platform=$1
    local arch=$2
    local toolchain=$3
    local sdk=$4

    local build_dir=$(get_build_dir "$DEP_NAME" "$platform" "$arch")
    local install_dir=$(get_install_dir "$platform" "$arch")
    local source_dir="$SOURCES_DIR/$DEP_NAME"
    local toolchain_file=$(get_toolchain_file "$toolchain")

    # Check if already built
    if [ -d "$install_dir/include/CGAL" ]; then
        log_info "CGAL already installed for $platform-$arch"
        return 0
    fi

    # Check dependencies
    if [ ! -f "$install_dir/lib/libgmp.a" ]; then
        log_error "GMP not found for $platform-$arch. Build GMP first."
        exit 1
    fi
    if [ ! -f "$install_dir/lib/libmpfr.a" ]; then
        log_error "MPFR not found for $platform-$arch. Build MPFR first."
        exit 1
    fi

    log_info "Building CGAL for $platform-$arch..."

    ensure_dir "$build_dir"
    ensure_dir "$install_dir"

    cd "$build_dir"

    # Configure with CMake
    # CGAL is mostly header-only, we just need to install headers and CMake configs
    cmake "$source_dir" \
        -DCMAKE_TOOLCHAIN_FILE="$toolchain_file" \
        -DCMAKE_OSX_ARCHITECTURES="$arch" \
        -DCMAKE_INSTALL_PREFIX="$install_dir" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_PREFIX_PATH="$install_dir" \
        -DGMP_INCLUDE_DIR="$install_dir/include" \
        -DGMP_LIBRARIES="$install_dir/lib/libgmp.a" \
        -DMPFR_INCLUDE_DIR="$install_dir/include" \
        -DMPFR_LIBRARIES="$install_dir/lib/libmpfr.a" \
        -DBOOST_ROOT="$install_dir" \
        -DBoost_INCLUDE_DIR="$install_dir/include" \
        -DCGAL_HEADER_ONLY=OFF \
        -DWITH_CGAL_Core=ON \
        -DWITH_CGAL_ImageIO=OFF \
        -DWITH_CGAL_Qt5=OFF \
        -DWITH_CGAL_Qt6=OFF \
        -DWITH_demos=OFF \
        -DWITH_examples=OFF \
        -DWITH_tests=OFF \
        -DBUILD_TESTING=OFF \
        -DBUILD_DOC=OFF

    # Build and install
    cmake --build . --parallel $JOBS
    cmake --install .

    log_success "Built CGAL for $platform-$arch"
}

# Build for all platforms or specific one
build_cgal() {
    download_cgal

    if [ -n "$1" ]; then
        # Build specific platform
        for p in "${PLATFORMS[@]}"; do
            parse_platform "$p"
            if [ "$PLATFORM-$ARCH" == "$1" ]; then
                build_cgal_platform "$PLATFORM" "$ARCH" "$TOOLCHAIN" "$SDK"
                return 0
            fi
        done
        log_error "Unknown platform: $1"
        exit 1
    else
        # Build all platforms
        for p in "${PLATFORMS[@]}"; do
            parse_platform "$p"
            build_cgal_platform "$PLATFORM" "$ARCH" "$TOOLCHAIN" "$SDK"
        done
    fi
}

# Run
build_cgal "$1"
