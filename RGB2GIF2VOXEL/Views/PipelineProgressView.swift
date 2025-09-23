import SwiftUI
import Combine

/// Visual progress indicator for RGB→GIF→Voxel pipeline phases
public struct PipelineProgressView: View {
    @ObservedObject var viewModel: PipelineViewModel

    // Visual configuration
    private let phaseColors: [PipelineViewModel.Phase: Color] = [
        .idle: .gray,
        .capturing: .blue,
        .processing: .orange,
        .quantizing: .purple,
        .encoding: .green,
        .buildingTensor: .indigo,
        .saving: .teal,
        .complete: .green,
        .error: .red
    ]

    private let phaseIcons: [PipelineViewModel.Phase: String] = [
        .idle: "circle",
        .capturing: "camera.fill",
        .processing: "cpu",
        .quantizing: "paintpalette.fill",
        .encoding: "doc.zipper",
        .buildingTensor: "cube.fill",
        .saving: "square.and.arrow.down.fill",
        .complete: "checkmark.circle.fill",
        .error: "exclamationmark.triangle.fill"
    ]

    public var body: some View {
        VStack(spacing: 20) {
            // Current phase indicator
            currentPhaseCard

            // Progress bar
            progressBar

            // Phase timeline
            phaseTimeline

            // Statistics
            if viewModel.showStatistics {
                statisticsCard
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.1), radius: 10)
    }

    // MARK: - Current Phase Card

    private var currentPhaseCard: some View {
        HStack(spacing: 16) {
            // Animated icon
            Group {
                if #available(iOS 17.0, *) {
                    Image(systemName: phaseIcons[viewModel.currentPhase] ?? "circle")
                        .font(.system(size: 32))
                        .foregroundColor(phaseColors[viewModel.currentPhase])
                        .symbolEffect(.pulse, isActive: viewModel.isProcessing)
                } else {
                    Image(systemName: phaseIcons[viewModel.currentPhase] ?? "circle")
                        .font(.system(size: 32))
                        .foregroundColor(phaseColors[viewModel.currentPhase])
                        .opacity(viewModel.isProcessing ? 0.6 : 1.0)
                        .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: viewModel.isProcessing)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.currentPhase.displayName)
                    .font(.headline)
                    .foregroundColor(.primary)

                if let message = viewModel.statusMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            // Frame counter
            if viewModel.currentPhase == .capturing {
                frameCounter
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    // MARK: - Frame Counter

    private var frameCounter: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text("\(viewModel.framesProcessed)")
                .font(.system(size: 24, weight: .semibold, design: .monospaced))
                .foregroundColor(.blue)

            Text("of \(viewModel.totalFrames)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Labels
            HStack {
                Text("Progress")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Text("\(Int(viewModel.overallProgress * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
            }

            // Bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemFill))
                        .frame(height: 8)

                    // Progress
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    phaseColors[viewModel.currentPhase] ?? .blue,
                                    (phaseColors[viewModel.currentPhase] ?? .blue).opacity(0.7)
                                ]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * viewModel.overallProgress, height: 8)
                        .animation(.easeInOut(duration: 0.3), value: viewModel.overallProgress)
                }
            }
            .frame(height: 8)

            // ETA
            if let eta = viewModel.estimatedTimeRemaining {
                Text("ETA: \(Int(eta))s")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Phase Timeline

    private var phaseTimeline: some View {
        HStack(spacing: 0) {
            ForEach(PipelineViewModel.Phase.processingPhases, id: \.self) { phase in
                phaseStep(for: phase)
                if phase != PipelineViewModel.Phase.processingPhases.last {
                    phaseLine(for: phase)
                }
            }
        }
        .frame(height: 60)
    }

    private func phaseStep(for phase: PipelineViewModel.Phase) -> some View {
        VStack(spacing: 4) {
            // Icon
            ZStack {
                Circle()
                    .fill(stepColor(for: phase))
                    .frame(width: 32, height: 32)

                if viewModel.completedPhases.contains(phase) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                } else {
                    Image(systemName: phaseIcons[phase] ?? "circle")
                        .font(.system(size: 14))
                        .foregroundColor(viewModel.currentPhase == phase ? .white : Color(.systemGray3))
                }
            }

            // Label
            Text(phase.shortName)
                .font(.system(size: 9))
                .foregroundColor(viewModel.completedPhases.contains(phase) || viewModel.currentPhase == phase ? .primary : .secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private func phaseLine(for phase: PipelineViewModel.Phase) -> some View {
        Rectangle()
            .fill(viewModel.completedPhases.contains(phase) ? Color.green : Color(.systemFill))
            .frame(height: 2)
            .frame(maxWidth: .infinity)
    }

    private func stepColor(for phase: PipelineViewModel.Phase) -> Color {
        if viewModel.completedPhases.contains(phase) {
            return .green
        } else if viewModel.currentPhase == phase {
            return phaseColors[phase] ?? .blue
        } else {
            return Color(.systemFill)
        }
    }

    // MARK: - Statistics Card

    private var statisticsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Statistics")
                .font(.caption)
                .foregroundColor(.secondary)

            VStack(spacing: 8) {
                statRow("Frames", value: "\(viewModel.framesProcessed)/\(viewModel.totalFrames)")
                statRow("Memory", value: formatMemory(viewModel.memoryUsed))
                statRow("FPS", value: String(format: "%.1f", viewModel.currentFPS))
                if viewModel.outputSize > 0 {
                    statRow("Output Size", value: formatBytes(viewModel.outputSize))
                }
            }
        }
        .padding()
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(8)
    }

    private func statRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption.monospacedDigit())
                .foregroundColor(.primary)
        }
    }

    // MARK: - Formatting Helpers

    private func formatMemory(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .memory)
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

