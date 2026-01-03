# CMake Toolchain for macOS (arm64 + x86_64)
#
# Usage: cmake -DCMAKE_TOOLCHAIN_FILE=macos.toolchain.cmake ..
# For specific arch: cmake -DCMAKE_TOOLCHAIN_FILE=... -DCMAKE_OSX_ARCHITECTURES=arm64 ..

set(CMAKE_SYSTEM_NAME Darwin)

# Default to native architecture, can override with -DCMAKE_OSX_ARCHITECTURES
if(NOT CMAKE_OSX_ARCHITECTURES)
    execute_process(
        COMMAND uname -m
        OUTPUT_VARIABLE CMAKE_OSX_ARCHITECTURES
        OUTPUT_STRIP_TRAILING_WHITESPACE
    )
endif()

# Deployment target
set(CMAKE_OSX_DEPLOYMENT_TARGET "15.0" CACHE STRING "Minimum macOS version")

# Find Xcode SDK
execute_process(
    COMMAND xcrun --sdk macosx --show-sdk-path
    OUTPUT_VARIABLE CMAKE_OSX_SYSROOT
    OUTPUT_STRIP_TRAILING_WHITESPACE
)

# Find compilers via xcrun
execute_process(
    COMMAND xcrun --sdk macosx --find clang
    OUTPUT_VARIABLE CMAKE_C_COMPILER
    OUTPUT_STRIP_TRAILING_WHITESPACE
)
execute_process(
    COMMAND xcrun --sdk macosx --find clang++
    OUTPUT_VARIABLE CMAKE_CXX_COMPILER
    OUTPUT_STRIP_TRAILING_WHITESPACE
)

# Standard C++ settings
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Build type defaults
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release)
endif()

# Position independent code for static libraries
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# Set platform identifier for conditionals
set(PLATFORM_MACOS ON)
