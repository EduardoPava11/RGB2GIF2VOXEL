//
//  DebugOverlayView.swift
//  RGB2GIF2VOXEL
//
//  Debug overlay showing real-time performance metrics
//

import SwiftUI

struct DebugOverlayView: View {
    @ObservedObject var logger = PerformanceLogger.shared
    @State private var showingLogs = false
    @State private var isMinimized = false

    var body: some View {
        VStack {
            if isMinimized {
                // Minimized view - just FPS counter
                HStack {
                    Text(String(format: "%.0f FPS", logger.averageFPS))
                        .font(.caption.monospaced())
                        .foregroundColor(fpsColor)
                        .padding(4)
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(4)

                    Button(action: { isMinimized = false }) {
                        Image(systemName: "chevron.down.circle.fill")
                            .foregroundColor(.white)
                    }
                }
                .padding(4)
            } else {
                // Full overlay
                VStack(alignment: .leading, spacing: 4) {
                    // Header
                    HStack {
                        Text("🔍 Performance Monitor")
                            .font(.caption.bold())
                            .foregroundColor(.white)

                        Spacer()

                        Button(action: { isMinimized = true }) {
                            Image(systemName: "minus.circle.fill")
                                .foregroundColor(.white)
                        }
                    }

                    Divider().background(Color.white.opacity(0.3))

                    // Metrics
                    if let metrics = logger.currentMetrics {
                        MetricRow(label: "Frame", value: "#\(metrics.frameIndex)")
                        MetricRow(label: "Processing", value: String(format: "%.1fms", metrics.processingTimeMs),
                                 color: processingColor(metrics.processingTimeMs))
                        MetricRow(label: "Memory", value: String(format: "%.0fMB", metrics.memoryUsageMB),
                                 color: memoryColor(metrics.memoryUsageMB))
                        MetricRow(label: "CPU", value: String(format: "%.0f%%", metrics.cpuUsagePercent))
                        MetricRow(label: "FPS", value: String(format: "%.1f", metrics.fps),
                                 color: fpsColor(metrics.fps))
                        MetricRow(label: "Thermal", value: metrics.thermalState,
                                 color: thermalColor(metrics.thermalState))

                        if logger.totalDroppedFrames > 0 {
                            MetricRow(label: "Dropped", value: "\(logger.totalDroppedFrames)",
                                     color: .red)
                        }
                    } else {
                        Text("Waiting for data...")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }

                    Divider().background(Color.white.opacity(0.3))

                    // Actions
                    HStack(spacing: 8) {
                        Button(action: { showingLogs.toggle() }) {
                            Label("Logs", systemImage: "doc.text")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button(action: exportLogs) {
                            Label("Export", systemImage: "square.and.arrow.up")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding(8)
                .frame(width: 200)
                .background(Color.black.opacity(0.85))
                .cornerRadius(8)
            }
        }
        .sheet(isPresented: $showingLogs) {
            LogViewerSheet()
        }
    }

    // MARK: - Helpers

    private var fpsColor: Color {
        fpsColor(logger.averageFPS)
    }

    private func fpsColor(_ fps: Double) -> Color {
        if fps >= 25 { return .green }
        if fps >= 15 { return .yellow }
        return .red
    }

    private func processingColor(_ ms: Double) -> Color {
        if ms <= 40 { return .green }  // 25 FPS target
        if ms <= 66 { return .yellow } // 15 FPS
        return .red
    }

    private func memoryColor(_ mb: Double) -> Color {
        if mb < 200 { return .green }
        if mb < 400 { return .yellow }
        return .red
    }

    private func thermalColor(_ state: String) -> Color {
        switch state {
        case "Nominal": return .green
        case "Fair": return .yellow
        case "Serious": return .orange
        case "Critical": return .red
        default: return .gray
        }
    }

    private func exportLogs() {
        guard let logURL = logger.exportLogs() else { return }
        // Share logs via activity controller
        let activityVC = UIActivityViewController(activityItems: [logURL], applicationActivities: nil)

        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
    }
}

// MARK: - Metric Row

struct MetricRow: View {
    let label: String
    let value: String
    var color: Color = .white

    var body: some View {
        HStack {
            Text(label)
                .font(.caption.monospaced())
                .foregroundColor(.gray)
            Spacer()
            Text(value)
                .font(.caption.monospaced().bold())
                .foregroundColor(color)
        }
    }
}

// MARK: - Log Viewer

struct LogViewerSheet: View {
    @ObservedObject var logger = PerformanceLogger.shared
    @Environment(\.dismiss) var dismiss
    @State private var filterLevel: PerformanceLogger.LogLevel?

    var filteredLogs: [String] {
        guard let filter = filterLevel else { return logger.logMessages }
        return logger.logMessages.filter { $0.contains(filter.rawValue) }
    }

    var body: some View {
        NavigationView {
            VStack {
                // Filter
                Picker("Filter", selection: $filterLevel) {
                    Text("All").tag(nil as PerformanceLogger.LogLevel?)
                    ForEach([PerformanceLogger.LogLevel.debug, .info, .warning, .error, .performance], id: \.self) { level in
                        Text(level.rawValue).tag(level as PerformanceLogger.LogLevel?)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal)

                // Logs
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(filteredLogs.enumerated()), id: \.offset) { _, log in
                            Text(log)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundColor(logColor(for: log))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Performance Logs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func logColor(for log: String) -> Color {
        if log.contains("ERROR") { return .red }
        if log.contains("WARN") { return .yellow }
        if log.contains("PERF") { return .cyan }
        if log.contains("DEBUG") { return .gray }
        return .white
    }
}