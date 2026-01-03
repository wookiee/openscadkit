#!/bin/bash
# Common configuration for all build scripts

set -e

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPENSCADKIT_DIR="$(dirname "$SCRIPT_DIR")"
REPO_ROOT="$(dirname "$OPENSCADKIT_DIR")"  # openscadkit repository root

# Build directories
BUILD_ROOT="$OPENSCADKIT_DIR/build"
SOURCES_DIR="$BUILD_ROOT/sources"
INSTALL_DIR="$BUILD_ROOT/install"

# Toolchain files
TOOLCHAINS_DIR="$SCRIPT_DIR/toolchains"

# Platforms to build
# Format: platform:arch:toolchain:sdk
PLATFORMS=(
    "ios:arm64:ios-arm64:iphoneos"
    "ios-simulator:arm64:ios-simulator:iphonesimulator"
    "ios-simulator:x86_64:ios-simulator:iphonesimulator"
    "macos:arm64:macos:macosx"
    "macos:x86_64:macos:macosx"
    "xros:arm64:xros-arm64:xros"
    "xros-simulator:arm64:xros-simulator:xrsimulator"
)

# Deployment targets
IOS_DEPLOYMENT_TARGET="18.0"
MACOS_DEPLOYMENT_TARGET="15.0"
XROS_DEPLOYMENT_TARGET="1.0"

# Number of parallel jobs
JOBS=$(sysctl -n hw.ncpu)

# Dependency versions (use stable releases)
BOOST_VERSION="1.84.0"
FREETYPE_VERSION="2.14.1"
HARFBUZZ_VERSION="8.3.0"
DOUBLE_CONVERSION_VERSION="3.3.0"
MANIFOLD_VERSION="3.3.2"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Parse platform string into components
# Usage: parse_platform "ios:arm64:ios-arm64:iphoneos"
# Sets: PLATFORM, ARCH, TOOLCHAIN, SDK
parse_platform() {
    IFS=':' read -r PLATFORM ARCH TOOLCHAIN SDK <<< "$1"
}

# Get install directory for a platform/arch combo
get_install_dir() {
    local platform=$1
    local arch=$2
    echo "$INSTALL_DIR/${platform}-${arch}"
}

# Get build directory for a platform/arch/dependency combo
get_build_dir() {
    local dep=$1
    local platform=$2
    local arch=$3
    echo "$BUILD_ROOT/${platform}-${arch}/${dep}"
}

# Get toolchain file path
get_toolchain_file() {
    local toolchain=$1
    echo "$TOOLCHAINS_DIR/${toolchain}.toolchain.cmake"
}

# Ensure directory exists
ensure_dir() {
    mkdir -p "$1"
}

# Download and extract source if needed
download_source() {
    local name=$1
    local url=$2
    local dest="$SOURCES_DIR/$name"

    if [ -d "$dest" ]; then
        log_info "Source $name already exists"
        return 0
    fi

    ensure_dir "$SOURCES_DIR"
    log_info "Downloading $name..."

    local archive="$SOURCES_DIR/${name}.tar.gz"
    curl -L "$url" -o "$archive"

    log_info "Extracting $name..."
    mkdir -p "$dest"
    tar -xzf "$archive" -C "$dest" --strip-components=1
    rm "$archive"

    log_success "Downloaded and extracted $name"
}

# Clone git repo if needed
clone_repo() {
    local name=$1
    local url=$2
    local branch=$3
    local dest="$SOURCES_DIR/$name"

    if [ -d "$dest" ]; then
        log_info "Source $name already exists"
        return 0
    fi

    ensure_dir "$SOURCES_DIR"
    log_info "Cloning $name..."

    if [ -n "$branch" ]; then
        git clone --depth 1 --branch "$branch" "$url" "$dest"
    else
        git clone --depth 1 "$url" "$dest"
    fi

    log_success "Cloned $name"
}
