//
//  MetalCSGRenderer.swift
//  OpenSCADMetal
//
//  Main Metal CSG renderer. Manages rendering of CSG primitives using
//  image-based CSG algorithms (SCS and Goldfeather).
//

import Metal
import MetalKit
import simd

/// Main CSG renderer using Metal.
/// Implements OpenCSG-style image-based CSG rendering.
class MetalCSGRenderer: NSObject {

    // MARK: - Properties

    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let pipelineManager: CSGPipelineManager

    // Current render state
    private var primitives: [CSGPrimitive] = []
    private var uniforms = CSGUniforms()
    private var material = CSGMaterial()
    private var light = CSGLight()

    // Uniform buffers
    private var uniformBuffer: MTLBuffer!
    private var materialBuffer: MTLBuffer!
    private var lightBuffer: MTLBuffer!

    // Configuration
    var algorithm: CSGAlgorithm = .automatic
    var backgroundColor: SIMD4<Float> = SIMD4<Float>(0.2, 0.2, 0.25, 1.0)

    /// Set to true to skip CSG and render primitives directly (for debugging)
    var debugDirectRender: Bool = true

    // MARK: - Initialization

    init(device: MTLDevice) throws {
        self.device = device

        guard let commandQueue = device.makeCommandQueue() else {
            throw CSGRendererError.commandQueueCreationFailed
        }
        self.commandQueue = commandQueue

        self.pipelineManager = try CSGPipelineManager(device: device)

        super.init()

        try createBuffers()
    }

    private func createBuffers() throws {
        uniformBuffer = device.makeBuffer(
            length: MemoryLayout<CSGUniforms>.stride,
            options: .storageModeShared
        )
        uniformBuffer.label = "CSG Uniforms"

        materialBuffer = device.makeBuffer(
            length: MemoryLayout<CSGMaterial>.stride,
            options: .storageModeShared
        )
        materialBuffer.label = "CSG Material"

        lightBuffer = device.makeBuffer(
            length: MemoryLayout<CSGLight>.stride,
            options: .storageModeShared
        )
        lightBuffer.label = "CSG Light"

        guard uniformBuffer != nil, materialBuffer != nil, lightBuffer != nil else {
            throw CSGRendererError.bufferCreationFailed
        }
    }

    // MARK: - Primitive Management

    /// Set the primitives to render
    func setPrimitives(_ primitives: [CSGPrimitive]) {
        self.primitives = primitives
    }

    /// Add a primitive to the render list
    func addPrimitive(_ primitive: CSGPrimitive) {
        primitives.append(primitive)
    }

    /// Clear all primitives
    func clearPrimitives() {
        primitives.removeAll()
    }

    // MARK: - Camera/Transform Setup

    /// Update the model-view-projection matrices
    func setTransforms(
        modelMatrix: simd_float4x4 = matrix_identity_float4x4,
        viewMatrix: simd_float4x4,
        projectionMatrix: simd_float4x4
    ) {
        uniforms = CSGUniforms(
            modelMatrix: modelMatrix,
            viewMatrix: viewMatrix,
            projectionMatrix: projectionMatrix
        )
    }

    /// Set material properties
    func setMaterial(_ material: CSGMaterial) {
        self.material = material
    }

    /// Set light properties
    func setLight(_ light: CSGLight) {
        self.light = light
    }

    // MARK: - Rendering

    /// Render the current primitives to the given drawable
    func render(to view: MTKView) {
        guard let drawable = view.currentDrawable,
              let renderPassDescriptor = view.currentRenderPassDescriptor else {
            return
        }

        // Update uniform buffers
        updateBuffers()

        // Create command buffer
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            return
        }
        commandBuffer.label = "CSG Render"

