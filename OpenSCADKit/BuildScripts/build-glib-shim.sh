#!/bin/bash
# Create a minimal GLib UTF-8 shim for iOS/macOS
#
# This creates a lightweight replacement for GLib that provides only the
# UTF-8 functions used by OpenSCAD. This avoids the need to build the
# full GLib library with its libffi dependency (which has assembly issues
# on newer Apple platforms).
#
# OpenSCAD only uses GLib for UTF-8 string handling:
# - g_utf8_strlen, g_utf8_get_char, g_utf8_validate, g_utf8_next_char
# - g_utf8_offset_to_pointer, g_utf8_strncpy
# - g_unichar_validate, g_unichar_to_utf8
#
# Usage: ./build-glib-shim.sh [platform-arch]
# Example: ./build-glib-shim.sh ios-arm64
# Without arguments: installs for all platforms

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

DEP_NAME="glib-shim"

# Create the shim source files
create_shim_sources() {
    local shim_dir="$SOURCES_DIR/$DEP_NAME"

    if [ -f "$shim_dir/glib.h" ]; then
        log_info "Shim sources already created"
        return 0
    fi

    log_info "Creating GLib shim sources..."
    ensure_dir "$shim_dir"
    ensure_dir "$shim_dir/glib"

    # Create the main glib.h header
    cat > "$shim_dir/glib.h" << 'HEADER_EOF'
/*
 * Minimal GLib UTF-8 Shim
 *
 * This header provides a lightweight replacement for GLib's UTF-8 functions
 * used by OpenSCAD. It avoids the need to build the full GLib library.
 */

#ifndef GLIB_SHIM_H
#define GLIB_SHIM_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Version macros - pretend to be GLib 2.78 */
#define GLIB_MAJOR_VERSION 2
#define GLIB_MINOR_VERSION 78
#define GLIB_MICRO_VERSION 0

/* Type definitions */
typedef char gchar;
typedef unsigned char guchar;
typedef int gint;
typedef unsigned int guint;
typedef int32_t gint32;
typedef uint32_t guint32;
typedef int gboolean;
typedef ptrdiff_t gssize;
typedef size_t gsize;
typedef uint32_t gunichar;

#ifndef TRUE
#define TRUE 1
#endif

#ifndef FALSE
#define FALSE 0
#endif

#ifndef NULL
#define NULL ((void*)0)
#endif

/* UTF-8 byte sequence length based on first byte */
#define UTF8_CHAR_LEN(c) \
    (((unsigned char)(c) < 0x80) ? 1 : \
     ((unsigned char)(c) < 0xC0) ? 1 : \
     ((unsigned char)(c) < 0xE0) ? 2 : \
     ((unsigned char)(c) < 0xF0) ? 3 : \
     ((unsigned char)(c) < 0xF8) ? 4 : 1)

/* Macro to advance to next UTF-8 character */
#define g_utf8_next_char(p) ((p) + UTF8_CHAR_LEN(*(p)))

/* Function declarations */

/**
 * g_utf8_get_char:
 * @p: a pointer to Unicode character encoded as UTF-8
 *
 * Converts a sequence of bytes encoded as UTF-8 to a Unicode character.
 *
 * Returns: the resulting character
 */
gunichar g_utf8_get_char(const gchar *p);

/**
 * g_utf8_strlen:
 * @p: pointer to the start of a UTF-8 encoded string
 * @max: the maximum number of bytes to examine (-1 for unlimited)
 *
 * Computes the length of the string in characters.
 *
 * Returns: the length of the string in characters
 */
gssize g_utf8_strlen(const gchar *p, gssize max);

/**
 * g_utf8_validate:
 * @str: a pointer to character data
 * @max_len: max bytes to validate, or -1 to go until NUL
 * @end: return location for end of valid data (can be NULL)
 *
 * Validates UTF-8 encoded text.
 *
 * Returns: TRUE if the text was valid UTF-8
 */
gboolean g_utf8_validate(const gchar *str, gssize max_len, const gchar **end);

/**
 * g_utf8_offset_to_pointer:
 * @str: a UTF-8 encoded string
 * @offset: a character offset within @str
 *
 * Converts from an integer character offset to a pointer.
 *
 * Returns: the resulting pointer
 */
gchar *g_utf8_offset_to_pointer(const gchar *str, gssize offset);

/**
 * g_utf8_strncpy:
 * @dest: buffer to fill with characters from @src
 * @src: UTF-8 encoded string
 * @n: character count
 *
 * Copies a substring of n characters from src to dest.
 *
 * Returns: @dest
 */
gchar *g_utf8_strncpy(gchar *dest, const gchar *src, gsize n);

/**
 * g_unichar_validate:
 * @ch: a Unicode character
 *
 * Checks whether @ch is a valid Unicode character.
 *
 * Returns: TRUE if @ch is a valid Unicode character
 */
gboolean g_unichar_validate(gunichar ch);

/**
 * g_unichar_to_utf8:
 * @c: a Unicode character code
 * @outbuf: output buffer, must have at least 6 bytes of space
 *
 * Converts a single character to UTF-8.
 *
 * Returns: number of bytes written
 */
gint g_unichar_to_utf8(gunichar c, gchar *outbuf);

#ifdef __cplusplus
}
#endif

