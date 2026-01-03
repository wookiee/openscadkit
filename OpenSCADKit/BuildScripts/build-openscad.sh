#!/bin/bash
# Build OpenSCAD as a static library for iOS/macOS
#
# This builds OpenSCAD in NULLGL/HEADLESS mode as a static library.
# All GUI components are disabled.
#
# Usage: ./build-openscad.sh [platform-arch]
# Example: ./build-openscad.sh ios-arm64
# Without arguments: builds for all platforms

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

DEP_NAME="openscad"
OPENSCAD_SOURCE_DIR="$SCRIPT_DIR/../.."  # OpenSCAD source is at repo root (grandparent of BuildScripts)

# Build OpenSCAD for a single platform/arch
build_openscad_platform() {
    local platform=$1
    local arch=$2
    local toolchain=$3
    local sdk=$4

    local build_dir=$(get_build_dir "$DEP_NAME" "$platform" "$arch")
    local install_dir=$(get_install_dir "$platform" "$arch")
    local toolchain_file=$(get_toolchain_file "$toolchain")

    # Check if already built
    if [ -f "$install_dir/lib/libopenscad.a" ]; then
        log_info "OpenSCAD already built for $platform-$arch"
        return 0
    fi

    # Check required dependencies
    local required_libs=(
        "libboost_filesystem.a"
        "libfreetype.a"
        "libharfbuzz.a"
        "libfontconfig.a"
        "libgmp.a"
        "libmpfr.a"
        "libdouble-conversion.a"
        "libmanifold.a"
        "libClipper2.a"
        "libzip.a"
        "libexpat.a"
        "libglib-shim.a"
    )

    for lib in "${required_libs[@]}"; do
        if [ ! -f "$install_dir/lib/$lib" ]; then
            log_error "Required library $lib not found for $platform-$arch"
            exit 1
        fi
    done

    log_info "Building OpenSCAD for $platform-$arch..."

    ensure_dir "$build_dir"
    ensure_dir "$install_dir"

    cd "$build_dir"

    # Get the glib-shim include path (we need to tell OpenSCAD to use it as glib.h)
    local glib_include="$install_dir/include"

    # Create a dummy Sanitizers module to avoid errors
    ensure_dir "$build_dir/cmake"
    cat > "$build_dir/cmake/SanitizersConfig.cmake" << 'CMAKE_DUMMY'
# Dummy Sanitizers config - provides empty add_sanitizers macro
macro(add_sanitizers)
endmacro()
CMAKE_DUMMY

    # Create a dummy TBB target to satisfy manifold's conditional dependency
    # Install it to the install prefix so it's found when manifold's config is loaded
    ensure_dir "$install_dir/lib/cmake/TBB"
    cat > "$install_dir/lib/cmake/TBB/TBBConfig.cmake" << 'CMAKE_TBB'
# Dummy TBB config - manifold has conditional TBB dependency that CMake still validates
if(NOT TARGET TBB::tbb)
  add_library(TBB::tbb INTERFACE IMPORTED)
endif()
set(TBB_FOUND TRUE)
set(TBB_VERSION "2022.0.0")
CMAKE_TBB

    # Also put it in the build cmake dir for other uses
    cat > "$build_dir/cmake/TBBConfig.cmake" << 'CMAKE_TBB'
# Dummy TBB config - manifold has conditional TBB dependency that CMake still validates
if(NOT TARGET TBB::tbb)
  add_library(TBB::tbb INTERFACE IMPORTED)
endif()
set(TBB_FOUND TRUE)
CMAKE_TBB

    # Create a stub libintl.h for iOS (no gettext support)
    ensure_dir "$build_dir/stubs"
    cat > "$build_dir/stubs/libintl.h" << 'LIBINTL_STUB'
/* Stub libintl.h for iOS - provides no-op gettext functions */
#ifndef LIBINTL_H_STUB
#define LIBINTL_H_STUB

#ifdef __cplusplus
extern "C" {
#endif

/* Return the translation of MSGID */
static inline char *gettext(const char *msgid) {
    return (char *)msgid;
}

static inline char *dgettext(const char *domainname, const char *msgid) {
    (void)domainname;
    return (char *)msgid;
}

static inline char *dcgettext(const char *domainname, const char *msgid, int category) {
    (void)domainname;
    (void)category;
    return (char *)msgid;
}

static inline char *ngettext(const char *msgid1, const char *msgid2, unsigned long n) {
    return (char *)(n == 1 ? msgid1 : msgid2);
}

static inline char *dngettext(const char *domainname, const char *msgid1, const char *msgid2, unsigned long n) {
    (void)domainname;
    return (char *)(n == 1 ? msgid1 : msgid2);
}

static inline char *textdomain(const char *domainname) {
    return (char *)domainname;
}

static inline char *bindtextdomain(const char *domainname, const char *dirname) {
    (void)dirname;
    return (char *)domainname;
}

static inline char *bind_textdomain_codeset(const char *domainname, const char *codeset) {
    (void)codeset;
    return (char *)domainname;
}

#ifdef __cplusplus
}
#endif

#endif /* LIBINTL_H_STUB */
LIBINTL_STUB

    # Configure with CMake
    cmake "$OPENSCAD_SOURCE_DIR" \
        -DCMAKE_TOOLCHAIN_FILE="$toolchain_file" \
        -DCMAKE_OSX_ARCHITECTURES="$arch" \
        -DCMAKE_INSTALL_PREFIX="$install_dir" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_PREFIX_PATH="$install_dir" \
        -DCMAKE_FIND_ROOT_PATH="$install_dir" \
        -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
        -DCMAKE_CXX_FLAGS="-I$build_dir/stubs" \
        -DCMAKE_C_FLAGS="-I$build_dir/stubs" \
        -DSanitizers_DIR="$build_dir/cmake" \
        -DTBB_DIR="$build_dir/cmake" \
        -DCOCOA_LIBRARY="-framework Foundation" \
        \
        -DNULLGL=ON \
        -DHEADLESS=ON \
        -DBUILD_SHARED_LIBS=OFF \
        -DEXPERIMENTAL=OFF \
        -DSNAPSHOT=OFF \
        -DENABLE_TESTS=OFF \
        -DENABLE_PYTHON=OFF \
        -DUSE_BUILTIN_OPENCSG=OFF \
        -DUSE_MIMALLOC=OFF \
        -DUSE_GLEW=OFF \
        -DUSE_QT6=OFF \
        -DENABLE_CAIRO=OFF \
        -DCMAKE_REQUIRE_FIND_PACKAGE_Lib3MF=OFF \
        -DCMAKE_DISABLE_FIND_PACKAGE_Lib3MF=ON \
        -DENABLE_HIDAPI=OFF \
        -DENABLE_SPNAV=OFF \
        -DUSE_BUILTIN_MANIFOLD=OFF \
        -DUSE_BUILTIN_CLIPPER2=OFF \
        -DENABLE_MANIFOLD=ON \
        -DMANIFOLD_PAR=OFF \
        -DTBB_FOUND=FALSE \
        \
        -DBoost_USE_STATIC_LIBS=ON \
        -DBoost_USE_STATIC_RUNTIME=ON \
        -DBoost_NO_BOOST_CMAKE=OFF \
        -DBoost_INCLUDE_DIR="$install_dir/include" \
        -DBOOST_ROOT="$install_dir" \
        \
        -DEIGEN3_INCLUDE_DIR="$install_dir/include/eigen3" \
        \
        -DCGAL_DIR="$install_dir/lib/cmake/CGAL" \
        -DGMP_INCLUDE_DIR="$install_dir/include" \
        -DGMP_LIBRARIES="$install_dir/lib/libgmp.a" \
        -DMPFR_INCLUDE_DIR="$install_dir/include" \
        -DMPFR_LIBRARIES="$install_dir/lib/libmpfr.a" \
        \
        -DFreetype_INCLUDE_DIRS="$install_dir/include/freetype2" \
        -DFreetype_LIBRARY="$install_dir/lib/libfreetype.a" \
        \
        -DHarfBuzz_INCLUDE_DIRS="$install_dir/include/harfbuzz" \
        -DHarfBuzz_LIBRARIES="$install_dir/lib/libharfbuzz.a" \
        \
        -DFontconfig_INCLUDE_DIRS="$install_dir/include" \
        -DFontconfig_LIBRARIES="$install_dir/lib/libfontconfig.a" \
        \
        -DLibZip_INCLUDE_DIR="$install_dir/include" \
        -DLibZip_LIBRARY="$install_dir/lib/libzip.a" \
        \
        -Ddouble-conversion_DIR="$install_dir/lib/cmake/double-conversion" \
        \
        -Dmanifold_DIR="$install_dir/lib/cmake/manifold" \
        \
        -DClipper2_DIR="$install_dir/lib/cmake/Clipper2" \
        \
        -DGLIB2_INCLUDE_DIRS="$glib_include" \
        -DGLIB2_LIBRARIES="$install_dir/lib/libglib-shim.a"

    # Build OpenSCAD and SVG libraries
    cmake --build . --parallel $JOBS --target OpenSCADLibInternal
    cmake --build . --parallel $JOBS --target svg

    # Install the static libraries
    # OpenSCAD doesn't have a proper install target for library mode, so we do it manually
    ensure_dir "$install_dir/lib"
    ensure_dir "$install_dir/include/openscad"

    # Copy the main OpenSCAD static library (note: cmake outputs lowercase name)
    if [ -f "libopenscadinternal.a" ]; then
        cp "libopenscadinternal.a" "$install_dir/lib/libopenscad.a"
    elif [ -f "libOpenSCADLibInternal.a" ]; then
        cp "libOpenSCADLibInternal.a" "$install_dir/lib/libopenscad.a"
    else
        log_error "Could not find built OpenSCAD library"
        find . -name "*.a" -type f
        exit 1
    fi

    # Copy libsvg.a (SVG import support)
    if [ -f "libsvg.a" ]; then
        cp "libsvg.a" "$install_dir/lib/libsvg.a"
    else
        log_warning "libsvg.a not found - SVG import will not work"
    fi

    # Copy essential headers
    cp -R "$OPENSCAD_SOURCE_DIR/src/core/"*.h "$install_dir/include/openscad/" 2>/dev/null || true
    cp -R "$OPENSCAD_SOURCE_DIR/src/geometry/"*.h "$install_dir/include/openscad/" 2>/dev/null || true

    # Copy C bridge header (for Swift interop)
    cp "$OPENSCAD_SOURCE_DIR/src/io/export_cbridge.h" "$install_dir/include/openscad/COpenSCAD.h"

    log_success "Built OpenSCAD for $platform-$arch"
}

# Build for all platforms or specific one
build_openscad() {
    if [ -n "$1" ]; then
        # Build specific platform
        for p in "${PLATFORMS[@]}"; do
            parse_platform "$p"
            if [ "$PLATFORM-$ARCH" == "$1" ]; then
                build_openscad_platform "$PLATFORM" "$ARCH" "$TOOLCHAIN" "$SDK"
                return 0
            fi
        done
        log_error "Unknown platform: $1"
        exit 1
    else
        # Build all platforms
        for p in "${PLATFORMS[@]}"; do
            parse_platform "$p"
            build_openscad_platform "$PLATFORM" "$ARCH" "$TOOLCHAIN" "$SDK"
        done
    fi
}

# Run
build_openscad "$1"
