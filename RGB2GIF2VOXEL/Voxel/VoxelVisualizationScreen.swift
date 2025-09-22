//
//  VoxelVisualizationScreen.swift
//  RGB2GIF2VOXEL
//
//  Main screen for displaying and controlling the voxel cube visualization
//

import SwiftUI
import Combine

struct VoxelVisualizationScreen: View {

    // MARK: - Properties

    let gifData: Data
    let tensorData: Data

    @State private var isPlaying = true
    @State private var playbackSpeed: Float = 1.0
    @State private var viewMode: VoxelDisplayMode = .solid
    @State private var cubeOpacity: Double = 1.0
    @State private var rotationAngle: Double = 0.0
    @State private var zSlicePosition: Double = 128.0
    @State private var showInfo = false
    @State private var showExportOptions = false

    @Environment(\.presentationMode) var presentationMode

    // MARK: - Body

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [Color.black, Color.gray.opacity(0.3)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                headerView

                // 3D Voxel Cube
                voxelCubeView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Controls
                controlsView
                    .padding()
                    .background(
                        BlurredBackground()
                            .ignoresSafeArea(edges: .bottom)
                    )
            }
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $showInfo) {
            VoxelInfoSheet(
                gifData: gifData,
                tensorData: tensorData
            )
        }
        .sheet(isPresented: $showExportOptions) {
            ExportOptionsSheet(
                gifData: gifData,
                tensorData: tensorData
            )
        }
    }

    // MARK: - Header View

    private var headerView: some View {
        HStack {
            Button(action: {
                presentationMode.wrappedValue.dismiss()
            }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.white.opacity(0.2)))
            }

            Spacer()

            Text("VOXEL CUBE")
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundColor(.white)

            Spacer()

            Button(action: {
                showInfo = true
            }) {
                Image(systemName: "info.circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.white.opacity(0.2)))
            }
        }
        .padding()
        .background(
            BlurredBackground()
                .ignoresSafeArea(edges: .top)
        )
    }

    // MARK: - Voxel Cube View

    private var voxelCubeView: some View {
        GeometryReader { geometry in
            VoxelCubeView(
                tensorData: tensorData,
                isPlaying: $isPlaying,
                playbackSpeed: $playbackSpeed,
                viewMode: $viewMode
            )
            .opacity(cubeOpacity)
            .rotation3DEffect(
                .degrees(rotationAngle),
                axis: (x: 0, y: 1, z: 0)
            )
            .gesture(
                DragGesture()
                    .onChanged { value in
                        rotationAngle += Double(value.translation.width) / 5.0
                    }
            )
            .onTapGesture {
                withAnimation(.spring()) {
                    isPlaying.toggle()
                }
            }
        }
    }

    // MARK: - Controls View

    private var controlsView: some View {
        VStack(spacing: 20) {
            // Playback controls
            playbackControls

            // View mode selector
            viewModeSelector

            // Sliders
            slidersSection

            // Export buttons
            exportButtons
        }
    }

    private var playbackControls: some View {
        HStack(spacing: 30) {
            // Play/Pause
            Button(action: {
                withAnimation(.spring()) {
                    isPlaying.toggle()
                }
            }) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.white)
                    .frame(width: 60, height: 60)
                    .background(
                        Circle()
                            .fill(Color.accentColor)
                            .shadow(color: .accentColor.opacity(0.3), radius: 10)
                    )
            }

            // Speed control
            HStack {
                Image(systemName: "tortoise.fill")
                    .foregroundColor(.gray)

                Slider(value: $playbackSpeed, in: 0.1...3.0)
                    .accentColor(.accentColor)
                    .frame(width: 120)

                Image(systemName: "hare.fill")
                    .foregroundColor(.gray)

                Text("\(String(format: "%.1f", playbackSpeed))×")
                    .font(.caption)
                    .foregroundColor(.white)
                    .frame(width: 40)
            }
        }
    }

    private var viewModeSelector: some View {
        HStack(spacing: 15) {
            ForEach(VoxelDisplayMode.allCases, id: \.self) { mode in
                Button(action: {
                    withAnimation(.spring()) {
                        viewMode = mode
                    }
                }) {
                    VStack(spacing: 5) {
                        Image(systemName: mode.icon)
                            .font(.system(size: 20))

                        Text(mode.rawValue)
                            .font(.caption2)
                    }
                    .foregroundColor(viewMode == mode ? .black : .white)
                    .frame(width: 70, height: 50)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(viewMode == mode ? Color.white : Color.white.opacity(0.2))
                    )
                }
            }
        }
    }

    private var slidersSection: some View {
        VStack(spacing: 15) {
            // Opacity slider
            HStack {
                Label("Opacity", systemImage: "eye.fill")
                    .foregroundColor(.white)
                    .frame(width: 100, alignment: .leading)

                Slider(value: $cubeOpacity, in: 0.1...1.0)
                    .accentColor(.white)

                Text("\(Int(cubeOpacity * 100))%")
                    .foregroundColor(.white)
                    .frame(width: 50)
            }

            // Z-Slice slider (for slice mode)
            if viewMode == .slice {
                HStack {
                    Label("Z-Slice", systemImage: "square.stack.3d.down.forward")
                        .foregroundColor(.white)
                        .frame(width: 100, alignment: .leading)

                    Slider(value: $zSlicePosition, in: 0...255, step: 1)
                        .accentColor(.white)

                    Text("\(Int(zSlicePosition))")
                        .foregroundColor(.white)
                        .frame(width: 50)
                }
            }
        }
    }

    private var exportButtons: some View {
        HStack(spacing: 15) {
            Button(action: {
                showExportOptions = true
            }) {
                Label("Export Voxel", systemImage: "cube.fill")
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 25)
                            .fill(Color.white.opacity(0.2))
                    )
            }

            Button(action: {
                shareGIF()
            }) {
                Label("Share GIF", systemImage: "square.and.arrow.up")
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 25)
                            .fill(Color.white.opacity(0.2))
                    )
            }
        }
    }

    // MARK: - Actions

    private func shareGIF() {
        let activityVC = UIActivityViewController(
            activityItems: [gifData],
            applicationActivities: nil
        )

        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
    }
}

