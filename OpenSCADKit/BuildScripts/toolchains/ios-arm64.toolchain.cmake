# CMake Toolchain for iOS Device (arm64)
#
# Usage: cmake -DCMAKE_TOOLCHAIN_FILE=ios-arm64.toolchain.cmake ..

set(CMAKE_SYSTEM_NAME iOS)
set(CMAKE_SYSTEM_PROCESSOR arm64)
set(CMAKE_OSX_ARCHITECTURES arm64)

# Deployment target - use FORCE to prevent project CMakeLists from overriding
set(CMAKE_OSX_DEPLOYMENT_TARGET "18.0" CACHE STRING "Minimum iOS version" FORCE)

# Find Xcode SDK
execute_process(
    COMMAND xcrun --sdk iphoneos --show-sdk-path
    OUTPUT_VARIABLE CMAKE_OSX_SYSROOT
    OUTPUT_STRIP_TRAILING_WHITESPACE
)

# Compiler settings
set(CMAKE_C_COMPILER_TARGET arm64-apple-ios)
set(CMAKE_CXX_COMPILER_TARGET arm64-apple-ios)

# Find compilers via xcrun
execute_process(
    COMMAND xcrun --sdk iphoneos --find clang
    OUTPUT_VARIABLE CMAKE_C_COMPILER
    OUTPUT_STRIP_TRAILING_WHITESPACE
)
execute_process(
    COMMAND xcrun --sdk iphoneos --find clang++
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

# Disable bitcode (deprecated in Xcode 14+)
set(CMAKE_XCODE_ATTRIBUTE_ENABLE_BITCODE NO)

# For iOS, we need to tell CMake this is for a device, not simulator
# and to skip trying to run executables
set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)

# Don't search system paths
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)

# Set platform identifier for conditionals
set(PLATFORM_IOS ON)
set(PLATFORM_IOS_DEVICE ON)
