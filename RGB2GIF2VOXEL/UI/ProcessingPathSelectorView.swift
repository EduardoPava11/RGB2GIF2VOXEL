//
//  ProcessingPathSelectorView.swift
//  RGB2GIF2VOXEL
//
//  UI component for selecting between Rust FFI and Swift processing paths
//

import SwiftUI

/// UI view for selecting processing path with feature comparison
struct ProcessingPathSelectorView: View {
    @Binding var selectedPath: ProcessingPath
    @State private var showDetails = false
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                Text("Choose Processing Path")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Select how your frames are processed into GIFs")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Path selection cards
            VStack(spacing: 12) {
                ForEach(ProcessingPath.allCases) { path in
                    ProcessingPathCard(
                        path: path,
                        isSelected: selectedPath == path,
                        onSelect: { selectedPath = path }
                    )
                }
            }
            
            // Details toggle
            Button(action: { showDetails.toggle() }) {
                HStack {
                    Text(showDetails ? "Hide Details" : "Show Details")
                    Image(systemName: showDetails ? "chevron.up" : "chevron.down")
                }
                .font(.caption)
                .foregroundColor(.accentColor)
            }
            
            // Feature comparison (expandable)
            if showDetails {
                FeatureComparisonView()
                    .transition(.opacity.combined(with: .scale))
            }
        }
        .padding()
        .animation(.easeInOut(duration: 0.3), value: showDetails)
    }
}

/// Individual processing path card
struct ProcessingPathCard: View {
    let path: ProcessingPath
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 16) {
                // Selection indicator
                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.3), lineWidth: 2)
                        .frame(width: 24, height: 24)
                    
                    if isSelected {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 16, height: 16)
                    }
                }
                
                // Path info
                VStack(alignment: .leading, spacing: 4) {
                    Text(path.displayName)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(path.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                }
                
                Spacer()
                
                // Status indicator
                pathStatusIndicator
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    @ViewBuilder
    private var pathStatusIndicator: some View {
        switch path {
        case .rustFFI:
            VStack(spacing: 2) {
                Image(systemName: "gearshape.2")
                    .foregroundColor(.orange)
                Text("Advanced")
                    .font(.caption2)
                    .foregroundColor(.orange)
            }
        case .swift:
            VStack(spacing: 2) {
                Image(systemName: "checkmark.shield")
                    .foregroundColor(.green)
                Text("Reliable")
                    .font(.caption2)
                    .foregroundColor(.green)
            }
        }
    }
}

/// Feature comparison table
struct FeatureComparisonView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Feature Comparison")
                .font(.headline)
                .padding(.bottom, 4)
            
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(Array(featureComparison.keys.sorted()), id: \.self) { feature in
                    FeatureRow(
                        feature: feature,
                        rustSupport: featureComparison[feature]?.rust ?? false,
                        swiftSupport: featureComparison[feature]?.swift ?? false
                    )
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.05))
        )
    }
    
    private var featureComparison: [String: (rust: Bool, swift: Bool)] {
        [
            "NeuQuant Color Quantization": (rust: true, swift: false),
            "Advanced Dithering": (rust: true, swift: false),
            "Palette Optimization": (rust: true, swift: false),
            "Multi-threading": (rust: true, swift: false),
            "Tensor Generation": (rust: true, swift: true),
            "Native iOS Integration": (rust: false, swift: true),
            "Photos Library Saving": (rust: false, swift: true),
            "Guaranteed Compatibility": (rust: false, swift: true),
            "Fallback Recovery": (rust: false, swift: true),
            "Performance Monitoring": (rust: true, swift: true)
        ]
    }
}

/// Individual feature comparison row
struct FeatureRow: View {
    let feature: String
    let rustSupport: Bool
    let swiftSupport: Bool
    
    var body: some View {
        HStack {
            Text(feature)
                .font(.caption)
                .foregroundColor(.primary)
            
            Spacer()
            
            // Rust support
            Image(systemName: rustSupport ? "checkmark.circle.fill" : "minus.circle")
                .foregroundColor(rustSupport ? .green : .gray.opacity(0.5))
                .frame(width: 40)
            
            // Swift support
            Image(systemName: swiftSupport ? "checkmark.circle.fill" : "minus.circle")
                .foregroundColor(swiftSupport ? .green : .gray.opacity(0.5))
                .frame(width: 40)
        }
    }
}

/// Processing path performance metrics view
struct PathMetricsView: View {
    let metrics: ProcessingMetrics
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Performance Metrics")
                .font(.headline)
            
            HStack(spacing: 20) {
                MetricCard(
                    title: "🦀 Rust Path",
                    reliability: "\(Int(metrics.rustReliability * 100))%",
                    averageTime: String(format: "%.1fs", metrics.averageRustTime),
                    successCount: metrics.rustSuccessCount,
                    failureCount: metrics.rustFailureCount
                )
                
                MetricCard(
                    title: "🍎 Swift Path", 
                    reliability: "\(Int(metrics.swiftReliability * 100))%",
                    averageTime: String(format: "%.1fs", metrics.averageSwiftTime),
                    successCount: metrics.swiftSuccessCount,
                    failureCount: metrics.swiftFailureCount
                )
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.1))
        )
    }
}

/// Individual metric card
struct MetricCard: View {
    let title: String
    let reliability: String
    let averageTime: String
    let successCount: Int
    let failureCount: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Reliability:")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(reliability)
                        .font(.caption2)
                        .fontWeight(.medium)
                }
                
                HStack {
                    Text("Avg Time:")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(averageTime)
                        .font(.caption2)
                        .fontWeight(.medium)
                }
                
                HStack {
                    Text("Success/Fail:")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(successCount)/\(failureCount)")
                        .font(.caption2)
                        .fontWeight(.medium)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.05))
        )
    }
}

// MARK: - Preview

#Preview("Path Selector") {
    ProcessingPathSelectorView(selectedPath: .constant(.swift))
        .padding()
}

#Preview("Feature Comparison") {
    FeatureComparisonView()
        .padding()
}

#Preview("Metrics") {
    PathMetricsView(
        metrics: ProcessingMetrics(
            processingTime: 2.3,
            paletteSize: 256,
            fileSize: 1024000
        )
    )
    .padding()
}