// MARK: - Info Sheet

struct VoxelInfoSheet: View {
    let gifData: Data
    let tensorData: Data

    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        NavigationView {
            List {
                Section(header: Text("GIF Information")) {
                    InfoRow(label: "File Size", value: formatBytes(gifData.count))
                    InfoRow(label: "Frames", value: "256")
                    InfoRow(label: "Resolution", value: "256×256")
                    InfoRow(label: "Color Depth", value: "8-bit (256 colors)")
                }

                Section(header: Text("Voxel Tensor")) {
                    InfoRow(label: "Tensor Size", value: formatBytes(tensorData.count))
                    InfoRow(label: "Dimensions", value: "16×16×256")
                    InfoRow(label: "Voxels", value: "65,536")
                    InfoRow(label: "Data Format", value: "RGBA (4 bytes/voxel)")
                }

                Section(header: Text("Visualization")) {
                    Text("The voxel cube represents your GIF as a 3D temporal sculpture where:")
                        .font(.caption)
                    Text("• X-axis: Horizontal position")
                        .font(.caption)
                    Text("• Y-axis: Vertical position")
                        .font(.caption)
                    Text("• Z-axis: Time (frames)")
                        .font(.caption)
                }
            }
            .navigationTitle("Voxel Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }

    private func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }
}

// MARK: - Export Options Sheet

struct ExportOptionsSheet: View {
    let gifData: Data
    let tensorData: Data

    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Export Formats")) {
                    Button(action: exportAsVOX) {
                        HStack {
                            Image(systemName: "cube.fill")
                                .foregroundColor(.blue)
                            Text("MagicaVoxel (.vox)")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                        }
                    }

                    Button(action: exportAsPLY) {
                        HStack {
                            Image(systemName: "cube.transparent")
                                .foregroundColor(.green)
                            Text("Stanford PLY (.ply)")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                        }
                    }

                    Button(action: exportAsOBJ) {
                        HStack {
                            Image(systemName: "cube")
                                .foregroundColor(.orange)
                            Text("Wavefront OBJ (.obj)")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Section(header: Text("Share Options")) {
                    Button(action: shareToAR) {
                        HStack {
                            Image(systemName: "arkit")
                                .foregroundColor(.purple)
                            Text("View in AR")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Export Voxel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }

    private func exportAsVOX() {
        // TODO: Implement VOX export
        print("Exporting as VOX...")
    }

    private func exportAsPLY() {
        // TODO: Implement PLY export
        print("Exporting as PLY...")
    }

    private func exportAsOBJ() {
        // TODO: Implement OBJ export
        print("Exporting as OBJ...")
    }

    private func shareToAR() {
        // TODO: Implement AR sharing
        print("Sharing to AR...")
    }
}

// MARK: - Supporting Views

struct BlurredBackground: UIViewRepresentable {
    func makeUIView(context: Context) -> UIVisualEffectView {
        let view = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
        return view
    }

    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {}
}