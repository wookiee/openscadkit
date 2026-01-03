#!/bin/bash
# Build libffi for iOS/macOS
#
# libffi is a portable foreign function interface library.
# Required by GLib2 for dynamic function calls.
# Uses autotools (configure/make) for building.
#
# Usage: ./build-libffi.sh [platform-arch]
# Example: ./build-libffi.sh ios-arm64
# Without arguments: builds for all platforms

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

DEP_NAME="libffi"
LIBFFI_VERSION="3.4.6"

# Download libffi source
download_libffi() {
    local url="https://github.com/libffi/libffi/releases/download/v${LIBFFI_VERSION}/libffi-${LIBFFI_VERSION}.tar.gz"
    download_source "$DEP_NAME" "$url"
}

# Get host triplet for a platform/arch
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

# Build libffi for a single platform/arch
build_libffi_platform() {
    local platform=$1
    local arch=$2
    local toolchain=$3
    local sdk=$4

    local build_dir=$(get_build_dir "$DEP_NAME" "$platform" "$arch")
    local install_dir=$(get_install_dir "$platform" "$arch")
    local source_dir="$SOURCES_DIR/$DEP_NAME"

    # Check if already built
    if [ -f "$install_dir/lib/libffi.a" ]; then
        log_info "libffi already built for $platform-$arch"
        return 0
    fi

    log_info "Building libffi for $platform-$arch..."

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
    # -fno-asynchronous-unwind-tables disables CFI generation which causes issues with libffi's assembly
    local common_flags="-arch $arch -isysroot $sdk_path $deployment_flags -fno-asynchronous-unwind-tables"

    export CFLAGS="$common_flags"
    export CXXFLAGS="$common_flags"
    export LDFLAGS="$common_flags"

    # Clean previous failed build if exists
    rm -rf "$build_dir"/*

    cd "$build_dir"

    # Configure libffi
    # Note: libffi's configure doesn't have --disable-assembly like GMP
    # We rely on the configure script to detect the platform and use appropriate code paths
    "$source_dir/configure" \
        --host="$host_triplet" \
        --prefix="$install_dir" \
        --enable-static \
        --disable-shared \
        --disable-docs \
        --disable-multi-os-directory

    # Build and install
    make -j$JOBS
    make install

    # Clean up .la files
    rm -f "$install_dir/lib/"*.la

    log_success "Built libffi for $platform-$arch"
}

# Build for all platforms or specific one
build_libffi() {
    download_libffi

    if [ -n "$1" ]; then
        # Build specific platform
        for p in "${PLATFORMS[@]}"; do
            parse_platform "$p"
            if [ "$PLATFORM-$ARCH" == "$1" ]; then
                build_libffi_platform "$PLATFORM" "$ARCH" "$TOOLCHAIN" "$SDK"
                return 0
            fi
        done
        log_error "Unknown platform: $1"
        exit 1
    else
        # Build all platforms
        for p in "${PLATFORMS[@]}"; do
            parse_platform "$p"
            build_libffi_platform "$PLATFORM" "$ARCH" "$TOOLCHAIN" "$SDK"
        done
    fi
}

# Run
build_libffi "$1"
