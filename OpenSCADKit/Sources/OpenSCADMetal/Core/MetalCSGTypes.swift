//
//  MetalCSGTypes.swift
//  OpenSCADMetal
//
//  Core type definitions for the Metal CSG renderer.
//

import Metal
import simd

// MARK: - CSG Operations

/// CSG operation types matching OpenCSG's Operation enum
enum CSGOperation: Int {
    case intersection = 0
    case subtraction = 1
}

// MARK: - CSG Primitive Protocol

/// Protocol for objects that can be rendered as CSG primitives.
/// Matches the interface expected by OpenCSG's Primitive class.
protocol CSGPrimitive {
    /// The CSG operation this primitive participates in
    var operation: CSGOperation { get }

    /// Convexity of the primitive (1 = convex, >1 = concave with max layers)
    var convexity: UInt { get }

    /// Axis-aligned bounding box for optimization
    var boundingBox: (min: SIMD3<Float>, max: SIMD3<Float>) { get }

    /// Metal vertex buffer containing geometry
    var vertexBuffer: MTLBuffer { get }

    /// Metal index buffer for indexed drawing
    var indexBuffer: MTLBuffer { get }

    /// Number of indices to draw
    var indexCount: Int { get }

    /// Vertex stride in bytes
    var vertexStride: Int { get }
}

// MARK: - Concrete Primitive Implementation

/// Concrete implementation of CSGPrimitive for runtime-created geometry
struct CSGPrimitiveData: CSGPrimitive {
    let operation: CSGOperation
    let convexity: UInt
    let boundingBox: (min: SIMD3<Float>, max: SIMD3<Float>)
    let vertexBuffer: MTLBuffer
    let indexBuffer: MTLBuffer
    let indexCount: Int
    let vertexStride: Int

    init(
        operation: CSGOperation,
        convexity: UInt = 1,
        boundingBox: (min: SIMD3<Float>, max: SIMD3<Float>),
        vertexBuffer: MTLBuffer,
        indexBuffer: MTLBuffer,
        indexCount: Int,
        vertexStride: Int = MemoryLayout<SIMD3<Float>>.stride
    ) {
        self.operation = operation
        self.convexity = convexity
        self.boundingBox = boundingBox
        self.vertexBuffer = vertexBuffer
        self.indexBuffer = indexBuffer
        self.indexCount = indexCount
        self.vertexStride = vertexStride
    }
}

// MARK: - Render Configuration

/// Configuration for a CSG rendering pass
struct CSGRenderConfig {
    var cullMode: MTLCullMode = .back
    var depthCompareFunction: MTLCompareFunction = .less
    var depthWriteEnabled: Bool = true
    var colorWriteMask: MTLColorWriteMask = .all
    var stencilEnabled: Bool = false
    var stencilReferenceValue: UInt32 = 0
}

// MARK: - Uniforms (Swift-side mirror of ShaderTypes.h)

/// Per-frame uniforms matching CSGUniforms in ShaderTypes.h
struct CSGUniforms {
    var modelViewProjectionMatrix: simd_float4x4
    var modelViewMatrix: simd_float4x4
    var normalMatrix: simd_float4x4

    init() {
        modelViewProjectionMatrix = matrix_identity_float4x4
        modelViewMatrix = matrix_identity_float4x4
        normalMatrix = matrix_identity_float4x4
    }

    init(modelMatrix: simd_float4x4, viewMatrix: simd_float4x4, projectionMatrix: simd_float4x4) {
        let modelView = viewMatrix * modelMatrix
        self.modelViewMatrix = modelView
        self.modelViewProjectionMatrix = projectionMatrix * modelView
        self.normalMatrix = simd_inverse(simd_transpose(modelView))
    }
}

/// Material properties matching CSGMaterial in ShaderTypes.h
struct CSGMaterial {
    var baseColor: SIMD4<Float>
    var roughness: Float
    var metallic: Float
    var padding: (Float, Float) = (0, 0)

    init(baseColor: SIMD4<Float> = SIMD4<Float>(0.8, 0.8, 0.8, 1.0),
         roughness: Float = 0.5,
         metallic: Float = 0.0) {
        self.baseColor = baseColor
        self.roughness = roughness
        self.metallic = metallic
    }
}

/// Light properties matching CSGLight in ShaderTypes.h
struct CSGLight {
    var direction: SIMD3<Float>
    var intensity: Float
    var color: SIMD4<Float>

    init(direction: SIMD3<Float> = normalize(SIMD3<Float>(-0.3, -0.5, -1.0)),
         intensity: Float = 1.0,
         color: SIMD4<Float> = SIMD4<Float>(1, 1, 1, 1)) {
        self.direction = direction
        self.intensity = intensity
        self.color = color
    }
}

// MARK: - Algorithm Selection

/// CSG rendering algorithm selection
enum CSGAlgorithm {
    /// SCS algorithm - faster, works for convex primitives only
    case scs
    /// Goldfeather algorithm - handles concave primitives
    case goldfeather
    /// Automatic selection based on primitive convexity
    case automatic
}

// MARK: - Depth Complexity

/// Depth complexity sampling mode (matches OpenCSG)
enum DepthComplexityMode {
    /// No sampling - O(n²) but fast for few objects
    case none
    /// Use occlusion queries for optimization
    case occlusionQuery
    /// Sample depth complexity with stencil buffer
    case stencilSampling
}
