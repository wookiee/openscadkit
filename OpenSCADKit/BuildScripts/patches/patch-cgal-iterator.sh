#!/bin/bash
# Patch CGAL iterator.h for Boost 1.84+ / Clang 19+ compatibility
# See: https://github.com/CGAL/cgal/commit/0de060acd68
#
# This fixes the "no member named 'base'" error in CGAL's BGL iterator classes

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPENSCADKIT_DIR="$(dirname "$SCRIPT_DIR")"
INSTALL_DIR="$OPENSCADKIT_DIR/build/install"

patch_iterator() {
    local file="$1"

    if [ ! -f "$file" ]; then
        echo "File not found: $file"
        return 0
    fi

    # Check if already patched
    if grep -q "return (g != nullptr);" "$file" 2>/dev/null; then
        echo "Already patched: $file"
        return 0
    fi

    echo "Patching: $file"

    # Replace the broken base() calls with correct g != nullptr check
    sed -i.bak 's/return (! (this->base() == nullptr));/return (g != nullptr);/g' "$file"
    rm -f "${file}.bak"
}

# Find and patch all installed iterator.h files
for dir in "$INSTALL_DIR"/*/include/CGAL/boost/graph; do
    if [ -d "$dir" ]; then
        patch_iterator "$dir/iterator.h"
    fi
done

echo "CGAL iterator patch complete"
