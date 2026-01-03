//
//  CSGPrimitiveGenerators.swift
//  OpenSCADMetal
//
//  Generates Metal buffers for basic CSG primitives (cube, sphere, cylinder).
//  Used for testing and for Swift-side primitive creation.
//

import Metal
import simd

/// Factory for creating CSG primitive geometry
class CSGPrimitiveFactory {

    private let device: MTLDevice

    init(device: MTLDevice) {
        self.device = device
    }

    // MARK: - Cube

    /// Create a unit cube centered at origin
    func makeCube(
        size: SIMD3<Float> = SIMD3<Float>(1, 1, 1),
        center: SIMD3<Float> = .zero,
        operation: CSGOperation = .intersection
    ) -> CSGPrimitiveData? {
        let halfSize = size / 2

        // 8 vertices of the cube
        let vertices: [SIMD3<Float>] = [
            // Front face
            center + SIMD3<Float>(-halfSize.x, -halfSize.y,  halfSize.z),
            center + SIMD3<Float>( halfSize.x, -halfSize.y,  halfSize.z),
            center + SIMD3<Float>( halfSize.x,  halfSize.y,  halfSize.z),
            center + SIMD3<Float>(-halfSize.x,  halfSize.y,  halfSize.z),
            // Back face
            center + SIMD3<Float>(-halfSize.x, -halfSize.y, -halfSize.z),
            center + SIMD3<Float>( halfSize.x, -halfSize.y, -halfSize.z),
            center + SIMD3<Float>( halfSize.x,  halfSize.y, -halfSize.z),
            center + SIMD3<Float>(-halfSize.x,  halfSize.y, -halfSize.z),
        ]

        // 12 triangles (2 per face)
        let indices: [UInt32] = [
            // Front
            0, 1, 2, 0, 2, 3,
            // Right
            1, 5, 6, 1, 6, 2,
            // Back
            5, 4, 7, 5, 7, 6,
            // Left
            4, 0, 3, 4, 3, 7,
            // Top
            3, 2, 6, 3, 6, 7,
            // Bottom
            4, 5, 1, 4, 1, 0
        ]

        // Generate normals (flat shading - one normal per triangle vertex)
        var shadingVertices: [(position: SIMD3<Float>, normal: SIMD3<Float>)] = []

        for i in stride(from: 0, to: indices.count, by: 3) {
            let v0 = vertices[Int(indices[i])]
            let v1 = vertices[Int(indices[i + 1])]
            let v2 = vertices[Int(indices[i + 2])]

            let edge1 = v1 - v0
            let edge2 = v2 - v0
            let normal = normalize(cross(edge1, edge2))

            shadingVertices.append((v0, normal))
            shadingVertices.append((v1, normal))
            shadingVertices.append((v2, normal))
        }

        return createPrimitive(
            vertices: shadingVertices,
            operation: operation,
            convexity: 1,
            boundingBox: (min: center - halfSize, max: center + halfSize)
        )
    }

    // MARK: - Sphere

    /// Create a sphere centered at origin
    func makeSphere(
        radius: Float = 0.5,
        center: SIMD3<Float> = .zero,
        segments: Int = 32,
        rings: Int = 16,
        operation: CSGOperation = .intersection
    ) -> CSGPrimitiveData? {
        var vertices: [(position: SIMD3<Float>, normal: SIMD3<Float>)] = []

        for ring in 0..<rings {
            let theta1 = Float(ring) / Float(rings) * .pi
            let theta2 = Float(ring + 1) / Float(rings) * .pi

            for segment in 0..<segments {
                let phi1 = Float(segment) / Float(segments) * 2 * .pi
                let phi2 = Float(segment + 1) / Float(segments) * 2 * .pi

                // Four corners of the quad
                let p1 = spherePoint(radius: radius, theta: theta1, phi: phi1) + center
                let p2 = spherePoint(radius: radius, theta: theta1, phi: phi2) + center
                let p3 = spherePoint(radius: radius, theta: theta2, phi: phi2) + center
                let p4 = spherePoint(radius: radius, theta: theta2, phi: phi1) + center

                // Normals (same as position for unit sphere)
                let n1 = normalize(p1 - center)
                let n2 = normalize(p2 - center)
                let n3 = normalize(p3 - center)
                let n4 = normalize(p4 - center)

                // Two triangles per quad
                vertices.append((p1, n1))
                vertices.append((p2, n2))
                vertices.append((p3, n3))

                vertices.append((p1, n1))
                vertices.append((p3, n3))
                vertices.append((p4, n4))
            }
        }

        return createPrimitive(
            vertices: vertices,
            operation: operation,
            convexity: 1,
            boundingBox: (
                min: center - SIMD3<Float>(repeating: radius),
                max: center + SIMD3<Float>(repeating: radius)
            )
        )
    }

    private func spherePoint(radius: Float, theta: Float, phi: Float) -> SIMD3<Float> {
        let sinTheta = sin(theta)
        return SIMD3<Float>(
            radius * sinTheta * cos(phi),
            radius * cos(theta),
            radius * sinTheta * sin(phi)
        )
    }

