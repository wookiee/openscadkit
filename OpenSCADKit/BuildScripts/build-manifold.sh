#!/bin/bash
# Build Manifold for iOS/macOS
#
# Manifold is a high-performance geometry kernel used by OpenSCAD
# It includes Clipper2 as a dependency (fetched automatically by CMake)
#
# Usage: ./build-manifold.sh [platform-arch]
# Example: ./build-manifold.sh ios-arm64
# Without arguments: builds for all platforms

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

DEP_NAME="manifold"

# Clone Manifold source
download_manifold() {
    local dest="$SOURCES_DIR/$DEP_NAME"
    clone_repo "$DEP_NAME" "https://github.com/elalish/manifold.git" "v${MANIFOLD_VERSION}"

    # Initialize submodules (quickhull is required)
    if [ -d "$dest" ]; then
        log_info "Initializing Manifold submodules..."
        cd "$dest"
        git submodule update --init --recursive
        cd - > /dev/null
    fi
}

# Build Manifold for a single platform/arch
build_manifold_platform() {
    local platform=$1
    local arch=$2
    local toolchain=$3
    local sdk=$4

    local build_dir=$(get_build_dir "$DEP_NAME" "$platform" "$arch")
    local install_dir=$(get_install_dir "$platform" "$arch")
    local source_dir="$SOURCES_DIR/$DEP_NAME"
    local toolchain_file=$(get_toolchain_file "$toolchain")

    # Check if already built
    if [ -f "$install_dir/lib/libmanifold.a" ]; then
        log_info "Manifold already built for $platform-$arch"
        return 0
    fi

    log_info "Building Manifold for $platform-$arch..."

    ensure_dir "$build_dir"
    ensure_dir "$install_dir"

    cd "$build_dir"

    # Configure with CMake
    # Manifold fetches Clipper2 automatically via FetchContent
    cmake "$source_dir" \
        -DCMAKE_TOOLCHAIN_FILE="$toolchain_file" \
        -DCMAKE_OSX_ARCHITECTURES="$arch" \
        -DCMAKE_INSTALL_PREFIX="$install_dir" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
        -DBUILD_SHARED_LIBS=OFF \
        -DMANIFOLD_TEST=OFF \
        -DMANIFOLD_CROSS_SECTION=ON \
        -DMANIFOLD_EXPORT=OFF \
        -DMANIFOLD_CBIND=OFF \
        -DMANIFOLD_PYBIND=OFF \
        -DMANIFOLD_JSBIND=OFF \
        -DMANIFOLD_PAR=OFF \
        -DCMAKE_DISABLE_FIND_PACKAGE_TBB=ON

    # Build and install
    cmake --build . --parallel $JOBS
    cmake --install .

    # Patch manifold config to always find TBB (even when PAR=NONE) for target validation
    # The generator expression in manifoldTargets.cmake references TBB::tbb even when disabled
    local manifold_config="$install_dir/lib/cmake/manifold/manifoldConfig.cmake"
    if [ -f "$manifold_config" ]; then
        if ! grep -q "find_package(TBB QUIET)" "$manifold_config"; then
            sed -i '' 's/include("${CMAKE_CURRENT_LIST_DIR}\/manifoldTargets.cmake")/find_package(TBB QUIET)\ninclude("${CMAKE_CURRENT_LIST_DIR}\/manifoldTargets.cmake")/' "$manifold_config"
        fi
    fi

    log_success "Built Manifold for $platform-$arch"
}

# Build for all platforms or specific one
build_manifold() {
    download_manifold

    if [ -n "$1" ]; then
        # Build specific platform
        for p in "${PLATFORMS[@]}"; do
            parse_platform "$p"
            if [ "$PLATFORM-$ARCH" == "$1" ]; then
                build_manifold_platform "$PLATFORM" "$ARCH" "$TOOLCHAIN" "$SDK"
                return 0
            fi
        done
        log_error "Unknown platform: $1"
        exit 1
    else
        # Build all platforms
        for p in "${PLATFORMS[@]}"; do
            parse_platform "$p"
            build_manifold_platform "$PLATFORM" "$ARCH" "$TOOLCHAIN" "$SDK"
        done
    fi
}

# Run
build_manifold "$1"
