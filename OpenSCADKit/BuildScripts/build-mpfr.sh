#!/bin/bash
# Build MPFR (Multiple Precision Floating-Point Reliable Library) for iOS/macOS
#
# MPFR is required by CGAL for exact arithmetic operations.
# Uses autotools (configure/make) for building.
# Depends on GMP.
#
# Usage: ./build-mpfr.sh [platform-arch]
# Example: ./build-mpfr.sh ios-arm64
# Without arguments: builds for all platforms

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

DEP_NAME="mpfr"
MPFR_VERSION="4.2.1"

# Download MPFR source
download_mpfr() {
    local url="https://ftp.gnu.org/gnu/mpfr/mpfr-${MPFR_VERSION}.tar.xz"
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

# Get host triplet for a platform/arch
# Note: For autotools, we use Darwin triplets for all Apple platforms
get_host_triplet() {
    local arch=$1

    case "$arch" in
        arm64)
            echo "aarch64-apple-darwin"
            ;;
        x86_64)
            echo "x86_64-apple-darwin"
            ;;
        *)
            log_error "Unknown arch: $arch"
            exit 1
            ;;
    esac
}

# Get SDK path for a platform
get_sdk_path() {
    local sdk=$1
    xcrun --sdk "$sdk" --show-sdk-path
}

# Get deployment target flags
get_deployment_flags() {
    local platform=$1
    local arch=$2
    case "$platform" in
        ios)
            echo "-miphoneos-version-min=$IOS_DEPLOYMENT_TARGET"
            ;;
        ios-simulator)
            echo "-mios-simulator-version-min=$IOS_DEPLOYMENT_TARGET"
            ;;
        macos)
            echo "-mmacosx-version-min=$MACOS_DEPLOYMENT_TARGET"
            ;;
        xros)
            echo "-target ${arch}-apple-xros${XROS_DEPLOYMENT_TARGET}"
            ;;
        xros-simulator)
            echo "-target ${arch}-apple-xros${XROS_DEPLOYMENT_TARGET}-simulator"
            ;;
    esac
}

# Build MPFR for a single platform/arch
build_mpfr_platform() {
    local platform=$1
    local arch=$2
    local toolchain=$3
    local sdk=$4

    local build_dir=$(get_build_dir "$DEP_NAME" "$platform" "$arch")
    local install_dir=$(get_install_dir "$platform" "$arch")
    local source_dir="$SOURCES_DIR/$DEP_NAME"

    # Check if already built
    if [ -f "$install_dir/lib/libmpfr.a" ]; then
        log_info "MPFR already built for $platform-$arch"
        return 0
    fi

    # Check for GMP dependency
    if [ ! -f "$install_dir/lib/libgmp.a" ]; then
        log_error "GMP not found for $platform-$arch. Build GMP first."
        exit 1
    fi

    log_info "Building MPFR for $platform-$arch..."

    ensure_dir "$build_dir"
    ensure_dir "$install_dir"

    local host_triplet=$(get_host_triplet "$arch")
    local sdk_path=$(get_sdk_path "$sdk")
    local deployment_flags=$(get_deployment_flags "$platform" "$arch")

    # Set up cross-compilation environment
    export CC="$(xcrun --sdk $sdk -f clang)"
    export CXX="$(xcrun --sdk $sdk -f clang++)"
    export AR="$(xcrun --sdk $sdk -f ar)"
    export RANLIB="$(xcrun --sdk $sdk -f ranlib)"
    export STRIP="$(xcrun --sdk $sdk -f strip)"

    # Common flags
    local common_flags="-arch $arch -isysroot $sdk_path $deployment_flags"

    export CFLAGS="$common_flags -I$install_dir/include"
    export CXXFLAGS="$common_flags -I$install_dir/include"
    export LDFLAGS="$common_flags -L$install_dir/lib"

    cd "$build_dir"

    # Configure MPFR
    "$source_dir/configure" \
        --host="$host_triplet" \
        --prefix="$install_dir" \
        --enable-static \
        --disable-shared \
        --with-gmp="$install_dir"

    # Build and install
    make -j$JOBS
    make install

    # Clean up .la files (can cause issues with CMake)
    rm -f "$install_dir/lib/"*.la

    log_success "Built MPFR for $platform-$arch"
}

# Build for all platforms or specific one
build_mpfr() {
    download_mpfr

    if [ -n "$1" ]; then
        # Build specific platform
        for p in "${PLATFORMS[@]}"; do
            parse_platform "$p"
            if [ "$PLATFORM-$ARCH" == "$1" ]; then
                build_mpfr_platform "$PLATFORM" "$ARCH" "$TOOLCHAIN" "$SDK"
                return 0
            fi
        done
        log_error "Unknown platform: $1"
        exit 1
    else
        # Build all platforms
        for p in "${PLATFORMS[@]}"; do
            parse_platform "$p"
            build_mpfr_platform "$PLATFORM" "$ARCH" "$TOOLCHAIN" "$SDK"
        done
    fi
}

# Run
build_mpfr "$1"
