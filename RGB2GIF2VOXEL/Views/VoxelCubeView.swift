//
//  VoxelCubeView.swift
//  RGB2GIF2VOXEL
//
//  SwiftUI view wrapping Metal voxel renderer
//

import SwiftUI
import MetalKit

public struct VoxelCubeView: UIViewRepresentable {
    let gifData: Data
    @State private var renderer: MetalVoxelRenderer?
    @Binding var rotation: SIMD3<Float>
    @Binding var scale: Float

    public init(gifData: Data, rotation: Binding<SIMD3<Float>> = .constant(.zero), scale: Binding<Float> = .constant(1.0)) {
        self.gifData = gifData
        self._rotation = rotation
        self._scale = scale
    }

    public func makeUIView(context: Context) -> MTKView {
        let metalView = MTKView()

        guard let device = MTLCreateSystemDefaultDevice() else {
            print("Metal is not supported on this device")
            return metalView
        }

        metalView.device = device
        metalView.colorPixelFormat = .bgra8Unorm
        metalView.depthStencilPixelFormat = .depth32Float
        metalView.clearColor = MTLClearColor(red: 0.05, green: 0.05, blue: 0.1, alpha: 1.0)
        metalView.isPaused = false
        metalView.enableSetNeedsDisplay = false
        metalView.preferredFramesPerSecond = 60

        // Create and setup renderer
        let renderer = MetalVoxelRenderer()
        context.coordinator.renderer = renderer
        metalView.delegate = context.coordinator

        // Load GIF frames into renderer
        if let frames = extractFramesFromGIF(gifData) {
            renderer.loadFrames(frames)
        }

        return metalView
    }

    public func updateUIView(_ metalView: MTKView, context: Context) {
        context.coordinator.renderer?.rotate(by: rotation)
        context.coordinator.renderer?.setScale(scale)
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public class Coordinator: NSObject, MTKViewDelegate {
        var parent: VoxelCubeView
        var renderer: MetalVoxelRenderer?

        init(_ parent: VoxelCubeView) {
            self.parent = parent
            super.init()
        }

        public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            // Handle resize
        }

        public func draw(in view: MTKView) {
            renderer?.render(in: view)
        }
    }

    // Extract frames from GIF data
    private func extractFramesFromGIF(_ gifData: Data) -> [Data]? {
        // For now, return placeholder data
        // In production, parse GIF and extract frame data
        var frames: [Data] = []

        // Create some test frames
        for i in 0..<128 {
            var frameData = Data(count: 128 * 128 * 4)
            frameData.withUnsafeMutableBytes { bytes in
                let pixels = bytes.bindMemory(to: UInt8.self)
                for y in 0..<128 {
                    for x in 0..<128 {
                        let idx = (y * 128 + x) * 4
                        // Create gradient pattern
                        pixels[idx] = UInt8((x * 255) / 127)     // B
                        pixels[idx+1] = UInt8((y * 255) / 127)   // G
                        pixels[idx+2] = UInt8((i * 255) / 127)   // R
                        pixels[idx+3] = 255                       // A
                    }
                }
            }
            frames.append(frameData)
        }

        return frames
    }
}

// Enhanced 3D visualization view with controls
public struct Enhanced3DVoxelView: View {
    let gifData: Data
    @State private var rotation = SIMD3<Float>(0, 0, 0)
    @State private var scale: Float = 1.0
    @State private var autoRotate = true
    @State private var showWireframe = false

    public var body: some View {
        ZStack {
            // Metal voxel view
            VoxelCubeView(gifData: gifData, rotation: $rotation, scale: $scale)
                .ignoresSafeArea()

            // Controls overlay
            VStack {
                // Header
                VStack(spacing: 4) {
                    Text("VOXEL CUBE")
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)

                    Text("128³ Frame Conveyor")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.ultraThinMaterial)
                )
                .padding(.top, 60)

                Spacer()

                // Bottom controls
                VStack(spacing: 16) {
                    // Auto-rotate toggle
                    Toggle(isOn: $autoRotate) {
                        Label("Auto Rotate", systemImage: "rotate.3d")
                            .foregroundColor(.white)
                    }
                    .toggleStyle(SwitchToggleStyle(tint: .blue))
                    .padding(.horizontal)

                    // Scale slider
                    HStack {
                        Image(systemName: "minus.magnifyingglass")
                            .foregroundColor(.white.opacity(0.7))

                        Slider(value: $scale, in: 0.5...2.0)
                            .accentColor(.blue)

                        Image(systemName: "plus.magnifyingglass")
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .padding(.horizontal)

                    // Wireframe toggle
                    Button(action: { showWireframe.toggle() }) {
                        Label(showWireframe ? "Solid" : "Wireframe",
                              systemImage: showWireframe ? "cube.fill" : "cube")
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(
                                Capsule()
                                    .fill(showWireframe ? Color.blue : Color.gray.opacity(0.3))
                            )
                    }
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(.ultraThinMaterial)
                )
                .padding()
            }
        }
        .onAppear {
            startAutoRotation()
        }
    }

    private func startAutoRotation() {
        Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { _ in
            if autoRotate {
                rotation.y += 0.01
            }
        }
    }
}

// Preview provider
struct VoxelCubeView_Previews: PreviewProvider {
    static var previews: some View {
        Enhanced3DVoxelView(gifData: Data())
            .preferredColorScheme(.dark)
    }
}