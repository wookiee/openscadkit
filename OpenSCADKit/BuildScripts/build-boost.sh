#!/bin/bash
# Build Boost for iOS/macOS
#
# Boost is mostly header-only, but we need compiled libraries for:
# - filesystem
# - program_options
# - regex
#
# Usage: ./build-boost.sh [platform-arch]
# Example: ./build-boost.sh ios-arm64
# Without arguments: builds for all platforms

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

DEP_NAME="boost"

# Download Boost source
download_boost() {
    local version_underscore="${BOOST_VERSION//./_}"
    local url="https://archives.boost.io/release/${BOOST_VERSION}/source/boost_${version_underscore}.tar.gz"
    download_source "$DEP_NAME" "$url"
}

# Build Boost for a single platform/arch
build_boost_platform() {
    local platform=$1
    local arch=$2
    local toolchain=$3
    local sdk=$4

    local build_dir=$(get_build_dir "$DEP_NAME" "$platform" "$arch")
    local install_dir=$(get_install_dir "$platform" "$arch")
    local source_dir="$SOURCES_DIR/$DEP_NAME"

    # Check if already built
    if [ -f "$install_dir/lib/libboost_filesystem.a" ]; then
        log_info "Boost already built for $platform-$arch"
        return 0
    fi

    log_info "Building Boost for $platform-$arch..."

    ensure_dir "$build_dir"
    ensure_dir "$install_dir"

    cd "$source_dir"

    # Bootstrap if needed
    if [ ! -f "b2" ]; then
        log_info "Bootstrapping Boost..."
        ./bootstrap.sh --with-libraries=filesystem,program_options,regex --prefix="$install_dir"
    fi

    # Determine toolset and target
    local toolset="clang"
    local target_os=""
    local cxxflags=""
    local linkflags=""

    # Get SDK path
    local sdk_path=$(xcrun --sdk "$sdk" --show-sdk-path)
    local cc=$(xcrun --sdk "$sdk" --find clang)
    local cxx=$(xcrun --sdk "$sdk" --find clang++)

    case "$platform" in
        ios)
            target_os="iphone"
            cxxflags="-arch $arch -isysroot $sdk_path -miphoneos-version-min=$IOS_DEPLOYMENT_TARGET -fembed-bitcode-marker"
            linkflags="-arch $arch -isysroot $sdk_path"
            ;;
        ios-simulator)
            target_os="iphone"
            cxxflags="-arch $arch -isysroot $sdk_path -mios-simulator-version-min=$IOS_DEPLOYMENT_TARGET"
            linkflags="-arch $arch -isysroot $sdk_path"
            ;;
        macos)
            target_os="darwin"
            cxxflags="-arch $arch -isysroot $sdk_path -mmacosx-version-min=$MACOS_DEPLOYMENT_TARGET"
            linkflags="-arch $arch -isysroot $sdk_path"
            ;;
        xros)
            target_os="darwin"
            cxxflags="-arch $arch -isysroot $sdk_path -target arm64-apple-xros$XROS_DEPLOYMENT_TARGET"
            linkflags="-arch $arch -isysroot $sdk_path"
            ;;
        xros-simulator)
            target_os="darwin"
            cxxflags="-arch $arch -isysroot $sdk_path -target arm64-apple-xros$XROS_DEPLOYMENT_TARGET-simulator"
            linkflags="-arch $arch -isysroot $sdk_path"
            ;;
    esac

    # Create user-config.jam
    cat > "$build_dir/user-config.jam" << EOF
using clang : ios
    : $cxx
    : <cxxflags>"$cxxflags -std=c++17"
      <linkflags>"$linkflags"
    ;
EOF

    # Build
    ./b2 \
        --build-dir="$build_dir" \
        --prefix="$install_dir" \
        --user-config="$build_dir/user-config.jam" \
        --with-filesystem \
        --with-program_options \
        --with-regex \
        toolset=clang-ios \
        target-os=$target_os \
        architecture=arm \
        address-model=64 \
        link=static \
        runtime-link=static \
        threading=multi \
        variant=release \
        -j$JOBS \
        install

    log_success "Built Boost for $platform-$arch"
}

# Build for all platforms or specific one
build_boost() {
    download_boost

    if [ -n "$1" ]; then
        # Build specific platform
        for p in "${PLATFORMS[@]}"; do
            parse_platform "$p"
            if [ "$PLATFORM-$ARCH" == "$1" ]; then
                build_boost_platform "$PLATFORM" "$ARCH" "$TOOLCHAIN" "$SDK"
                return 0
            fi
        done
        log_error "Unknown platform: $1"
        exit 1
    else
        # Build all platforms
        for p in "${PLATFORMS[@]}"; do
            parse_platform "$p"
            build_boost_platform "$PLATFORM" "$ARCH" "$TOOLCHAIN" "$SDK"
        done
    fi
}

# Run
build_boost "$1"
