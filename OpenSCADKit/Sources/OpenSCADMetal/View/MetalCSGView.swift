//
//  MetalCSGView.swift
//  OpenSCADMetal
//
//  SwiftUI view wrapper for Metal CSG rendering.
//  Provides interactive 3D preview of CSG operations.
//

import SwiftUI
import MetalKit
import simd

#if os(macOS)
typealias ViewRepresentable = NSViewRepresentable
#else
typealias ViewRepresentable = UIViewRepresentable
#endif

/// SwiftUI view that renders CSG primitives using Metal.
struct MetalCSGView: ViewRepresentable {

    // MARK: - Properties

    /// The primitives to render
    @Binding var primitives: [CSGPrimitive]

    /// Camera rotation (radians)
    @Binding var cameraRotationX: Float
    @Binding var cameraRotationY: Float

    /// Camera zoom level
    @Binding var cameraZoom: Float

    /// Camera distance from origin
    var cameraDistance: Float = 5.0

    /// Background color
    var backgroundColor: SIMD4<Float> = SIMD4<Float>(0.15, 0.15, 0.18, 1.0)

    /// Material for rendering
    var material: CSGMaterial = CSGMaterial()

    // MARK: - View Representable

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    #if os(macOS)
    func makeNSView(context: Context) -> MTKView {
        createMTKView(context: context)
    }

    func updateNSView(_ view: MTKView, context: Context) {
        updateView(view, context: context)
    }
    #else
    func makeUIView(context: Context) -> MTKView {
        createMTKView(context: context)
    }

    func updateUIView(_ view: MTKView, context: Context) {
        updateView(view, context: context)
    }
    #endif

    private func createMTKView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.delegate = context.coordinator

        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported on this device")
        }

        mtkView.device = device
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.depthStencilPixelFormat = .depth32Float
        mtkView.clearColor = MTLClearColor(
            red: Double(backgroundColor.x),
            green: Double(backgroundColor.y),
            blue: Double(backgroundColor.z),
            alpha: Double(backgroundColor.w)
        )

        // Enable depth buffer
        mtkView.clearDepth = 1.0

        // Create renderer
        do {
            context.coordinator.renderer = try MetalCSGRenderer(device: device)
            context.coordinator.renderer?.backgroundColor = backgroundColor
        } catch {
            print("Failed to create CSG renderer: \(error)")
        }

        return mtkView
    }

    private func updateView(_ view: MTKView, context: Context) {
        guard let renderer = context.coordinator.renderer else { return }

        // Update primitives
        renderer.setPrimitives(primitives)

        // Update camera transform
        let viewMatrix = createViewMatrix()
        let aspect = Float(view.drawableSize.width / view.drawableSize.height)
        let projectionMatrix = simd_float4x4.perspectiveProjection(
            fovY: .pi / 4,
            aspect: aspect,
            nearZ: 0.1,
            farZ: 100.0
        )

        renderer.setTransforms(
            modelMatrix: matrix_identity_float4x4,
            viewMatrix: viewMatrix,
            projectionMatrix: projectionMatrix
        )

        // Update material
        renderer.setMaterial(material)

        // Update background
        renderer.backgroundColor = backgroundColor
        view.clearColor = MTLClearColor(
            red: Double(backgroundColor.x),
            green: Double(backgroundColor.y),
            blue: Double(backgroundColor.z),
            alpha: Double(backgroundColor.w)
        )

        // Trigger redraw
        view.setNeedsDisplay(view.bounds)
    }

    private func createViewMatrix() -> simd_float4x4 {
        // Create rotation quaternion
        let rotX = simd_quatf(angle: cameraRotationX, axis: SIMD3<Float>(1, 0, 0))
        let rotY = simd_quatf(angle: cameraRotationY, axis: SIMD3<Float>(0, 1, 0))
        let rotation = rotY * rotX

        // Calculate camera position
        let distance = cameraDistance / cameraZoom
        let forward = rotation.act(SIMD3<Float>(0, 0, 1))
        let eye = forward * distance
        let up = rotation.act(SIMD3<Float>(0, 1, 0))

        return simd_float4x4.lookAt(
            eye: eye,
            center: SIMD3<Float>(0, 0, 0),
            up: up
        )
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, MTKViewDelegate {
        var parent: MetalCSGView
        var renderer: MetalCSGRenderer?

        init(_ parent: MetalCSGView) {
            self.parent = parent
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            // Size change handled in updateView
        }

        func draw(in view: MTKView) {
            renderer?.render(to: view)
        }
    }
}

// MARK: - Interactive CSG View

/// Full-featured CSG view with gesture controls
struct InteractiveCSGView: View {

    @Binding var primitives: [CSGPrimitive]

    @State private var rotationX: Float = 0.3
    @State private var rotationY: Float = 0.5
    @State private var zoom: Float = 1.0

    @State private var baseRotationX: Float = 0.3
    @State private var baseRotationY: Float = 0.5
    @State private var baseZoom: Float = 1.0

    var body: some View {
        MetalCSGView(
            primitives: $primitives,
            cameraRotationX: $rotationX,
            cameraRotationY: $rotationY,
            cameraZoom: $zoom
        )
        .gesture(dragGesture)
        .gesture(magnifyGesture)
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                let sensitivity: Float = 0.008
                rotationY = baseRotationY + Float(value.translation.width) * sensitivity
                rotationX = baseRotationX + Float(value.translation.height) * sensitivity
                // Clamp X rotation to prevent flipping
                rotationX = min(max(rotationX, -.pi / 2 + 0.1), .pi / 2 - 0.1)
            }
            .onEnded { _ in
                baseRotationX = rotationX
                baseRotationY = rotationY
            }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                zoom = baseZoom * Float(value.magnification)
                zoom = min(max(zoom, 0.1), 10.0)
            }
            .onEnded { _ in
                baseZoom = zoom
            }
    }
}

// MARK: - Preview

#if DEBUG
struct MetalCSGView_Previews: PreviewProvider {
    static var previews: some View {
        InteractiveCSGView(primitives: .constant([]))
            .frame(width: 400, height: 400)
    }
}
#endif
