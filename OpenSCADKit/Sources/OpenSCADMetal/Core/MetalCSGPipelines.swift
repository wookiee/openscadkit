//
//  MetalCSGPipelines.swift
//  OpenSCADMetal
//
//  Manages Metal pipeline states for CSG rendering.
//  Caches pipeline states for different rendering configurations.
//

import Metal
import MetalKit

/// Manages Metal render pipeline states for CSG operations.
/// Provides cached pipeline states for depth pass, shading pass, and stencil operations.
class CSGPipelineManager {

    // MARK: - Properties

    private let device: MTLDevice
    private let library: MTLLibrary

    // Cached pipeline states
    private var depthPipelineStates: [PipelineKey: MTLRenderPipelineState] = [:]
    private var shadingPipelineStates: [PipelineKey: MTLRenderPipelineState] = [:]

    // Cached depth-stencil states
    private var depthStencilStates: [DepthStencilKey: MTLDepthStencilState] = [:]

    // Vertex descriptors
    private(set) var depthVertexDescriptor: MTLVertexDescriptor!
    private(set) var shadingVertexDescriptor: MTLVertexDescriptor!

    // MARK: - Pipeline Key Types

    struct PipelineKey: Hashable {
        let colorPixelFormat: MTLPixelFormat
        let depthPixelFormat: MTLPixelFormat
        let stencilPixelFormat: MTLPixelFormat
        let sampleCount: Int
    }

    struct DepthStencilKey: Hashable {
        let depthCompareFunction: MTLCompareFunction
        let depthWriteEnabled: Bool
        let stencilEnabled: Bool
        let stencilOperation: StencilConfig

        struct StencilConfig: Hashable {
            let readMask: UInt32
            let writeMask: UInt32
            let compareFunction: MTLCompareFunction
            let stencilFailure: MTLStencilOperation
            let depthFailure: MTLStencilOperation
            let depthStencilPass: MTLStencilOperation

            static let disabled = StencilConfig(
                readMask: 0,
                writeMask: 0,
                compareFunction: .always,
                stencilFailure: .keep,
                depthFailure: .keep,
                depthStencilPass: .keep
            )
        }
    }

    // MARK: - Initialization

    init(device: MTLDevice) throws {
        self.device = device

        // Load the shader library
        guard let library = device.makeDefaultLibrary() else {
            throw CSGPipelineError.shaderLibraryNotFound
        }
        self.library = library

        setupVertexDescriptors()
    }

    private func setupVertexDescriptors() {
        // Vertex layout: 6 floats per vertex (position xyz + normal xyz)
        // position: bytes 0-11 (3 floats)
        // normal: bytes 12-23 (3 floats)
        // Total stride: 24 bytes

        let floatSize = MemoryLayout<Float>.stride  // 4 bytes
        let stride = floatSize * 6  // 24 bytes: 6 floats per vertex

        // Depth pass vertex descriptor (reads position only, but stride matches full layout)
        depthVertexDescriptor = MTLVertexDescriptor()
        depthVertexDescriptor.attributes[0].format = .float3
        depthVertexDescriptor.attributes[0].offset = 0
        depthVertexDescriptor.attributes[0].bufferIndex = 0
        depthVertexDescriptor.layouts[0].stride = stride
        depthVertexDescriptor.layouts[0].stepFunction = .perVertex

        // Shading pass vertex descriptor (position + normal)
        shadingVertexDescriptor = MTLVertexDescriptor()
        // Position at offset 0
        shadingVertexDescriptor.attributes[0].format = .float3
        shadingVertexDescriptor.attributes[0].offset = 0
        shadingVertexDescriptor.attributes[0].bufferIndex = 0
        // Normal at offset 12 (after 3 floats)
        shadingVertexDescriptor.attributes[1].format = .float3
        shadingVertexDescriptor.attributes[1].offset = floatSize * 3  // 12 bytes
        shadingVertexDescriptor.attributes[1].bufferIndex = 0
        // Layout
        shadingVertexDescriptor.layouts[0].stride = stride
        shadingVertexDescriptor.layouts[0].stepFunction = .perVertex
    }

    // MARK: - Pipeline State Creation

