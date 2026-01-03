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
        // Public Swift API for OpenSCAD rendering
        .library(
            name: "OpenSCADKit",
            targets: ["OpenSCADKit"]
        ),
    ],
    targets: [
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
            ]
        ),

        // OpenSCAD XCFramework (pre-built static library)
        // Build with: OpenSCADKit/BuildScripts/build-all.sh && OpenSCADKit/BuildScripts/create-xcframework.sh
        .binaryTarget(
            name: "OpenSCAD",
            path: "Frameworks/OpenSCAD.xcframework"
        ),

        // Public Swift API
        .target(
            name: "OpenSCADKit",
            dependencies: ["COpenSCAD"],
            path: "Sources/OpenSCADKit"
        ),

        // Tests
        .testTarget(
            name: "OpenSCADKitTests",
            dependencies: ["OpenSCADKit"],
            path: "Tests/OpenSCADKitTests"
        ),
    ]
)
