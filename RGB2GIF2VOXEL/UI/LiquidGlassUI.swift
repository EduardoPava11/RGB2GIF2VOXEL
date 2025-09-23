//
//  LiquidGlassUI.swift
//  RGB2GIF2VOXEL
//
//  Beautiful Liquid Glass UI components inspired by iOS 26 and visionOS
//  Dynamic, translucent materials that react to GIF colors
//

import SwiftUI

// MARK: - Liquid Glass Materials

/// Adaptive glass material that changes color based on content
public struct LiquidGlassMaterial: ViewModifier {
    let baseColor: Color
    let intensity: Double

    public func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    // Base glass layer
                    RoundedRectangle(cornerRadius: 20)
                        .fill(.ultraThinMaterial)

                    // Color tint layer
                    RoundedRectangle(cornerRadius: 20)
                        .fill(baseColor.opacity(intensity * 0.15))

                    // Gradient overlay for depth
                    RoundedRectangle(cornerRadius: 20)
                        .fill(
                            LinearGradient(
                                colors: [
                                    baseColor.opacity(intensity * 0.1),
                                    .clear,
                                    baseColor.opacity(intensity * 0.05)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    // Inner glow
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.3),
                                    Color.white.opacity(0.1)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: baseColor.opacity(0.2), radius: 10, y: 5)
    }
}

extension View {
    public func liquidGlass(color: Color = .blue, intensity: Double = 1.0) -> some View {
        modifier(LiquidGlassMaterial(baseColor: color, intensity: intensity))
    }
}

// MARK: - Animated Capture Button

public struct AnimatedCaptureButton: View {
    @Binding var isCapturing: Bool
    var dominantColor: Color
    var action: () -> Void

    @State private var pulseScale: CGFloat = 1.0
    @State private var rotationAngle: Double = 0

    public var body: some View {
        Button(action: action) {
            ZStack {
                // Outer ring with gradient
                Circle()
                    .stroke(
                        AngularGradient(
                            colors: [
                                dominantColor,
                                dominantColor.opacity(0.5),
                                .white.opacity(0.3),
                                dominantColor
                            ],
                            center: .center,
                            startAngle: .degrees(rotationAngle),
                            endAngle: .degrees(rotationAngle + 360)
                        ),
                        lineWidth: 4
                    )
                    .frame(width: 80, height: 80)
                    .rotationEffect(.degrees(isCapturing ? rotationAngle : 0))

                // Inner button
                ZStack {
                    if isCapturing {
                        // Recording indicator
                        RoundedRectangle(cornerRadius: 8)
                            .fill(
                                LinearGradient(
                                    colors: [.red, .red.opacity(0.7)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: 35, height: 35)
                            .transition(.scale.combined(with: .opacity))
                    } else {
                        // Capture circle
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [
                                        dominantColor,
                                        dominantColor.opacity(0.8)
                                    ],
                                    center: .center,
                                    startRadius: 5,
                                    endRadius: 30
                                )
                            )
                            .frame(width: 65, height: 65)
                    }
                }
                .scaleEffect(pulseScale)
            }
        }
        .onAppear {
            // Pulse animation
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                pulseScale = 1.1
            }

            // Rotation animation when capturing
            withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                rotationAngle = 360
            }
        }
    }
}

// MARK: - Progress Ring

public struct GradientProgressRing: View {
    let progress: Double
    let colors: [Color]
    let lineWidth: CGFloat = 8

    public var body: some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(Color.white.opacity(0.1), lineWidth: lineWidth)

            // Progress ring
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    AngularGradient(
                        colors: colors + [colors.first ?? .blue],
                        center: .center
                    ),
                    style: StrokeStyle(
                        lineWidth: lineWidth,
                        lineCap: .round
                    )
                )
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.5, dampingFraction: 0.8), value: progress)
        }
    }
}

// MARK: - Floating Action Cards

public struct FloatingActionCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    let action: () -> Void

    @State private var isPressed = false
    @State private var hovering = false

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                // Icon with gradient background
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    color,
                                    color.opacity(0.7)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 50, height: 50)

                    Image(systemName: icon)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundColor(.white)
                }

                // Text content
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Arrow indicator
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(color)
                    .offset(x: hovering ? 3 : 0)
            }
            .padding()
            .liquidGlass(color: color, intensity: hovering ? 1.2 : 1.0)
            .scaleEffect(isPressed ? 0.95 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering = $0 }
        .onTapGesture {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                isPressed = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isPressed = false
                    action()
                }
            }
        }
    }
}