#endif /* GLIB_SHIM_H */
HEADER_EOF

    # Create the implementation file
    cat > "$shim_dir/glib_utf8.c" << 'IMPL_EOF'
/*
 * Minimal GLib UTF-8 Shim Implementation
 */

#include "glib.h"
#include <string.h>

gunichar g_utf8_get_char(const gchar *p)
{
    const unsigned char *s = (const unsigned char *)p;

    if (s[0] < 0x80) {
        return s[0];
    }

    gunichar result;
    int len;

    if ((s[0] & 0xE0) == 0xC0) {
        len = 2;
        result = s[0] & 0x1F;
    } else if ((s[0] & 0xF0) == 0xE0) {
        len = 3;
        result = s[0] & 0x0F;
    } else if ((s[0] & 0xF8) == 0xF0) {
        len = 4;
        result = s[0] & 0x07;
    } else {
        return 0xFFFD; /* Replacement character */
    }

    for (int i = 1; i < len; i++) {
        if ((s[i] & 0xC0) != 0x80) {
            return 0xFFFD;
        }
        result = (result << 6) | (s[i] & 0x3F);
    }

    return result;
}

gssize g_utf8_strlen(const gchar *p, gssize max)
{
    gssize len = 0;
    const unsigned char *s = (const unsigned char *)p;
    const unsigned char *end = (max < 0) ? NULL : s + max;

    while (*s && (!end || s < end)) {
        /* Skip continuation bytes */
        if ((*s & 0xC0) != 0x80) {
            len++;
        }
        s++;
    }

    return len;
}

gboolean g_utf8_validate(const gchar *str, gssize max_len, const gchar **end)
{
    const unsigned char *p = (const unsigned char *)str;
    const unsigned char *limit = (max_len < 0) ? NULL : p + max_len;

    while (*p && (!limit || p < limit)) {
        unsigned char c = *p;
        int len;

        if (c < 0x80) {
            len = 1;
        } else if ((c & 0xE0) == 0xC0) {
            len = 2;
            if (c < 0xC2) goto error; /* Overlong */
        } else if ((c & 0xF0) == 0xE0) {
            len = 3;
        } else if ((c & 0xF8) == 0xF0) {
            len = 4;
            if (c > 0xF4) goto error; /* Beyond Unicode */
        } else {
            goto error;
        }

        /* Check we have enough bytes */
        if (limit && p + len > limit) {
            goto error;
        }

        /* Check continuation bytes */
        for (int i = 1; i < len; i++) {
            if ((p[i] & 0xC0) != 0x80) {
                goto error;
            }
        }

        /* Check for overlong encodings and surrogates */
        if (len == 3) {
            gunichar ch = ((p[0] & 0x0F) << 12) | ((p[1] & 0x3F) << 6) | (p[2] & 0x3F);
            if (ch < 0x0800 || (ch >= 0xD800 && ch <= 0xDFFF)) {
                goto error;
            }
        } else if (len == 4) {
            gunichar ch = ((p[0] & 0x07) << 18) | ((p[1] & 0x3F) << 12) |
                         ((p[2] & 0x3F) << 6) | (p[3] & 0x3F);
            if (ch < 0x10000 || ch > 0x10FFFF) {
                goto error;
            }
        }

        p += len;
    }

    if (end) *end = (const gchar *)p;
    return TRUE;

error:
    if (end) *end = (const gchar *)p;
    return FALSE;
}

gchar *g_utf8_offset_to_pointer(const gchar *str, gssize offset)
{
    const unsigned char *p = (const unsigned char *)str;

    while (offset > 0 && *p) {
        p += UTF8_CHAR_LEN(*p);
        offset--;
    }

    return (gchar *)p;
}

gchar *g_utf8_strncpy(gchar *dest, const gchar *src, gsize n)
{
    const unsigned char *s = (const unsigned char *)src;
    gchar *d = dest;

    while (n > 0 && *s) {
        int len = UTF8_CHAR_LEN(*s);
        memcpy(d, s, len);
        d += len;
        s += len;
        n--;
    }

    *d = '\0';
    return dest;
}

