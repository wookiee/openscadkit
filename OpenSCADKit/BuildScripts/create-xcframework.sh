#!/bin/bash
# Create XCFramework from all built static libraries
#
# This script:
# 1. Merges all static libraries into a single libopenscad-all.a per platform
# 2. Uses lipo to create fat binaries for simulators (arm64 + x86_64)
# 3. Creates an XCFramework using xcodebuild -create-xcframework
#
# Usage: ./create-xcframework.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

XCFRAMEWORK_NAME="OpenSCAD"
OUTPUT_DIR="$BUILD_ROOT/xcframework"
XCFRAMEWORK_PATH="$OUTPUT_DIR/$XCFRAMEWORK_NAME.xcframework"

# Static libraries to include (order matters for dependencies)
LIBS=(
    "libdouble-conversion.a"
    "libboost_filesystem.a"
    "libboost_program_options.a"
    "libboost_regex.a"
    "libboost_atomic.a"
    "libgmp.a"
    "libgmpxx.a"
    "libmpfr.a"
    "libexpat.a"
    "libfreetype.a"
    "libharfbuzz.a"
    "libfontconfig.a"
    "libglib-shim.a"
    "libzip.a"
    "libClipper2.a"
    "libmanifold.a"
    "libsvg.a"
    "libopenscad.a"
)

