#!/bin/bash
# Build Eigen3 for iOS/macOS
#
# Eigen is a header-only C++ template library for linear algebra.
# No compilation needed - just install headers.
#
# Usage: ./build-eigen.sh [platform-arch]
# Example: ./build-eigen.sh ios-arm64
# Without arguments: installs for all platforms

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

DEP_NAME="eigen"
EIGEN_VERSION="3.4.0"

# Download Eigen source
download_eigen() {
    local url="https://gitlab.com/libeigen/eigen/-/archive/${EIGEN_VERSION}/eigen-${EIGEN_VERSION}.tar.gz"
    download_source "$DEP_NAME" "$url"
}

# Install Eigen headers for a single platform/arch
install_eigen_platform() {
    local platform=$1
    local arch=$2

    local install_dir=$(get_install_dir "$platform" "$arch")
    local source_dir="$SOURCES_DIR/$DEP_NAME"

    # Check if already installed
    if [ -d "$install_dir/include/eigen3/Eigen" ]; then
        log_info "Eigen already installed for $platform-$arch"
        return 0
    fi

    log_info "Installing Eigen headers for $platform-$arch..."

    ensure_dir "$install_dir/include/eigen3"

    # Copy Eigen headers (header-only library)
    cp -R "$source_dir/Eigen" "$install_dir/include/eigen3/"
    cp -R "$source_dir/unsupported" "$install_dir/include/eigen3/"

    # Create a CMake config file for find_package(Eigen3)
    ensure_dir "$install_dir/share/eigen3/cmake"
    cat > "$install_dir/share/eigen3/cmake/Eigen3Config.cmake" << 'EOF'
# Eigen3 CMake configuration file
set(EIGEN3_FOUND TRUE)
set(EIGEN3_VERSION "3.4.0")
set(EIGEN3_INCLUDE_DIR "${CMAKE_CURRENT_LIST_DIR}/../../../include/eigen3")
set(EIGEN3_INCLUDE_DIRS "${EIGEN3_INCLUDE_DIR}")

if(NOT TARGET Eigen3::Eigen)
    add_library(Eigen3::Eigen INTERFACE IMPORTED)
    set_target_properties(Eigen3::Eigen PROPERTIES
        INTERFACE_INCLUDE_DIRECTORIES "${EIGEN3_INCLUDE_DIR}"
    )
endif()
EOF

    log_success "Installed Eigen for $platform-$arch"
}

# Install for all platforms or specific one
install_eigen() {
    download_eigen

    if [ -n "$1" ]; then
        # Install for specific platform
        for p in "${PLATFORMS[@]}"; do
            parse_platform "$p"
            if [ "$PLATFORM-$ARCH" == "$1" ]; then
                install_eigen_platform "$PLATFORM" "$ARCH"
                return 0
            fi
        done
        log_error "Unknown platform: $1"
        exit 1
    else
        # Install for all platforms
        for p in "${PLATFORMS[@]}"; do
            parse_platform "$p"
            install_eigen_platform "$PLATFORM" "$ARCH"
        done
    fi
}

# Run
install_eigen "$1"