    // MARK: - Cylinder

    /// Create a cylinder along the Z axis
    func makeCylinder(
        radius: Float = 0.5,
        height: Float = 1.0,
        center: SIMD3<Float> = .zero,
        segments: Int = 32,
        operation: CSGOperation = .intersection
    ) -> CSGPrimitiveData? {
        var vertices: [(position: SIMD3<Float>, normal: SIMD3<Float>)] = []

        let halfHeight = height / 2

        for segment in 0..<segments {
            let phi1 = Float(segment) / Float(segments) * 2 * .pi
            let phi2 = Float(segment + 1) / Float(segments) * 2 * .pi

            let x1 = radius * cos(phi1)
            let z1 = radius * sin(phi1)
            let x2 = radius * cos(phi2)
            let z2 = radius * sin(phi2)

            // Side face
            let p1 = center + SIMD3<Float>(x1, -halfHeight, z1)
            let p2 = center + SIMD3<Float>(x2, -halfHeight, z2)
            let p3 = center + SIMD3<Float>(x2,  halfHeight, z2)
            let p4 = center + SIMD3<Float>(x1,  halfHeight, z1)

            let n1 = normalize(SIMD3<Float>(x1, 0, z1))
            let n2 = normalize(SIMD3<Float>(x2, 0, z2))

            vertices.append((p1, n1))
            vertices.append((p2, n2))
            vertices.append((p3, n2))

            vertices.append((p1, n1))
            vertices.append((p3, n2))
            vertices.append((p4, n1))

            // Top cap
            let topCenter = center + SIMD3<Float>(0, halfHeight, 0)
            let topNormal = SIMD3<Float>(0, 1, 0)
            vertices.append((topCenter, topNormal))
            vertices.append((p4, topNormal))
            vertices.append((p3, topNormal))

            // Bottom cap
            let bottomCenter = center + SIMD3<Float>(0, -halfHeight, 0)
            let bottomNormal = SIMD3<Float>(0, -1, 0)
            vertices.append((bottomCenter, bottomNormal))
            vertices.append((p2, bottomNormal))
            vertices.append((p1, bottomNormal))
        }

        return createPrimitive(
            vertices: vertices,
            operation: operation,
            convexity: 1,
            boundingBox: (
                min: center + SIMD3<Float>(-radius, -halfHeight, -radius),
                max: center + SIMD3<Float>(radius, halfHeight, radius)
            )
        )
    }

    // MARK: - Helper Methods

    private func createPrimitive(
        vertices: [(position: SIMD3<Float>, normal: SIMD3<Float>)],
        operation: CSGOperation,
        convexity: UInt,
        boundingBox: (min: SIMD3<Float>, max: SIMD3<Float>)
    ) -> CSGPrimitiveData? {
        // Interleave position and normal data
        var vertexData: [Float] = []
        for vertex in vertices {
            vertexData.append(vertex.position.x)
            vertexData.append(vertex.position.y)
            vertexData.append(vertex.position.z)
            vertexData.append(vertex.normal.x)
            vertexData.append(vertex.normal.y)
            vertexData.append(vertex.normal.z)
        }

        // Create vertex buffer
        guard let vertexBuffer = device.makeBuffer(
            bytes: vertexData,
            length: vertexData.count * MemoryLayout<Float>.stride,
            options: .storageModeShared
        ) else {
            return nil
        }
        vertexBuffer.label = "CSG Primitive Vertices"

        // Create sequential index buffer
        var indices: [UInt32] = []
        for i in 0..<vertices.count {
            indices.append(UInt32(i))
        }

        guard let indexBuffer = device.makeBuffer(
            bytes: indices,
            length: indices.count * MemoryLayout<UInt32>.stride,
            options: .storageModeShared
        ) else {
            return nil
        }
        indexBuffer.label = "CSG Primitive Indices"

        return CSGPrimitiveData(
            operation: operation,
            convexity: convexity,
            boundingBox: boundingBox,
            vertexBuffer: vertexBuffer,
            indexBuffer: indexBuffer,
            indexCount: indices.count,
            vertexStride: MemoryLayout<Float>.stride * 6 // position + normal
        )
    }
}

// MARK: - Demo Scene

extension CSGPrimitiveFactory {
    /// Create a demo scene with a cube minus a sphere
    func makeDemoScene() -> [CSGPrimitive] {
        var primitives: [CSGPrimitive] = []

        // Base cube
        if let cube = makeCube(
            size: SIMD3<Float>(1.5, 1.5, 1.5),
            center: .zero,
            operation: .intersection
        ) {
            primitives.append(cube)
        }

        // Subtracted sphere
        if let sphere = makeSphere(
            radius: 0.9,
            center: .zero,
            segments: 32,
            rings: 16,
            operation: .subtraction
        ) {
            primitives.append(sphere)
        }

        return primitives
    }
}