        // Configure render pass
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(
            red: Double(backgroundColor.x),
            green: Double(backgroundColor.y),
            blue: Double(backgroundColor.z),
            alpha: Double(backgroundColor.w)
        )
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].storeAction = .store

        renderPassDescriptor.depthAttachment?.clearDepth = 1.0
        renderPassDescriptor.depthAttachment?.loadAction = .clear
        renderPassDescriptor.depthAttachment?.storeAction = .dontCare

        // Perform CSG rendering
        do {
            try renderCSG(
                commandBuffer: commandBuffer,
                renderPassDescriptor: renderPassDescriptor,
                colorFormat: view.colorPixelFormat,
                depthFormat: view.depthStencilPixelFormat
            )
        } catch {
            print("CSG render error: \(error)")
        }

        // Present
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private func updateBuffers() {
        uniformBuffer.contents().storeBytes(of: uniforms, as: CSGUniforms.self)
        materialBuffer.contents().storeBytes(of: material, as: CSGMaterial.self)
        lightBuffer.contents().storeBytes(of: light, as: CSGLight.self)
    }

    // MARK: - CSG Rendering Implementation

    private func renderCSG(
        commandBuffer: MTLCommandBuffer,
        renderPassDescriptor: MTLRenderPassDescriptor,
        colorFormat: MTLPixelFormat,
        depthFormat: MTLPixelFormat
    ) throws {
        guard !primitives.isEmpty else {
            // No primitives - just clear
            guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
                return
            }
            encoder.endEncoding()
            return
        }

        // Debug mode: skip CSG and render directly
        if debugDirectRender {
            try renderDirect(
                commandBuffer: commandBuffer,
                renderPassDescriptor: renderPassDescriptor,
                colorFormat: colorFormat,
                depthFormat: depthFormat
            )
            return
        }

        // Determine algorithm based on primitive convexity
        let selectedAlgorithm = selectAlgorithm()

        switch selectedAlgorithm {
        case .scs:
            try renderSCS(
                commandBuffer: commandBuffer,
                renderPassDescriptor: renderPassDescriptor,
                colorFormat: colorFormat,
                depthFormat: depthFormat
            )
        case .goldfeather:
            try renderGoldfeather(
                commandBuffer: commandBuffer,
                renderPassDescriptor: renderPassDescriptor,
                colorFormat: colorFormat,
                depthFormat: depthFormat
            )
        case .automatic:
            // Should not reach here - selectAlgorithm returns concrete algorithm
            try renderSCS(
                commandBuffer: commandBuffer,
                renderPassDescriptor: renderPassDescriptor,
                colorFormat: colorFormat,
                depthFormat: depthFormat
            )
        }
    }

    // MARK: - Direct Rendering (Debug)

    /// Simple direct rendering without CSG - for debugging the basic pipeline
    private func renderDirect(
        commandBuffer: MTLCommandBuffer,
        renderPassDescriptor: MTLRenderPassDescriptor,
        colorFormat: MTLPixelFormat,
        depthFormat: MTLPixelFormat
    ) throws {
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            throw CSGRendererError.encoderCreationFailed
        }
        encoder.label = "Direct Render Pass"

        let shadingPipeline = try pipelineManager.shadingPipelineState(
            colorPixelFormat: colorFormat,
            depthPixelFormat: depthFormat
        )

        encoder.setRenderPipelineState(shadingPipeline)
        encoder.setCullMode(.front)  // Cull front faces (our winding is inverted)
        encoder.setDepthStencilState(pipelineManager.depthLessWriteState)

        encoder.setVertexBuffer(uniformBuffer, offset: 0, index: 1)
        encoder.setFragmentBuffer(materialBuffer, offset: 0, index: 2)

        // Debug: print primitive info once
        if primitives.count > 0 && !debugPrintedOnce {
            print("Rendering \(primitives.count) primitives")
            for (i, p) in primitives.enumerated() {
                print("  Primitive \(i): \(p.indexCount) indices, stride=\(p.vertexStride)")
            }
            print("Uniforms MVP diagonal: \(uniforms.modelViewProjectionMatrix.columns.0.x), \(uniforms.modelViewProjectionMatrix.columns.1.y), \(uniforms.modelViewProjectionMatrix.columns.2.z)")
            debugPrintedOnce = true
        }

        // Render all primitives with standard depth testing
        for primitive in primitives {
            encoder.setVertexBuffer(primitive.vertexBuffer, offset: 0, index: 0)
            encoder.drawIndexedPrimitives(
                type: .triangle,
                indexCount: primitive.indexCount,
                indexType: .uint32,
                indexBuffer: primitive.indexBuffer,
                indexBufferOffset: 0
            )
        }

        encoder.endEncoding()
    }

    private var debugPrintedOnce = false

    private func selectAlgorithm() -> CSGAlgorithm {
        switch algorithm {
        case .scs, .goldfeather:
            return algorithm
        case .automatic:
            // Use Goldfeather if any primitive is concave (convexity > 1)
            let hasConcave = primitives.contains { $0.convexity > 1 }
            return hasConcave ? .goldfeather : .scs
        }
    }

    // MARK: - SCS Algorithm

    /// Render using SCS (Sequenced Convex Subtraction) algorithm.
    /// This is simpler and faster but only works correctly for convex primitives.
    private func renderSCS(
        commandBuffer: MTLCommandBuffer,
        renderPassDescriptor: MTLRenderPassDescriptor,
        colorFormat: MTLPixelFormat,
        depthFormat: MTLPixelFormat
    ) throws {
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            throw CSGRendererError.encoderCreationFailed
        }
        encoder.label = "CSG SCS Pass"

        let depthPipeline = try pipelineManager.depthPipelineState(
            colorPixelFormat: colorFormat,
            depthPixelFormat: depthFormat
        )

        let shadingPipeline = try pipelineManager.shadingPipelineState(
            colorPixelFormat: colorFormat,
            depthPixelFormat: depthFormat
        )

        // === Phase 1: CSG Depth Computation ===

        encoder.setRenderPipelineState(depthPipeline)
        encoder.setVertexBuffer(uniformBuffer, offset: 0, index: 1)

        // Step 1: Render intersection primitives (front faces, depth less)
        encoder.setCullMode(.back) // Show front faces
        encoder.setDepthStencilState(pipelineManager.depthLessWriteState)

        for primitive in primitives where primitive.operation == .intersection {
            encoder.setVertexBuffer(primitive.vertexBuffer, offset: 0, index: 0)
            encoder.drawIndexedPrimitives(
                type: .triangle,
                indexCount: primitive.indexCount,
                indexType: .uint32,
                indexBuffer: primitive.indexBuffer,
                indexBufferOffset: 0
            )
        }

        // Step 2: Render subtraction primitives (back faces, depth greater)
        encoder.setCullMode(.front) // Show back faces
        encoder.setDepthStencilState(pipelineManager.depthGreaterWriteState)

        for primitive in primitives where primitive.operation == .subtraction {
            encoder.setVertexBuffer(primitive.vertexBuffer, offset: 0, index: 0)
            encoder.drawIndexedPrimitives(
                type: .triangle,
                indexCount: primitive.indexCount,
                indexType: .uint32,
                indexBuffer: primitive.indexBuffer,
                indexBufferOffset: 0
            )
        }

        // === Phase 2: Shading Pass (depth equal) ===

        encoder.setRenderPipelineState(shadingPipeline)
        encoder.setCullMode(.back)
        encoder.setDepthStencilState(pipelineManager.depthEqualNoWriteState)

        encoder.setVertexBuffer(uniformBuffer, offset: 0, index: 1)
        encoder.setFragmentBuffer(materialBuffer, offset: 0, index: 2)

        // Render all primitives with shading
        for primitive in primitives {
            encoder.setVertexBuffer(primitive.vertexBuffer, offset: 0, index: 0)
            encoder.drawIndexedPrimitives(
                type: .triangle,
                indexCount: primitive.indexCount,
                indexType: .uint32,
                indexBuffer: primitive.indexBuffer,
                indexBufferOffset: 0
            )
        }

        encoder.endEncoding()
    }

    // MARK: - Goldfeather Algorithm

    /// Render using Goldfeather algorithm.
    /// This handles concave primitives using stencil-based parity counting.
    private func renderGoldfeather(
        commandBuffer: MTLCommandBuffer,
        renderPassDescriptor: MTLRenderPassDescriptor,
        colorFormat: MTLPixelFormat,
        depthFormat: MTLPixelFormat
    ) throws {
        // Goldfeather requires stencil buffer
        // For now, fall back to SCS if stencil not available
        // TODO: Implement full Goldfeather with stencil operations

        try renderSCS(
            commandBuffer: commandBuffer,
            renderPassDescriptor: renderPassDescriptor,
            colorFormat: colorFormat,
            depthFormat: depthFormat
        )
    }
}

