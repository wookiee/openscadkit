//
//  RenderResult.swift
//  OpenSCADKit
//
//  Represents the result of an OpenSCAD render operation.
//

import Foundation

/// The result of rendering OpenSCAD source code.
///
/// Contains the triangle mesh data (positions, normals, indices) along with
/// any console output and error information.
public struct RenderResult: Sendable {
    /// Whether the render completed successfully.
    public let success: Bool

    /// Error message if render failed, nil otherwise.
    public let errorMessage: String?

    /// Console output captured during render (echo statements, warnings).
    public let consoleOutput: String

    /// Number of vertices in the mesh.
    public let vertexCount: Int

    /// Number of triangles in the mesh.
    public let triangleCount: Int

    /// Vertex positions as a flat array of floats (3 per vertex: x, y, z).
    public let positions: [Float]

    /// Vertex normals as a flat array of floats (3 per vertex: nx, ny, nz).
    public let normals: [Float]

    /// Triangle indices as a flat array of UInt32 (3 per triangle).
    public let indices: [UInt32]

    /// Creates a RenderResult with the given data.
    internal init(
        success: Bool,
        errorMessage: String?,
        consoleOutput: String,
        vertexCount: Int,
        triangleCount: Int,
        positions: [Float],
        normals: [Float],
        indices: [UInt32]
    ) {
        self.success = success
        self.errorMessage = errorMessage
        self.consoleOutput = consoleOutput
        self.vertexCount = vertexCount
        self.triangleCount = triangleCount
        self.positions = positions
        self.normals = normals
        self.indices = indices
    }

    /// Creates an empty failed result with an error message.
    internal static func failure(_ message: String) -> RenderResult {
        RenderResult(
            success: false,
            errorMessage: message,
            consoleOutput: "",
            vertexCount: 0,
            triangleCount: 0,
            positions: [],
            normals: [],
            indices: []
        )
    }
}
