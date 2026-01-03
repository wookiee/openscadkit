# OpenSCADKit Build Scripts

This directory contains the cross-compilation toolchain for building OpenSCAD as a native iOS/macOS XCFramework.

## Build Targets

| Platform | Architecture | SDK |
|----------|--------------|-----|
| iOS Device | arm64 | iphoneos |
| iOS Simulator | arm64, x86_64 | iphonesimulator |
| macOS | arm64, x86_64 | macosx |
| visionOS Device | arm64 | xros |
| visionOS Simulator | arm64 | xrsimulator |

## Dependencies (Build Order)

1. **double-conversion** - Google's binary-decimal conversion library
2. **Boost** - Header-only portions + program_options, regex, filesystem
3. **FreeType** - Font rendering library
4. **HarfBuzz** - Text shaping engine (depends on FreeType)
5. **Clipper2** - Polygon clipping library
6. **Manifold** - High-performance geometry kernel (depends on Clipper2)
7. **OpenSCAD** - The geometry engine itself (depends on all above)

## Directory Structure

```
BuildScripts/
├── toolchains/           # CMake toolchain files
│   ├── ios.toolchain.cmake
│   ├── ios-simulator.toolchain.cmake
│   ├── macos.toolchain.cmake
│   ├── xros.toolchain.cmake
│   └── xros-simulator.toolchain.cmake
├── build-all.sh          # Master build script
├── build-boost.sh        # Individual dependency builds
├── build-freetype.sh
├── build-harfbuzz.sh
├── build-manifold.sh
└── build-openscad.sh
```

## Build Output

All builds output to `../build/` with the structure:
```
build/
├── ios-arm64/
├── ios-simulator-arm64/
├── ios-simulator-x86_64/
├── macos-arm64/
├── macos-x86_64/
├── xros-arm64/
├── xros-simulator-arm64/
└── install/              # Final installed libraries
    ├── ios-arm64/
    │   ├── include/
    │   └── lib/
    └── ...
```

## Usage

```bash
# Build all dependencies for all platforms
./build-all.sh

# Build specific dependency
./build-freetype.sh ios-arm64

# Create XCFramework after all builds complete
./create-xcframework.sh
```
