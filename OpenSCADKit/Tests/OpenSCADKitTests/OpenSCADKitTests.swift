//
//  OpenSCADKitTests.swift
//  OpenSCADKit
//
//  Tests for the OpenSCADKit Swift API.
//

import Testing
@testable import OpenSCADKit

@Suite(.serialized)  // OpenSCAD internals are not thread-safe
struct OpenSCADKitTests {

    @Test func engineCanBeCreated() async {
        let engine = OpenSCADEngine()
        #expect(engine != nil)
    }

    @Test func versionReturnsString() {
        let version = OpenSCADEngine.version()
        #expect(!version.isEmpty)
        #expect(version.contains("OpenSCAD"))
    }

    @Test func initializeEngine() async throws {
        let engine = OpenSCADEngine()
        try await engine.initialize()
        // Should not throw
    }

    @Test func renderResultProperties() {
        let result = RenderResult(
            success: true,
            errorMessage: nil,
            consoleOutput: "test output",
            vertexCount: 8,
            triangleCount: 12,
            positions: [Float](repeating: 0, count: 24),
            normals: [Float](repeating: 0, count: 24),
            indices: [UInt32](repeating: 0, count: 36)
        )

        #expect(result.success == true)
        #expect(result.errorMessage == nil)
        #expect(result.consoleOutput == "test output")
        #expect(result.vertexCount == 8)
        #expect(result.triangleCount == 12)
        #expect(result.positions.count == 24)
        #expect(result.normals.count == 24)
        #expect(result.indices.count == 36)
    }

    @Test func renderSimpleCube() async throws {
        let engine = OpenSCADEngine()
        let result = try await engine.render(source: "cube([1, 1, 1]);")

        #expect(result.success == true)
        #expect(result.errorMessage == nil)
        #expect(result.vertexCount == 8)  // Cube has 8 vertices
        #expect(result.triangleCount == 12)  // Cube has 12 triangles (6 faces × 2)
    }

    @Test func renderSphere() async throws {
        let engine = OpenSCADEngine()
        let result = try await engine.render(source: "sphere(r=1, $fn=16);")

        #expect(result.success == true)
        #expect(result.vertexCount > 0)
        #expect(result.triangleCount > 0)
    }

    @Test func renderInvalidSource() async throws {
        let engine = OpenSCADEngine()
        let result = try await engine.render(source: "this is not valid scad code {{{")

        #expect(result.success == false)
        // Should have error message or empty geometry
    }
}
