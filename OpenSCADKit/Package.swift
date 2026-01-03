// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "OpenSCADKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .visionOS(.v1)
    ],
    products: [
        // === Individual Modules ===

        // Core engine: SCAD parsing, rendering, mesh data
        .library(
            name: "OpenSCADCore",
            targets: ["OpenSCADCore"]
        ),

        // Metal rendering: CSG preview, mesh display
        .library(
            name: "OpenSCADMetal",
            targets: ["OpenSCADMetal"]
        ),

        // === Umbrella Module ===

        // Full framework: includes Core + Metal
        // Use this for convenience; `import OpenSCADKit` gives you everything
        .library(
            name: "OpenSCADKit",
            targets: ["OpenSCADKit"]
        ),
    ],
    targets: [
        // === Binary Target ===

        // OpenSCAD XCFramework (pre-built static library)
        // Build with: BuildScripts/build-all.sh && BuildScripts/create-xcframework.sh
        .binaryTarget(
            name: "OpenSCAD",
            path: "Frameworks/OpenSCAD.xcframework"
        ),

        // === C Bridge ===

        // C bridge layer - wraps the C API from the XCFramework
        .target(
            name: "COpenSCAD",
            dependencies: ["OpenSCAD"],
            path: "Sources/COpenSCAD",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedLibrary("z"),
                .linkedLibrary("xml2"),
                .linkedLibrary("c++"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("ImageIO"),
            ]
        ),

        // === OpenSCADCore ===

        // Core engine: OpenSCADEngine, RenderResult, Mesh types
        .target(
            name: "OpenSCADCore",
            dependencies: ["COpenSCAD"],
            path: "Sources/OpenSCADCore"
        ),

        // === OpenSCADMetal ===

        // Metal rendering: CSG preview, mesh visualization
        .target(
            name: "OpenSCADMetal",
            dependencies: ["OpenSCADCore"],
            path: "Sources/OpenSCADMetal",
            resources: [
                .process("Shaders")
            ]
        ),

        // === Umbrella Module ===

        // Re-exports OpenSCADCore and OpenSCADMetal
        .target(
            name: "OpenSCADKit",
            dependencies: ["OpenSCADCore", "OpenSCADMetal"],
            path: "Sources/OpenSCADKit"
        ),

        // === Tests ===

        .testTarget(
            name: "OpenSCADCoreTests",
            dependencies: ["OpenSCADCore"],
            path: "Tests/OpenSCADCoreTests"
        ),
    ]
)
