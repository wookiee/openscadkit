//
//  SCSRenderer.swift
//  OpenSCADMetal
//
//  Implementation of the SCS (Sequenced Convex Subtraction) algorithm for Metal.
//  Based on OpenCSG's renderSCS.cpp implementation.
//
//  The SCS algorithm is faster than Goldfeather but only works correctly
//  for convex primitives (convexity == 1).
//

import Metal
import CoreGraphics
import simd

/// SCS (Sequenced Convex Subtraction) CSG rendering algorithm.
///
/// Algorithm overview:
/// 1. Initialize depth buffer to far plane
/// 2. For intersection primitives: render front faces, update depth where z < current
/// 3. For subtraction primitives: render back faces, update depth where z > current
/// 4. Final pass: render with depth == computed result to get visible surfaces
///
/// Reference: OpenCSG/src/renderSCS.cpp
class SCSRenderer {

    // MARK: - Properties

    private let device: MTLDevice
    private let pipelineManager: CSGPipelineManager

    // Offscreen render targets for multi-pass rendering
    private var depthTexture: MTLTexture?
    private var colorTexture: MTLTexture?
    private var currentSize: CGSize = .zero

    // MARK: - Initialization

    init(device: MTLDevice, pipelineManager: CSGPipelineManager) {
        self.device = device
        self.pipelineManager = pipelineManager
    }

    // MARK: - Render Target Management

    func ensureRenderTargets(size: CGSize, colorFormat: MTLPixelFormat, depthFormat: MTLPixelFormat) {
        guard size != currentSize else { return }
        currentSize = size

        let width = Int(size.width)
        let height = Int(size.height)

        // Create depth texture
        let depthDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: depthFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        depthDescriptor.usage = [.renderTarget, .shaderRead]
        depthDescriptor.storageMode = .private
        depthTexture = device.makeTexture(descriptor: depthDescriptor)
        depthTexture?.label = "SCS Depth Texture"

        // Create color texture (for ID buffer technique)
        let colorDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: colorFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        colorDescriptor.usage = [.renderTarget, .shaderRead]
        colorDescriptor.storageMode = .private
        colorTexture = device.makeTexture(descriptor: colorDescriptor)
        colorTexture?.label = "SCS Color Texture"
    }

    // MARK: - SCS Rendering

    /// Render primitives using SCS algorithm.
    ///
    /// This implements a simplified SCS that works for the common case of
    /// convex primitives with intersection and subtraction operations.
    ///
    /// - Parameters:
    ///   - encoder: The render command encoder
    ///   - primitives: CSG primitives to render
    ///   - uniforms: Transform matrices
    ///   - depthPipeline: Pipeline for depth-only pass
    ///   - shadingPipeline: Pipeline for final shading
    func render(
        encoder: MTLRenderCommandEncoder,
        primitives: [CSGPrimitive],
        uniformBuffer: MTLBuffer,
        materialBuffer: MTLBuffer,
        depthPipeline: MTLRenderPipelineState,
        shadingPipeline: MTLRenderPipelineState,
        depthStates: DepthStates
    ) {
        guard !primitives.isEmpty else { return }

        // Separate primitives by operation
        let intersections = primitives.filter { $0.operation == .intersection }
        let subtractions = primitives.filter { $0.operation == .subtraction }

        // === Phase 1: CSG Depth Computation ===
        renderCSGDepth(
            encoder: encoder,
            intersections: intersections,
            subtractions: subtractions,
            uniformBuffer: uniformBuffer,
            depthPipeline: depthPipeline,
            depthStates: depthStates
        )

        // === Phase 2: Shading Pass ===
        renderShading(
            encoder: encoder,
            primitives: primitives,
            uniformBuffer: uniformBuffer,
            materialBuffer: materialBuffer,
            shadingPipeline: shadingPipeline,
            depthStates: depthStates
        )
    }

    // MARK: - CSG Depth Pass

