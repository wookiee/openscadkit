#!/bin/bash
# Build GMP (GNU Multiple Precision Arithmetic Library) for iOS/macOS
#
# GMP is required by CGAL for exact arithmetic operations.
# Uses autotools (configure/make) for building.
#
# Usage: ./build-gmp.sh [platform-arch]
# Example: ./build-gmp.sh ios-arm64
# Without arguments: builds for all platforms

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

DEP_NAME="gmp"
GMP_VERSION="6.3.0"

# Download GMP source
download_gmp() {
    local url="https://ftp.gnu.org/gnu/gmp/gmp-${GMP_VERSION}.tar.xz"
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
# The SDK and flags differentiate the actual target
get_host_triplet() {
    local platform=$1
    local arch=$2

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

# Build GMP for a single platform/arch
build_gmp_platform() {
    local platform=$1
    local arch=$2
    local toolchain=$3
    local sdk=$4

    local build_dir=$(get_build_dir "$DEP_NAME" "$platform" "$arch")
    local install_dir=$(get_install_dir "$platform" "$arch")
    local source_dir="$SOURCES_DIR/$DEP_NAME"

    # Check if already built
    if [ -f "$install_dir/lib/libgmp.a" ]; then
        log_info "GMP already built for $platform-$arch"
        return 0
    fi

    log_info "Building GMP for $platform-$arch..."

    ensure_dir "$build_dir"
    ensure_dir "$install_dir"

    local host_triplet=$(get_host_triplet "$platform" "$arch")
    local sdk_path=$(get_sdk_path "$sdk")
    local deployment_flags=$(get_deployment_flags "$platform" "$arch")

    # Set up cross-compilation environment
    export CC="$(xcrun --sdk $sdk -f clang)"
    export CXX="$(xcrun --sdk $sdk -f clang++)"
    export AR="$(xcrun --sdk $sdk -f ar)"
    export RANLIB="$(xcrun --sdk $sdk -f ranlib)"
    export STRIP="$(xcrun --sdk $sdk -f strip)"

    # Common flags (no bitcode - deprecated in Xcode 14+)
    local common_flags="-arch $arch -isysroot $sdk_path $deployment_flags"

    export CFLAGS="$common_flags"
    export CXXFLAGS="$common_flags"
    export LDFLAGS="$common_flags"

    cd "$build_dir"

    # Configure GMP
    # --disable-assembly is needed for cross-compilation to avoid host-specific optimizations
    "$source_dir/configure" \
        --host="$host_triplet" \
        --prefix="$install_dir" \
        --enable-static \
        --disable-shared \
        --disable-assembly \
        --enable-cxx

    # Build and install
    make -j$JOBS
    make install

    # Clean up .la files (can cause issues with CMake)
    rm -f "$install_dir/lib/"*.la

    log_success "Built GMP for $platform-$arch"
}

# Build for all platforms or specific one
build_gmp() {
    download_gmp

    if [ -n "$1" ]; then
        # Build specific platform
        for p in "${PLATFORMS[@]}"; do
            parse_platform "$p"
            if [ "$PLATFORM-$ARCH" == "$1" ]; then
                build_gmp_platform "$PLATFORM" "$ARCH" "$TOOLCHAIN" "$SDK"
                return 0
            fi
        done
        log_error "Unknown platform: $1"
        exit 1
    else
        # Build all platforms
        for p in "${PLATFORMS[@]}"; do
            parse_platform "$p"
            build_gmp_platform "$PLATFORM" "$ARCH" "$TOOLCHAIN" "$SDK"
        done
    fi
}

# Run
build_gmp "$1"
