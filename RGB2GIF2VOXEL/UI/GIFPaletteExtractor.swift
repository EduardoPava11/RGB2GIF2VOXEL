//
//  GIFPaletteExtractor.swift
//  RGB2GIF2VOXEL
//
//  Dynamic color palette extraction from GIF89a frames
//  Creates beautiful, animated UI themes from captured content
//

import SwiftUI
import UIKit
import CoreImage
import Combine

/// Extracts dominant colors from GIF frames for dynamic UI theming
@MainActor
public class GIFPaletteExtractor: ObservableObject {

    // MARK: - Published Properties

    /// The current dominant color for UI theming
    @Published public var dominantColor: Color = .blue

    /// Animated gradient from frame colors
    @Published public var animatedGradient: [Color] = [.blue, .purple]

    /// Full palette extracted from GIF
    @Published public var extractedPalette: [Color] = []

    /// Per-frame colors for timeline visualization
    @Published public var frameColors: [Color] = []

    /// Current animated color (changes over time)
    @Published public var pulsingColor: Color = .blue

    // MARK: - Private Properties

    private var paletteData: [UInt32] = []
    private var animationTimer: Timer?
    private var currentColorIndex: Int = 0

    // MARK: - Initialization

    public init() {
        startColorAnimation()
    }

    deinit {
        animationTimer?.invalidate()
    }

    // MARK: - Public Methods

    /// Extract colors from CubeTensorData palette
    public func extractFromTensor(_ tensor: CubeTensorData) {
        print("🎨 Extracting colors from tensor palette...")

        // Store raw palette data
        self.paletteData = tensor.palette

        // Convert palette to SwiftUI colors
        var colors: [Color] = []
        for i in 0..<min(tensor.palette.count, 256) {
            let rgba = tensor.palette[i]
            let color = colorFromRGBA(rgba)
            colors.append(color)
        }

        // Remove duplicates and sort by luminance
        let uniqueColors = Array(Set(colors)).sorted { c1, c2 in
            luminance(of: c1) > luminance(of: c2)
        }

        self.extractedPalette = uniqueColors
        print("   Extracted \(uniqueColors.count) unique colors")

        // Set dominant color (most vibrant non-black color)
        if let vibrant = findMostVibrantColor(from: uniqueColors) {
            self.dominantColor = vibrant
        }

        // Create gradient from top colors
        if uniqueColors.count >= 2 {
            self.animatedGradient = Array(uniqueColors.prefix(5))
        }

        // Sample one color per frame for animation
        sampleFrameColors(from: tensor)
    }

    /// Extract colors from raw tensor data (256×256×256 RGBA)
    public func extractFromRawTensor(_ data: Data) {
        print("🎨 Extracting colors from raw tensor data...")

        let frameSize = 256 * 256 * 4
        let frameCount = min(256, data.count / frameSize)

        var colors: [Color] = []

        // Sample colors from each frame
        for frame in 0..<frameCount {
            let frameOffset = frame * frameSize

            // Sample center pixel and corners
            let samples = [
                (128, 128),  // Center
                (64, 64),    // Top-left quadrant
                (192, 64),   // Top-right quadrant
                (64, 192),   // Bottom-left quadrant
                (192, 192),  // Bottom-right quadrant
            ]

            for (x, y) in samples {
                let pixelOffset = frameOffset + (y * 256 + x) * 4

                if pixelOffset + 3 < data.count {
                    let r = CGFloat(data[pixelOffset]) / 255.0
                    let g = CGFloat(data[pixelOffset + 1]) / 255.0
                    let b = CGFloat(data[pixelOffset + 2]) / 255.0
                    let a = CGFloat(data[pixelOffset + 3]) / 255.0

                    if a > 0.5 {  // Only opaque colors
                        let color = Color(red: r, green: g, blue: b)
                        colors.append(color)
                    }
                }
            }

            // Store frame color for animation
            if let lastColor = colors.last {
                frameColors.append(lastColor)
            }
        }

        // Remove duplicates
        let uniqueColors = Array(Set(colors))
        self.extractedPalette = uniqueColors

        // Find dominant color
        if let vibrant = findMostVibrantColor(from: uniqueColors) {
            self.dominantColor = vibrant
        }

        // Create animated gradient
        if uniqueColors.count >= 2 {
            self.animatedGradient = Array(uniqueColors.shuffled().prefix(5))
        }

        print("   Extracted \(uniqueColors.count) unique colors from \(frameCount) frames")
    }

    // MARK: - Private Methods

    private func sampleFrameColors(from tensor: CubeTensorData) {
        // Sample one color per frame for smooth animation
        frameColors = []

        let framesNeeded = min(256, tensor.size)
        let indicesPerFrame = tensor.size * tensor.size

        for frame in 0..<framesNeeded {
            // Sample center pixel of each frame
            let centerIndex = frame * indicesPerFrame + (tensor.size * tensor.size) / 2

            if centerIndex < tensor.indices.count && !tensor.palette.isEmpty {
                let paletteIndex = Int(tensor.indices[centerIndex]) % tensor.palette.count
                let rgba = tensor.palette[paletteIndex]
                frameColors.append(colorFromRGBA(rgba))
            }
        }

        print("   Sampled \(frameColors.count) frame colors for animation")
    }

