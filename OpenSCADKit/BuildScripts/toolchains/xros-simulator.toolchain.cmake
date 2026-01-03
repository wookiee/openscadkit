# CMake Toolchain for visionOS Simulator (arm64)
#
# Usage: cmake -DCMAKE_TOOLCHAIN_FILE=xros-simulator.toolchain.cmake ..

set(CMAKE_SYSTEM_NAME visionOS)
set(CMAKE_SYSTEM_PROCESSOR arm64)
set(CMAKE_OSX_ARCHITECTURES arm64)

# Deployment target - use FORCE to override OpenSCAD's default
set(CMAKE_OSX_DEPLOYMENT_TARGET "2.0" CACHE STRING "Minimum visionOS version" FORCE)

# Compiler target
set(CMAKE_C_COMPILER_TARGET arm64-apple-xros-simulator)
set(CMAKE_CXX_COMPILER_TARGET arm64-apple-xros-simulator)

# Find Xcode SDK
execute_process(
    COMMAND xcrun --sdk xrsimulator --show-sdk-path
    OUTPUT_VARIABLE CMAKE_OSX_SYSROOT
    OUTPUT_STRIP_TRAILING_WHITESPACE
)

# Find compilers via xcrun
execute_process(
    COMMAND xcrun --sdk xrsimulator --find clang
    OUTPUT_VARIABLE CMAKE_C_COMPILER
    OUTPUT_STRIP_TRAILING_WHITESPACE
)
execute_process(
    COMMAND xcrun --sdk xrsimulator --find clang++
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
set(PLATFORM_VISIONOS ON)
set(PLATFORM_VISIONOS_SIMULATOR ON)