// MARK: - Pipeline ViewModel

@MainActor
public class PipelineViewModel: ObservableObject {

    // MARK: - Phase Definition
    public enum Phase: String, CaseIterable {
        case idle = "Ready"
        case capturing = "Capturing"
        case processing = "Processing"
        case quantizing = "Quantizing"
        case encoding = "Encoding"
        case buildingTensor = "Building Tensor"
        case saving = "Saving"
        case complete = "Complete"
        case error = "Error"

        var displayName: String { rawValue }

        var shortName: String {
            switch self {
            case .idle: return "Ready"
            case .capturing: return "Capture"
            case .processing: return "Process"
            case .quantizing: return "Quantize"
            case .encoding: return "Encode"
            case .buildingTensor: return "Tensor"
            case .saving: return "Save"
            case .complete: return "Done"
            case .error: return "Error"
            }
        }

        static var processingPhases: [Phase] {
            [.capturing, .processing, .quantizing, .encoding, .buildingTensor, .saving]
        }
    }

    // MARK: - Published Properties
    @Published public var currentPhase: Phase = .idle
    @Published public var overallProgress: Double = 0.0
    @Published public var framesProcessed: Int = 0
    @Published public var totalFrames: Int = 256
    @Published public var statusMessage: String?
    @Published public var isProcessing: Bool = false
    @Published public var completedPhases: Set<Phase> = []
    @Published public var showStatistics: Bool = true

    // Statistics
    @Published public var memoryUsed: Int64 = 0
    @Published public var currentFPS: Double = 0.0
    @Published public var outputSize: Int64 = 0
    @Published public var estimatedTimeRemaining: TimeInterval?

    // Timing
    private var phaseStartTime: Date?
    private var pipelineStartTime: Date?
    private var frameTimings: [TimeInterval] = []

    // MARK: - Phase Management

    public func startPhase(_ phase: Phase) {
        currentPhase = phase
        phaseStartTime = Date()

        if pipelineStartTime == nil {
            pipelineStartTime = Date()
        }

        isProcessing = true
        statusMessage = "Starting \(phase.displayName.lowercased())..."

        // Update progress based on phase
        switch phase {
        case .capturing:
            overallProgress = 0.0
        case .processing:
            overallProgress = 0.2
        case .quantizing:
            overallProgress = 0.4
        case .encoding:
            overallProgress = 0.6
        case .buildingTensor:
            overallProgress = 0.8
        case .saving:
            overallProgress = 0.9
        default:
            break
        }
    }

    public func completePhase(_ phase: Phase) {
        completedPhases.insert(phase)

        if let startTime = phaseStartTime {
            let duration = Date().timeIntervalSince(startTime)
            print("Phase \(phase.displayName) completed in \(String(format: "%.2f", duration))s")
        }

        // Auto-advance to next phase
        if let nextPhase = nextPhase(after: phase) {
            startPhase(nextPhase)
        } else {
            completePipeline()
        }
    }

    private func nextPhase(after phase: Phase) -> Phase? {
        let phases = Phase.processingPhases
        guard let currentIndex = phases.firstIndex(of: phase),
              currentIndex < phases.count - 1 else {
            return nil
        }
        return phases[currentIndex + 1]
    }

    public func completePipeline() {
        currentPhase = .complete
        overallProgress = 1.0
        isProcessing = false
        statusMessage = "Pipeline complete!"

        if let startTime = pipelineStartTime {
            let totalTime = Date().timeIntervalSince(startTime)
            print("Pipeline completed in \(String(format: "%.2f", totalTime))s")
        }
    }

    public func setError(_ message: String) {
        currentPhase = .error
        isProcessing = false
        statusMessage = message
        overallProgress = 0.0
    }

    // MARK: - Progress Updates

    public func updateFrameProgress(_ current: Int, total: Int) {
        framesProcessed = current
        totalFrames = total

        // Update overall progress based on frames
        if currentPhase == .capturing {
            overallProgress = Double(current) / Double(total) * 0.2
        }

        // Calculate FPS
        if frameTimings.count > 0 {
            let averageFrameTime = frameTimings.reduce(0, +) / Double(frameTimings.count)
            currentFPS = 1.0 / averageFrameTime
        }

        // Estimate time remaining
        if current > 0 && current < total {
            let framesRemaining = total - current
            let averageTimePerFrame = frameTimings.isEmpty ? 0.033 : frameTimings.reduce(0, +) / Double(frameTimings.count)
            estimatedTimeRemaining = Double(framesRemaining) * averageTimePerFrame
        }
    }

    public func recordFrameTiming(_ timing: TimeInterval) {
        frameTimings.append(timing)
        // Keep only last 30 frame timings for rolling average
        if frameTimings.count > 30 {
            frameTimings.removeFirst()
        }
    }

    // MARK: - Reset

    public func reset() {
        currentPhase = .idle
        overallProgress = 0.0
        framesProcessed = 0
        statusMessage = nil
        isProcessing = false
        completedPhases.removeAll()
        frameTimings.removeAll()
        pipelineStartTime = nil
        phaseStartTime = nil
        estimatedTimeRemaining = nil
    }
}

// MARK: - Preview

struct PipelineProgressView_Previews: PreviewProvider {
    static var previews: some View {
        let viewModel = PipelineViewModel()
        viewModel.currentPhase = .quantizing
        viewModel.overallProgress = 0.45
        viewModel.framesProcessed = 115
        viewModel.completedPhases = [.capturing, .processing]
        viewModel.memoryUsed = 157_286_400
        viewModel.currentFPS = 28.5

        return PipelineProgressView(viewModel: viewModel)
            .previewLayout(.sizeThatFits)
            .padding()
    }
}