    private func colorFromRGBA(_ rgba: UInt32) -> Color {
        let r = Double((rgba >> 24) & 0xFF) / 255.0
        let g = Double((rgba >> 16) & 0xFF) / 255.0
        let b = Double((rgba >> 8) & 0xFF) / 255.0
        return Color(red: r, green: g, blue: b)
    }

    private func luminance(of color: Color) -> Double {
        let uiColor = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: nil)

        // Perceived luminance formula
        return 0.299 * Double(r) + 0.587 * Double(g) + 0.114 * Double(b)
    }

    private func findMostVibrantColor(from colors: [Color]) -> Color? {
        return colors.max { c1, c2 in
            saturation(of: c1) < saturation(of: c2)
        }
    }

    private func saturation(of color: Color) -> Double {
        let uiColor = UIColor(color)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0
        uiColor.getHue(&h, saturation: &s, brightness: &b, alpha: nil)
        return Double(s)
    }

    private func startColorAnimation() {
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            self.animateColors()
        }
    }

    private func animateColors() {
        guard !frameColors.isEmpty else { return }

        // Cycle through frame colors smoothly
        currentColorIndex = (currentColorIndex + 1) % frameColors.count

        withAnimation(.easeInOut(duration: 0.3)) {
            pulsingColor = frameColors[currentColorIndex]
        }

        // Occasionally shuffle gradient
        if currentColorIndex % 30 == 0 && extractedPalette.count > 5 {
            withAnimation(.easeInOut(duration: 1.0)) {
                animatedGradient = Array(extractedPalette.shuffled().prefix(5))
            }
        }
    }
}

// MARK: - UI Components

/// Beautiful gradient background using extracted colors
public struct DynamicGradientBackground: View {
    @ObservedObject var paletteExtractor: GIFPaletteExtractor

    public var body: some View {
        LinearGradient(
            colors: paletteExtractor.animatedGradient.isEmpty
                ? [.blue, .purple]
                : paletteExtractor.animatedGradient,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .animation(.easeInOut(duration: 2.0), value: paletteExtractor.animatedGradient)
        .ignoresSafeArea()
    }
}

/// Animated color orb that pulses with frame colors
public struct PulsingColorOrb: View {
    @ObservedObject var paletteExtractor: GIFPaletteExtractor
    @State private var scale: CGFloat = 1.0
    @State private var rotation: Double = 0

    public var body: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        paletteExtractor.pulsingColor.opacity(0.8),
                        paletteExtractor.pulsingColor.opacity(0.3),
                        .clear
                    ],
                    center: .center,
                    startRadius: 5,
                    endRadius: 50
                )
            )
            .frame(width: 100, height: 100)
            .scaleEffect(scale)
            .rotationEffect(.degrees(rotation))
            .onAppear {
                withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                    scale = 1.3
                }
                withAnimation(.linear(duration: 10).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
    }
}

/// Color palette display showing all extracted colors
public struct ExtractedPaletteView: View {
    @ObservedObject var paletteExtractor: GIFPaletteExtractor

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(paletteExtractor.extractedPalette.prefix(20).enumerated()), id: \.offset) { index, color in
                    ColorSwatch(color: color, index: index)
                }
            }
            .padding()
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct ColorSwatch: View {
    let color: Color
    let index: Int
    @State private var isPressed = false

    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(color)
            .frame(width: 44, height: 44)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
            )
            .scaleEffect(isPressed ? 0.9 : 1.0)
            .onTapGesture {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    isPressed.toggle()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        isPressed = false
                    }
                }
            }
    }
}

/// Timeline visualization with frame colors
public struct FrameColorTimeline: View {
    @ObservedObject var paletteExtractor: GIFPaletteExtractor
    @State private var selectedFrame: Int = 0

    public var body: some View {
        VStack(spacing: 4) {
            // Color bars
            GeometryReader { geometry in
                HStack(spacing: 1) {
                    ForEach(Array(paletteExtractor.frameColors.enumerated()), id: \.offset) { index, color in
                        Rectangle()
                            .fill(color)
                            .frame(width: max(1, geometry.size.width / CGFloat(paletteExtractor.frameColors.count)))
                            .scaleEffect(y: selectedFrame == index ? 1.5 : 1.0)
                            .animation(.spring(response: 0.2), value: selectedFrame)
                    }
                }
            }
            .frame(height: 40)

            // Frame indicator
            Text("Frame \(selectedFrame + 1) / \(paletteExtractor.frameColors.count)")
                .font(.caption)
                .foregroundColor(.white.opacity(0.8))
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onAppear {
            // Animate through frames
            Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
                selectedFrame = (selectedFrame + 1) % max(1, paletteExtractor.frameColors.count)
            }
        }
    }
}