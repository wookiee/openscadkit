# CMake Toolchain for iOS Simulator (arm64 + x86_64)
#
# Usage: cmake -DCMAKE_TOOLCHAIN_FILE=ios-simulator.toolchain.cmake ..
# For specific arch: cmake -DCMAKE_TOOLCHAIN_FILE=... -DCMAKE_OSX_ARCHITECTURES=arm64 ..

set(CMAKE_SYSTEM_NAME iOS)

# Default to arm64 for Apple Silicon Macs, can override with -DCMAKE_OSX_ARCHITECTURES
if(NOT CMAKE_OSX_ARCHITECTURES)
    set(CMAKE_OSX_ARCHITECTURES "arm64" CACHE STRING "Build architectures")
endif()

# Deployment target - use FORCE to prevent project CMakeLists from overriding
set(CMAKE_OSX_DEPLOYMENT_TARGET "18.0" CACHE STRING "Minimum iOS version" FORCE)

# Find Xcode SDK
execute_process(
    COMMAND xcrun --sdk iphonesimulator --show-sdk-path
    OUTPUT_VARIABLE CMAKE_OSX_SYSROOT
    OUTPUT_STRIP_TRAILING_WHITESPACE
)

# Find compilers via xcrun
execute_process(
    COMMAND xcrun --sdk iphonesimulator --find clang
    OUTPUT_VARIABLE CMAKE_C_COMPILER
    OUTPUT_STRIP_TRAILING_WHITESPACE
)
execute_process(
    COMMAND xcrun --sdk iphonesimulator --find clang++
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

# For cross-compilation, skip trying to run executables
set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)

# Don't search system paths
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)

# Set platform identifier for conditionals
set(PLATFORM_IOS ON)
set(PLATFORM_IOS_SIMULATOR ON)
