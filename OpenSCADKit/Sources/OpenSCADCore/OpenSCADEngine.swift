//
//  OpenSCADEngine.swift
//  OpenSCADKit
//
//  Swift wrapper for the OpenSCAD C bridge API.
//  Provides async rendering of OpenSCAD source to triangle meshes.
//

import Foundation
import COpenSCAD

/// An actor that manages OpenSCAD rendering operations.
///
/// OpenSCAD's internals are not thread-safe, so all operations are serialized
/// through this actor. Create a single instance and reuse it for all renders.
///
/// ```swift
/// let engine = OpenSCADEngine()
/// let result = try await engine.render(source: "cube([10, 10, 10]);")
/// if result.success {
///     print("Rendered \(result.triangleCount) triangles")
/// }
/// ```
public actor OpenSCADEngine {
    private var isInitialized = false

    /// Creates a new OpenSCAD engine instance.
    public init() {}

    /// Initializes the OpenSCAD engine.
    ///
    /// This is called automatically on first render, but can be called
    /// explicitly for eager initialization.
    ///
    /// - Throws: `OpenSCADError.initializationFailed` if initialization fails.
    public func initialize() throws {
        guard !isInitialized else { return }

        let result = openscad_init()
        if result != 0 {
            throw OpenSCADError.initializationFailed
        }
        isInitialized = true
    }

    /// Renders OpenSCAD source code to a triangle mesh.
    ///
    /// - Parameters:
    ///   - source: The OpenSCAD source code to render.
    ///   - fontsPath: Optional path to a fonts directory.
    /// - Returns: A `RenderResult` containing the mesh data or error information.
    /// - Throws: `OpenSCADError.initializationFailed` if the engine fails to initialize.
    public func render(source: String, fontsPath: String? = nil) async throws -> RenderResult {
        try initialize()

        return await Task.detached(priority: .userInitiated) { [self] in
            await self.performRender(source: source, fontsPath: fontsPath)
        }.value
    }

    /// Performs the actual render operation.
    private func performRender(source: String, fontsPath: String?) -> RenderResult {
        let resultPtr = source.withCString { sourcePtr in
            if let fontsPath = fontsPath {
                return fontsPath.withCString { fontsPtr in
                    openscad_render(sourcePtr, fontsPtr)
                }
            } else {
                return openscad_render(sourcePtr, nil)
            }
        }

        guard let resultPtr = resultPtr else {
            return .failure("Render returned null result")
        }

        defer { openscad_result_free(resultPtr) }

        let success = openscad_result_success(resultPtr)

        // Get error message
        var errorMessage: String? = nil
        if let errorPtr = openscad_result_error(resultPtr) {
            let error = String(cString: errorPtr)
            if !error.isEmpty {
                errorMessage = error
            }
        }

        // Get console output
        var consoleOutput = ""
        if let consolePtr = openscad_result_console(resultPtr) {
            consoleOutput = String(cString: consolePtr)
        }

        // Get mesh data
        let vertexCount = Int(openscad_result_vertex_count(resultPtr))
        let triangleCount = Int(openscad_result_triangle_count(resultPtr))

        var positions: [Float] = []
        var normals: [Float] = []
        var indices: [UInt32] = []

        if vertexCount > 0 {
            if let posPtr = openscad_result_positions(resultPtr) {
                positions = Array(UnsafeBufferPointer(start: posPtr, count: vertexCount * 3))
            }
            if let normPtr = openscad_result_normals(resultPtr) {
                normals = Array(UnsafeBufferPointer(start: normPtr, count: vertexCount * 3))
            }
        }

        if triangleCount > 0 {
            if let idxPtr = openscad_result_indices(resultPtr) {
                indices = Array(UnsafeBufferPointer(start: idxPtr, count: triangleCount * 3))
            }
        }

        return RenderResult(
            success: success,
            errorMessage: errorMessage,
            consoleOutput: consoleOutput,
            vertexCount: vertexCount,
            triangleCount: triangleCount,
            positions: positions,
            normals: normals,
            indices: indices
        )
    }

    /// Cancels any in-progress render operation.
    public func cancel() {
        openscad_cancel()
    }

    /// Returns the OpenSCAD version string.
    public static func version() -> String {
        if let versionPtr = openscad_version() {
            return String(cString: versionPtr)
        }
        return "Unknown"
    }
}

/// Errors that can occur during OpenSCAD operations.
public enum OpenSCADError: Error, LocalizedError {
    case initializationFailed

    public var errorDescription: String? {
        switch self {
        case .initializationFailed:
            return "Failed to initialize OpenSCAD engine"
        }
    }
}