// MARK: - Voxel Preview Card

public struct VoxelPreviewCard: View {
    let frameCount: Int
    let tensorSize: Int
    let dominantColor: Color
    @State private var rotation3D: Double = 0

    public var body: some View {
        VStack(spacing: 12) {
            // 3D Cube visualization
            ZStack {
                // Wireframe cube representation
                ForEach(0..<6, id: \.self) { face in
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    dominantColor,
                                    dominantColor.opacity(0.3)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 2
                        )
                        .frame(width: 60, height: 60)
                        .rotation3DEffect(
                            .degrees(rotation3D + Double(face * 60)),
                            axis: (x: face % 2 == 0 ? 1 : 0,
                                   y: face % 2 == 1 ? 1 : 0,
                                   z: 0.5),
                            perspective: 0.5
                        )
                }

                // Center info
                VStack(spacing: 2) {
                    Text("\(tensorSize)³")
                        .font(.system(.title3, design: .monospaced))
                        .fontWeight(.bold)

                    Text("VOXELS")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
            .frame(height: 100)

            // Stats
            VStack(spacing: 8) {
                HStack {
                    Label("\(frameCount) frames", systemImage: "square.stack.3d.up")
                        .font(.caption)
                    Spacer()
                }

                HStack {
                    Label("\(tensorSize * tensorSize * tensorSize) voxels", systemImage: "cube")
                        .font(.caption)
                    Spacer()
                }
            }
            .padding(.horizontal)
        }
        .padding()
        .frame(width: 180)
        .liquidGlass(color: dominantColor, intensity: 0.8)
        .onAppear {
            withAnimation(.linear(duration: 10).repeatForever(autoreverses: false)) {
                rotation3D = 360
            }
        }
    }
}

// MARK: - Settings Panel

public struct LiquidGlassSettingsPanel: View {
    @Binding var selectedN: Int
    @Binding var paletteSize: Int
    let dominantColor: Color

    let nOptions = [256, 132, 264]
    let paletteOptions = [256, 128, 64]

    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Cube Size Selector
            VStack(alignment: .leading, spacing: 8) {
                Label("Cube Dimensions", systemImage: "cube.transparent")
                    .font(.headline)

                HStack(spacing: 12) {
                    ForEach(nOptions, id: \.self) { n in
                        CubeSizeOption(
                            size: n,
                            isSelected: selectedN == n,
                            color: dominantColor
                        ) {
                            selectedN = n
                        }
                    }
                }
            }

            // Palette Size Selector
            VStack(alignment: .leading, spacing: 8) {
                Label("Color Palette", systemImage: "paintpalette")
                    .font(.headline)

                HStack(spacing: 12) {
                    ForEach(paletteOptions, id: \.self) { size in
                        PaletteSizeOption(
                            size: size,
                            isSelected: paletteSize == size,
                            color: dominantColor
                        ) {
                            paletteSize = size
                        }
                    }
                }
            }
        }
        .padding()
        .liquidGlass(color: dominantColor, intensity: 0.6)
    }
}

struct CubeSizeOption: View {
    let size: Int
    let isSelected: Bool
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text("\(size)")
                    .font(.system(.title2, design: .monospaced))
                    .fontWeight(isSelected ? .bold : .medium)

                Text(size == 256 ? "HD" : size == 132 ? "Fast" : "Ultra")
                    .font(.caption2)
            }
            .foregroundColor(isSelected ? .white : .primary)
            .frame(width: 80, height: 60)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ?
                          LinearGradient(
                              colors: [color, color.opacity(0.7)],
                              startPoint: .top,
                              endPoint: .bottom
                          ) :
                          LinearGradient(
                              colors: [Color.white.opacity(0.1), Color.white.opacity(0.05)],
                              startPoint: .top,
                              endPoint: .bottom
                          )
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct PaletteSizeOption: View {
    let size: Int
    let isSelected: Bool
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text("\(size)")
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(isSelected ? .bold : .medium)

                Text("colors")
                    .font(.caption2)
            }
            .foregroundColor(isSelected ? .white : .primary)
            .frame(width: 60, height: 50)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ?
                          LinearGradient(
                              colors: [color, color.opacity(0.7)],
                              startPoint: .top,
                              endPoint: .bottom
                          ) :
                          LinearGradient(
                              colors: [Color.white.opacity(0.1), Color.white.opacity(0.05)],
                              startPoint: .top,
                              endPoint: .bottom
                          )
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}