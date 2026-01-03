#!/bin/bash
# Build FontConfig for iOS/macOS
#
# FontConfig is a library for configuring and customizing font access.
# Required by OpenSCAD for text() functionality.
# Uses Meson for building. Depends on FreeType and expat.
#
# Usage: ./build-fontconfig.sh [platform-arch]
# Example: ./build-fontconfig.sh ios-arm64
# Without arguments: builds for all platforms

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

DEP_NAME="fontconfig"
FONTCONFIG_VERSION="2.15.0"

# Check for meson - also check common pip install locations
check_meson() {
    # Add common pip install locations to PATH
    export PATH="$HOME/.local/bin:$PATH"

    if ! command -v meson &> /dev/null; then
        log_error "meson is required but not installed. Install with: pip3 install meson ninja"
        exit 1
    fi
    if ! command -v ninja &> /dev/null; then
        log_error "ninja is required but not installed. Install with: pip3 install ninja"
        exit 1
    fi
}

# Download fontconfig source
download_fontconfig() {
    local url="https://www.freedesktop.org/software/fontconfig/release/fontconfig-${FONTCONFIG_VERSION}.tar.xz"
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

# Get SDK path for a platform
get_sdk_path() {
    local sdk=$1
    xcrun --sdk "$sdk" --show-sdk-path
}

# Get deployment target flag
get_deployment_flag() {
    local platform=$1
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
            echo "-target arm64-apple-xros$XROS_DEPLOYMENT_TARGET"
            ;;
        xros-simulator)
            echo "-target arm64-apple-xros$XROS_DEPLOYMENT_TARGET-simulator"
            ;;
    esac
}

# Get system name for meson
get_meson_system() {
    local platform=$1
    case "$platform" in
        ios|ios-simulator)
            echo "ios"
            ;;
        macos)
            echo "darwin"
            ;;
        xros|xros-simulator)
            echo "ios"  # Treat visionOS as iOS for meson
            ;;
    esac
}

# Get CPU family for meson
get_meson_cpu_family() {
    local arch=$1
    case "$arch" in
        arm64)
            echo "aarch64"
            ;;
        x86_64)
            echo "x86_64"
            ;;
    esac
}

# Build fontconfig for a single platform/arch
build_fontconfig_platform() {
    local platform=$1
    local arch=$2
    local toolchain=$3
    local sdk=$4

    local build_dir=$(get_build_dir "$DEP_NAME" "$platform" "$arch")
    local install_dir=$(get_install_dir "$platform" "$arch")
    local source_dir="$SOURCES_DIR/$DEP_NAME"

    # Check if already built
    if [ -f "$install_dir/lib/libfontconfig.a" ]; then
        log_info "fontconfig already built for $platform-$arch"
        return 0
    fi

    # Check dependencies
    if [ ! -f "$install_dir/lib/libfreetype.a" ]; then
        log_error "FreeType not found for $platform-$arch. Build FreeType first."
        exit 1
    fi
    if [ ! -f "$install_dir/lib/libexpat.a" ]; then
        log_error "expat not found for $platform-$arch. Build expat first."
        exit 1
    fi

    log_info "Building fontconfig for $platform-$arch..."

    ensure_dir "$build_dir"
    ensure_dir "$install_dir"

    local sdk_path=$(get_sdk_path "$sdk")
    local deployment_flag=$(get_deployment_flag "$platform")
    local meson_system=$(get_meson_system "$platform")
    local meson_cpu_family=$(get_meson_cpu_family "$arch")

    # Get the compiler from SDK
    local cc="$(xcrun --sdk $sdk -f clang)"
    local cxx="$(xcrun --sdk $sdk -f clang++)"
    local ar="$(xcrun --sdk $sdk -f ar)"

    # Common flags
    local common_flags="-arch $arch -isysroot $sdk_path $deployment_flag"

    # Create meson cross file
    # For visionOS, we need to use ld64 as linker and remove the -target from link args
    local cross_file="$build_dir/cross.ini"

    # Get ld path
    local ld="$(xcrun --sdk $sdk -f ld)"

    # For visionOS, handle the -target flag separately (needs to be two args: -target and the triple)
    local c_compile_args="'-arch', '$arch', '-isysroot', '$sdk_path'"
    local c_link_extra=""
    if [[ "$platform" == xros* ]]; then
        # For visionOS, use -target as separate args and only for compile, not link
        local target_triple
        if [[ "$platform" == "xros-simulator" ]]; then
            target_triple="arm64-apple-xros${XROS_DEPLOYMENT_TARGET}-simulator"
        else
            target_triple="arm64-apple-xros${XROS_DEPLOYMENT_TARGET}"
        fi
        c_compile_args="$c_compile_args, '-target', '$target_triple'"
        c_link_extra="'-arch', '$arch', '-isysroot', '$sdk_path'"
    else
        c_compile_args="$c_compile_args, '$deployment_flag'"
        c_link_extra="'-arch', '$arch', '-isysroot', '$sdk_path', '$deployment_flag'"
    fi

    cat > "$cross_file" << EOF
[binaries]
c = '$cc'
cpp = '$cxx'
ar = '$ar'
strip = '$(xcrun --sdk $sdk -f strip)'
pkg-config = 'pkg-config'

[built-in options]
c_args = [$c_compile_args, '-I$install_dir/include', '-I$install_dir/include/freetype2']
c_link_args = [$c_link_extra, '-L$install_dir/lib']
cpp_args = [$c_compile_args, '-I$install_dir/include', '-I$install_dir/include/freetype2']
cpp_link_args = [$c_link_extra, '-L$install_dir/lib']

[host_machine]
system = '$meson_system'
cpu_family = '$meson_cpu_family'
cpu = '$arch'
endian = 'little'

[properties]
needs_exe_wrapper = true
pkg_config_libdir = '$install_dir/lib/pkgconfig'
EOF

    # Clean previous build
    rm -rf "$build_dir/meson"

    cd "$source_dir"

    # Run meson setup
    # Note: We set custom cache/config dirs since we're cross-compiling and these aren't needed
    PKG_CONFIG_PATH="$install_dir/lib/pkgconfig" \
    FREETYPE_CFLAGS="-I$install_dir/include/freetype2 -I$install_dir/include" \
    FREETYPE_LIBS="-L$install_dir/lib -lfreetype -lpng -lz -lbz2" \
    meson setup "$build_dir/meson" \
        --cross-file="$cross_file" \
        --prefix="$install_dir" \
        --default-library=static \
        --buildtype=release \
        -Ddoc=disabled \
        -Dtests=disabled \
        -Dtools=disabled \
        -Dcache-build=disabled \
        -Dnls=disabled

    # Build and install
    ninja -C "$build_dir/meson" -j$JOBS
    ninja -C "$build_dir/meson" install

    log_success "Built fontconfig for $platform-$arch"
}

# Build for all platforms or specific one
build_fontconfig() {
    check_meson
    download_fontconfig

    if [ -n "$1" ]; then
        # Build specific platform
        for p in "${PLATFORMS[@]}"; do
            parse_platform "$p"
            if [ "$PLATFORM-$ARCH" == "$1" ]; then
                build_fontconfig_platform "$PLATFORM" "$ARCH" "$TOOLCHAIN" "$SDK"
                return 0
            fi
        done
        log_error "Unknown platform: $1"
        exit 1
    else
        # Build all platforms
        for p in "${PLATFORMS[@]}"; do
            parse_platform "$p"
            build_fontconfig_platform "$PLATFORM" "$ARCH" "$TOOLCHAIN" "$SDK"
        done
    fi
}

# Run
build_fontconfig "$1"