    private func renderCSGDepth(
        encoder: MTLRenderCommandEncoder,
        intersections: [CSGPrimitive],
        subtractions: [CSGPrimitive],
        uniformBuffer: MTLBuffer,
        depthPipeline: MTLRenderPipelineState,
        depthStates: DepthStates
    ) {
        encoder.pushDebugGroup("SCS Depth Pass")
        encoder.setRenderPipelineState(depthPipeline)
        encoder.setVertexBuffer(uniformBuffer, offset: 0, index: 1)

        // Step 1: Render all intersection primitives
        // Front faces only, depth less - establishes base CSG surface
        if !intersections.isEmpty {
            encoder.pushDebugGroup("Intersections")
            encoder.setCullMode(.back)
            encoder.setDepthStencilState(depthStates.depthLessWrite)

            for primitive in intersections {
                drawPrimitive(primitive, encoder: encoder)
            }
            encoder.popDebugGroup()
        }

        // Step 2: Render all subtraction primitives
        // Back faces only, depth greater - carves out subtracted regions
        if !subtractions.isEmpty {
            encoder.pushDebugGroup("Subtractions")
            encoder.setCullMode(.front)
            encoder.setDepthStencilState(depthStates.depthGreaterWrite)

            for primitive in subtractions {
                drawPrimitive(primitive, encoder: encoder)
            }
            encoder.popDebugGroup()
        }

        encoder.popDebugGroup()
    }

    // MARK: - Shading Pass

    private func renderShading(
        encoder: MTLRenderCommandEncoder,
        primitives: [CSGPrimitive],
        uniformBuffer: MTLBuffer,
        materialBuffer: MTLBuffer,
        shadingPipeline: MTLRenderPipelineState,
        depthStates: DepthStates
    ) {
        encoder.pushDebugGroup("SCS Shading Pass")
        encoder.setRenderPipelineState(shadingPipeline)
        encoder.setCullMode(.back)
        encoder.setDepthStencilState(depthStates.depthEqualNoWrite)

        encoder.setVertexBuffer(uniformBuffer, offset: 0, index: 1)
        encoder.setFragmentBuffer(materialBuffer, offset: 0, index: 2)

        // Render all primitives - only fragments at CSG-computed depth will pass
        for primitive in primitives {
            drawPrimitive(primitive, encoder: encoder)
        }

        encoder.popDebugGroup()
    }

    // MARK: - Primitive Drawing

    private func drawPrimitive(_ primitive: CSGPrimitive, encoder: MTLRenderCommandEncoder) {
        encoder.setVertexBuffer(primitive.vertexBuffer, offset: 0, index: 0)
        encoder.drawIndexedPrimitives(
            type: .triangle,
            indexCount: primitive.indexCount,
            indexType: .uint32,
            indexBuffer: primitive.indexBuffer,
            indexBufferOffset: 0
        )
    }
}

// MARK: - Depth States Container

/// Container for commonly-used depth-stencil states
struct DepthStates {
    let depthLessWrite: MTLDepthStencilState
    let depthGreaterWrite: MTLDepthStencilState
    let depthEqualNoWrite: MTLDepthStencilState

    init(pipelineManager: CSGPipelineManager) {
        self.depthLessWrite = pipelineManager.depthLessWriteState
        self.depthGreaterWrite = pipelineManager.depthGreaterWriteState
        self.depthEqualNoWrite = pipelineManager.depthEqualNoWriteState
    }
}

// MARK: - SCS with ID Buffer (Advanced)

extension SCSRenderer {
    /// Advanced SCS using ID buffer technique.
    ///
    /// This technique encodes primitive IDs in a color texture, allowing
    /// more complex CSG operations and proper handling of overlapping primitives.
    ///
    /// Based on OpenCSG's SCSChannelManager approach.
    func renderWithIDBuffer(
        commandBuffer: MTLCommandBuffer,
        primitives: [CSGPrimitive],
        uniformBuffer: MTLBuffer,
        colorFormat: MTLPixelFormat,
        depthFormat: MTLPixelFormat,
        viewportSize: CGSize
    ) {
        // Ensure we have render targets
        ensureRenderTargets(size: viewportSize, colorFormat: colorFormat, depthFormat: depthFormat)

        // TODO: Implement ID buffer technique for complex CSG
        // This would involve:
        // 1. Render each primitive with unique ID color
        // 2. Use stencil to track depth layers
        // 3. Merge results based on CSG operations
    }
}