    /// Get or create a depth-only pipeline state for CSG computation
    func depthPipelineState(
        colorPixelFormat: MTLPixelFormat,
        depthPixelFormat: MTLPixelFormat,
        stencilPixelFormat: MTLPixelFormat = .invalid,
        sampleCount: Int = 1
    ) throws -> MTLRenderPipelineState {
        let key = PipelineKey(
            colorPixelFormat: colorPixelFormat,
            depthPixelFormat: depthPixelFormat,
            stencilPixelFormat: stencilPixelFormat,
            sampleCount: sampleCount
        )

        if let cached = depthPipelineStates[key] {
            return cached
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "CSG Depth Pipeline"

        // Load shaders
        guard let vertexFunction = library.makeFunction(name: "csg_depth_vertex"),
              let fragmentFunction = library.makeFunction(name: "csg_depth_fragment") else {
            throw CSGPipelineError.shaderFunctionNotFound
        }

        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.vertexDescriptor = depthVertexDescriptor

        // Color attachment - disabled for depth-only pass
        descriptor.colorAttachments[0].pixelFormat = colorPixelFormat
        descriptor.colorAttachments[0].writeMask = [] // Don't write color

        descriptor.depthAttachmentPixelFormat = depthPixelFormat
        descriptor.stencilAttachmentPixelFormat = stencilPixelFormat
        descriptor.rasterSampleCount = sampleCount

        let state = try device.makeRenderPipelineState(descriptor: descriptor)
        depthPipelineStates[key] = state
        return state
    }

    /// Get or create a shading pipeline state for final color pass
    func shadingPipelineState(
        colorPixelFormat: MTLPixelFormat,
        depthPixelFormat: MTLPixelFormat,
        stencilPixelFormat: MTLPixelFormat = .invalid,
        sampleCount: Int = 1
    ) throws -> MTLRenderPipelineState {
        let key = PipelineKey(
            colorPixelFormat: colorPixelFormat,
            depthPixelFormat: depthPixelFormat,
            stencilPixelFormat: stencilPixelFormat,
            sampleCount: sampleCount
        )

        if let cached = shadingPipelineStates[key] {
            return cached
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "CSG Shading Pipeline"

        // Load shaders
        guard let vertexFunction = library.makeFunction(name: "csg_shading_vertex"),
              let fragmentFunction = library.makeFunction(name: "csg_flat_fragment") else {
            throw CSGPipelineError.shaderFunctionNotFound
        }

        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.vertexDescriptor = shadingVertexDescriptor

        // Color attachment - enabled for shading pass
        descriptor.colorAttachments[0].pixelFormat = colorPixelFormat
        descriptor.colorAttachments[0].writeMask = .all

        // Enable alpha blending
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].rgbBlendOperation = .add
        descriptor.colorAttachments[0].alphaBlendOperation = .add
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        descriptor.depthAttachmentPixelFormat = depthPixelFormat
        descriptor.stencilAttachmentPixelFormat = stencilPixelFormat
        descriptor.rasterSampleCount = sampleCount

        let state = try device.makeRenderPipelineState(descriptor: descriptor)
        shadingPipelineStates[key] = state
        return state
    }

    // MARK: - Depth-Stencil State Creation

    /// Get or create a depth-stencil state
    func depthStencilState(
        depthCompareFunction: MTLCompareFunction,
        depthWriteEnabled: Bool,
        stencilConfig: DepthStencilKey.StencilConfig = .disabled
    ) -> MTLDepthStencilState {
        let key = DepthStencilKey(
            depthCompareFunction: depthCompareFunction,
            depthWriteEnabled: depthWriteEnabled,
            stencilEnabled: stencilConfig.writeMask != 0 || stencilConfig.readMask != 0,
            stencilOperation: stencilConfig
        )

        if let cached = depthStencilStates[key] {
            return cached
        }

        let descriptor = MTLDepthStencilDescriptor()
        descriptor.depthCompareFunction = depthCompareFunction
        descriptor.isDepthWriteEnabled = depthWriteEnabled

        if key.stencilEnabled {
            let stencilDescriptor = MTLStencilDescriptor()
            stencilDescriptor.readMask = stencilConfig.readMask
            stencilDescriptor.writeMask = stencilConfig.writeMask
            stencilDescriptor.stencilCompareFunction = stencilConfig.compareFunction
            stencilDescriptor.stencilFailureOperation = stencilConfig.stencilFailure
            stencilDescriptor.depthFailureOperation = stencilConfig.depthFailure
            stencilDescriptor.depthStencilPassOperation = stencilConfig.depthStencilPass

            descriptor.frontFaceStencil = stencilDescriptor
            descriptor.backFaceStencil = stencilDescriptor
        }

        let state = device.makeDepthStencilState(descriptor: descriptor)!
        depthStencilStates[key] = state
        return state
    }

    // MARK: - Convenience Depth-Stencil States

    /// Depth-only state: write depth, compare less
    var depthLessWriteState: MTLDepthStencilState {
        depthStencilState(depthCompareFunction: .less, depthWriteEnabled: true)
    }

    /// Depth-only state: write depth, compare greater
    var depthGreaterWriteState: MTLDepthStencilState {
        depthStencilState(depthCompareFunction: .greater, depthWriteEnabled: true)
    }

    /// Shading pass state: compare equal, no write
    var depthEqualNoWriteState: MTLDepthStencilState {
        depthStencilState(depthCompareFunction: .equal, depthWriteEnabled: false)
    }

    /// Disabled depth state
    var depthDisabledState: MTLDepthStencilState {
        depthStencilState(depthCompareFunction: .always, depthWriteEnabled: false)
    }

    /// Stencil increment state (for Goldfeather parity counting)
    func stencilIncrementState(depthCompare: MTLCompareFunction) -> MTLDepthStencilState {
        depthStencilState(
            depthCompareFunction: depthCompare,
            depthWriteEnabled: false,
            stencilConfig: .init(
                readMask: 0xFF,
                writeMask: 0xFF,
                compareFunction: .always,
                stencilFailure: .keep,
                depthFailure: .keep,
                depthStencilPass: .incrementClamp
            )
        )
    }

    /// Stencil decrement state (for Goldfeather parity counting)
    func stencilDecrementState(depthCompare: MTLCompareFunction) -> MTLDepthStencilState {
        depthStencilState(
            depthCompareFunction: depthCompare,
            depthWriteEnabled: false,
            stencilConfig: .init(
                readMask: 0xFF,
                writeMask: 0xFF,
                compareFunction: .always,
                stencilFailure: .keep,
                depthFailure: .keep,
                depthStencilPass: .decrementClamp
            )
        )
    }
}

// MARK: - Errors

enum CSGPipelineError: Error {
    case shaderLibraryNotFound
    case shaderFunctionNotFound
    case pipelineCreationFailed(String)
}