# Create merged static library for a platform
merge_libs() {
    local platform=$1
    local arch=$2
    local install_dir=$(get_install_dir "$platform" "$arch")
    local output_lib="$OUTPUT_DIR/$platform-$arch/lib$XCFRAMEWORK_NAME.a"

    log_info "Merging libraries for $platform-$arch..."

    ensure_dir "$(dirname "$output_lib")"

    # Collect all library paths
    local lib_paths=()
    for lib in "${LIBS[@]}"; do
        local lib_path="$install_dir/lib/$lib"
        if [ -f "$lib_path" ]; then
            lib_paths+=("$lib_path")
        else
            log_warning "Library $lib not found for $platform-$arch (skipping)"
        fi
    done

    if [ ${#lib_paths[@]} -eq 0 ]; then
        log_error "No libraries found for $platform-$arch"
        return 1
    fi

    # Use libtool to merge all static libraries
    libtool -static -o "$output_lib" "${lib_paths[@]}"

    log_success "Created merged library: $output_lib ($(du -h "$output_lib" | cut -f1))"
}

# Create fat binary for simulator (arm64 + x86_64)
create_fat_simulator() {
    local platform=$1  # ios-simulator or macos
    local output_lib="$OUTPUT_DIR/$platform-fat/lib$XCFRAMEWORK_NAME.a"

    local arm64_lib="$OUTPUT_DIR/$platform-arm64/lib$XCFRAMEWORK_NAME.a"
    local x86_64_lib="$OUTPUT_DIR/$platform-x86_64/lib$XCFRAMEWORK_NAME.a"

    if [ ! -f "$arm64_lib" ]; then
        log_error "Missing arm64 library: $arm64_lib"
        return 1
    fi

    if [ ! -f "$x86_64_lib" ]; then
        log_error "Missing x86_64 library: $x86_64_lib"
        return 1
    fi

    log_info "Creating fat binary for $platform..."

    ensure_dir "$(dirname "$output_lib")"

    lipo -create "$arm64_lib" "$x86_64_lib" -output "$output_lib"

    log_success "Created fat library: $output_lib ($(du -h "$output_lib" | cut -f1))"
}

# Collect headers
collect_headers() {
    local platform=$1
    local arch=$2
    local install_dir=$(get_install_dir "$platform" "$arch")
    local headers_dir="$OUTPUT_DIR/Headers"

    if [ -d "$headers_dir" ]; then
        return 0  # Already collected
    fi

    log_info "Collecting headers..."

    ensure_dir "$headers_dir"

    # Copy OpenSCAD headers
    if [ -d "$install_dir/include/openscad" ]; then
        cp -R "$install_dir/include/openscad" "$headers_dir/"
    fi

    # Copy a minimal module map for the framework
    cat > "$headers_dir/module.modulemap" << 'MODULEMAP'
module OpenSCAD {
    header "openscad/OpenSCAD.h"
    export *
}
MODULEMAP

    # Create an umbrella header that includes the C bridge API
    cat > "$headers_dir/openscad/OpenSCAD.h" << 'UMBRELLA'
// OpenSCAD XCFramework
// This header provides the C API for Swift interop

#ifndef OPENSCAD_H
#define OPENSCAD_H

#include "COpenSCAD.h"

#endif // OPENSCAD_H
UMBRELLA

    log_success "Headers collected to $headers_dir"
}

# Create the XCFramework
create_xcframework() {
    log_info "Creating XCFramework..."

    # Remove old framework if exists
    rm -rf "$XCFRAMEWORK_PATH"

    # Build xcodebuild command
    local cmd="xcodebuild -create-xcframework"

    # iOS Device (arm64)
    local ios_device="$OUTPUT_DIR/ios-arm64/lib$XCFRAMEWORK_NAME.a"
    if [ -f "$ios_device" ]; then
        cmd+=" -library $ios_device -headers $OUTPUT_DIR/Headers"
    fi

    # iOS Simulator (fat: arm64 + x86_64)
    local ios_sim="$OUTPUT_DIR/ios-simulator-fat/lib$XCFRAMEWORK_NAME.a"
    if [ -f "$ios_sim" ]; then
        cmd+=" -library $ios_sim -headers $OUTPUT_DIR/Headers"
    fi

    # macOS (fat: arm64 + x86_64)
    local macos="$OUTPUT_DIR/macos-fat/lib$XCFRAMEWORK_NAME.a"
    if [ -f "$macos" ]; then
        cmd+=" -library $macos -headers $OUTPUT_DIR/Headers"
    fi

    # visionOS Device (arm64)
    local xros_device="$OUTPUT_DIR/xros-arm64/lib$XCFRAMEWORK_NAME.a"
    if [ -f "$xros_device" ]; then
        cmd+=" -library $xros_device -headers $OUTPUT_DIR/Headers"
    fi

    # visionOS Simulator (arm64 only - no x86_64 for visionOS)
    local xros_sim="$OUTPUT_DIR/xros-simulator-arm64/lib$XCFRAMEWORK_NAME.a"
    if [ -f "$xros_sim" ]; then
        cmd+=" -library $xros_sim -headers $OUTPUT_DIR/Headers"
    fi

    cmd+=" -output $XCFRAMEWORK_PATH"

    log_info "Running: $cmd"
    eval $cmd

    log_success "XCFramework created: $XCFRAMEWORK_PATH"

    # Show framework structure
    echo ""
    echo "XCFramework structure:"
    find "$XCFRAMEWORK_PATH" -type d -maxdepth 2

    # Show total size
    echo ""
    echo "Total size: $(du -sh "$XCFRAMEWORK_PATH" | cut -f1)"
}

# Main
main() {
    log_info "Creating $XCFRAMEWORK_NAME.xcframework..."

    ensure_dir "$OUTPUT_DIR"

    # Step 1: Merge libraries for each platform
    merge_libs "ios" "arm64"
    merge_libs "ios-simulator" "arm64"
    merge_libs "ios-simulator" "x86_64"
    merge_libs "macos" "arm64"
    merge_libs "macos" "x86_64"
    merge_libs "xros" "arm64"
    merge_libs "xros-simulator" "arm64"

    # Step 2: Create fat binaries for simulators and macOS
    create_fat_simulator "ios-simulator"
    create_fat_simulator "macos"

    # Step 3: Collect headers (use ios-arm64 as reference)
    collect_headers "ios" "arm64"

    # Step 4: Create XCFramework
    create_xcframework

    log_success "Done! XCFramework is at: $XCFRAMEWORK_PATH"
}

main "$@"