gboolean g_unichar_validate(gunichar ch)
{
    /* Valid Unicode codepoints: 0x0000-0xD7FF, 0xE000-0x10FFFF */
    /* Excludes surrogates (0xD800-0xDFFF) and values > 0x10FFFF */
    if (ch > 0x10FFFF) return FALSE;
    if (ch >= 0xD800 && ch <= 0xDFFF) return FALSE;
    return TRUE;
}

gint g_unichar_to_utf8(gunichar c, gchar *outbuf)
{
    unsigned char *buf = (unsigned char *)outbuf;
    int len;

    if (c < 0x80) {
        buf[0] = c;
        buf[1] = '\0';
        len = 1;
    } else if (c < 0x800) {
        buf[0] = 0xC0 | (c >> 6);
        buf[1] = 0x80 | (c & 0x3F);
        buf[2] = '\0';
        len = 2;
    } else if (c < 0x10000) {
        buf[0] = 0xE0 | (c >> 12);
        buf[1] = 0x80 | ((c >> 6) & 0x3F);
        buf[2] = 0x80 | (c & 0x3F);
        buf[3] = '\0';
        len = 3;
    } else if (c <= 0x10FFFF) {
        buf[0] = 0xF0 | (c >> 18);
        buf[1] = 0x80 | ((c >> 12) & 0x3F);
        buf[2] = 0x80 | ((c >> 6) & 0x3F);
        buf[3] = 0x80 | (c & 0x3F);
        buf[4] = '\0';
        len = 4;
    } else {
        /* Invalid - output replacement character */
        buf[0] = 0xEF;
        buf[1] = 0xBF;
        buf[2] = 0xBD;
        buf[3] = '\0';
        len = 3;
    }

    return len;
}
IMPL_EOF

    # Create CMakeLists.txt
    cat > "$shim_dir/CMakeLists.txt" << 'CMAKE_EOF'
cmake_minimum_required(VERSION 3.15)
project(glib-shim C)

add_library(glib-shim STATIC glib_utf8.c)
target_include_directories(glib-shim PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})

install(TARGETS glib-shim
    ARCHIVE DESTINATION lib
)
install(FILES glib.h DESTINATION include)
# Also install as glib/glib.h for compatibility with some includes
install(FILES glib.h DESTINATION include/glib)
CMAKE_EOF

    log_success "Created GLib shim sources"
}

# Build shim for a single platform/arch
build_glib_shim_platform() {
    local platform=$1
    local arch=$2
    local toolchain=$3
    local sdk=$4

    local build_dir=$(get_build_dir "$DEP_NAME" "$platform" "$arch")
    local install_dir=$(get_install_dir "$platform" "$arch")
    local source_dir="$SOURCES_DIR/$DEP_NAME"
    local toolchain_file=$(get_toolchain_file "$toolchain")

    # Check if already built
    if [ -f "$install_dir/lib/libglib-shim.a" ]; then
        log_info "GLib shim already built for $platform-$arch"
        return 0
    fi

    log_info "Building GLib shim for $platform-$arch..."

    ensure_dir "$build_dir"
    ensure_dir "$install_dir"

    cd "$build_dir"

    # Configure with CMake
    cmake "$source_dir" \
        -DCMAKE_TOOLCHAIN_FILE="$toolchain_file" \
        -DCMAKE_OSX_ARCHITECTURES="$arch" \
        -DCMAKE_INSTALL_PREFIX="$install_dir" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_POLICY_VERSION_MINIMUM=3.5

    # Build and install
    cmake --build . --parallel $JOBS
    cmake --install .

    log_success "Built GLib shim for $platform-$arch"
}

# Build for all platforms or specific one
build_glib_shim() {
    create_shim_sources

    if [ -n "$1" ]; then
        # Build specific platform
        for p in "${PLATFORMS[@]}"; do
            parse_platform "$p"
            if [ "$PLATFORM-$ARCH" == "$1" ]; then
                build_glib_shim_platform "$PLATFORM" "$ARCH" "$TOOLCHAIN" "$SDK"
                return 0
            fi
        done
        log_error "Unknown platform: $1"
        exit 1
    else
        # Build all platforms
        for p in "${PLATFORMS[@]}"; do
            parse_platform "$p"
            build_glib_shim_platform "$PLATFORM" "$ARCH" "$TOOLCHAIN" "$SDK"
        done
    fi
}

# Run
build_glib_shim "$1"