// MARK: - MTKViewDelegate

extension MetalCSGRenderer: MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // Update projection matrix for new size
        let aspect = Float(size.width / size.height)
        let projectionMatrix = simd_float4x4.perspectiveProjection(
            fovY: .pi / 4,
            aspect: aspect,
            nearZ: 0.1,
            farZ: 100.0
        )

        // Keep existing view matrix, update projection
        uniforms.modelViewProjectionMatrix = projectionMatrix * uniforms.modelViewMatrix
    }

    func draw(in view: MTKView) {
        render(to: view)
    }
}

// MARK: - Errors

enum CSGRendererError: Error {
    case commandQueueCreationFailed
    case bufferCreationFailed
    case encoderCreationFailed
    case pipelineStateCreationFailed
}

// MARK: - Matrix Utilities

extension simd_float4x4 {
    /// Create a perspective projection matrix
    static func perspectiveProjection(
        fovY: Float,
        aspect: Float,
        nearZ: Float,
        farZ: Float
    ) -> simd_float4x4 {
        let yScale = 1 / tan(fovY * 0.5)
        let xScale = yScale / aspect
        let zRange = farZ - nearZ
        let zScale = -(farZ + nearZ) / zRange
        let wzScale = -2 * farZ * nearZ / zRange

        return simd_float4x4(columns: (
            SIMD4<Float>(xScale, 0, 0, 0),
            SIMD4<Float>(0, yScale, 0, 0),
            SIMD4<Float>(0, 0, zScale, -1),
            SIMD4<Float>(0, 0, wzScale, 0)
        ))
    }

    /// Create a look-at view matrix
    static func lookAt(
        eye: SIMD3<Float>,
        center: SIMD3<Float>,
        up: SIMD3<Float>
    ) -> simd_float4x4 {
        let z = normalize(eye - center)
        let x = normalize(cross(up, z))
        let y = cross(z, x)

        return simd_float4x4(columns: (
            SIMD4<Float>(x.x, y.x, z.x, 0),
            SIMD4<Float>(x.y, y.y, z.y, 0),
            SIMD4<Float>(x.z, y.z, z.z, 0),
            SIMD4<Float>(-dot(x, eye), -dot(y, eye), -dot(z, eye), 1)
        ))
    }
}
