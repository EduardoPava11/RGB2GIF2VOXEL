//
//  SimplifiedDualPathView.swift
//  RGB2GIF2VOXEL
//
//  Basic dual processing path demonstration using existing components
//

import SwiftUI

struct SimplifiedDualPathView: View {
    @State private var selectedPath: ProcessingPath = .swift
    @State private var showingPathSelector = false
    @State private var currentStage = "Ready to capture"
    @State private var frameCount = 0
    @State private var isProcessing = false
    
    var body: some View {
        VStack(spacing: 30) {
            // Header
            VStack(spacing: 8) {
                Text("Dual-Path Processing Demo")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Choose your processing method")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Current path display
            Button(action: { showingPathSelector = true }) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Current Path")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(selectedPath.displayName)
                            .font(.headline)
                            .foregroundColor(.primary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .foregroundColor(.accentColor)
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(PlainButtonStyle())
            
            // Status
            VStack(spacing: 12) {
                Text("Status: \(currentStage)")
                    .font(.body)
                    .foregroundColor(.primary)
                
                if frameCount > 0 {
                    Text("Frames captured: \(frameCount)/256")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if isProcessing {
                    ProgressView()
                        .scaleEffect(1.2)
                }
            }
            .frame(height: 80)
            
            // Demo actions
            VStack(spacing: 16) {
                Button("Start Demo Capture") {
                    startDemoCapture()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isProcessing)
                
                if frameCount > 0 {
                    Button("Process with \(selectedPath.displayName)") {
                        Task {
                            await processDemoFrames()
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isProcessing)
                }
                
                if frameCount > 0 || isProcessing {
                    Button("Reset") {
                        resetDemo()
                    }
                    .buttonStyle(.borderless)
                }
            }
            
            Spacer()
        }
        .padding()
        .sheet(isPresented: $showingPathSelector) {
            ProcessingPathSelectorView(selectedPath: $selectedPath)
        }
    }
    
    private func startDemoCapture() {
        currentStage = "Capturing frames..."
        frameCount = 0
        
        // Simulate frame capture
        Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { timer in
            frameCount += Int.random(in: 1...4)
            
            if frameCount >= 256 {
                frameCount = 256
                currentStage = "Capture complete - ready to process"
                timer.invalidate()
            }
        }
    }
    
    private func processDemoFrames() async {
        isProcessing = true
        
        switch selectedPath {
        case .rustFFI:
            await simulateRustProcessing()
        case .swift:
            await simulateSwiftProcessing()
        }
        
        isProcessing = false
        currentStage = "Processing complete!"
        
        // Auto-reset after delay
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        resetDemo()
    }
    
    private func simulateRustProcessing() async {
        let stages = [
            "🦀 Initializing Rust FFI...",
            "🦀 NeuQuant quantization...",
            "🦀 Palette optimization...",
            "🦀 Advanced dithering...",
            "🦀 GIF encoding...",
            "🦀 Generating tensor data..."
        ]
        
        for stage in stages {
            currentStage = stage
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        }
    }
    
    private func simulateSwiftProcessing() async {
        let stages = [
            "🍎 Starting Swift processing...",
            "🍎 vImage downsampling...",
            "🍎 ImageIO GIF encoding...",
            "🍎 Photos integration...",
            "🍎 Finalizing..."
        ]
        
        for stage in stages {
            currentStage = stage
            try? await Task.sleep(nanoseconds: 600_000_000) // 0.6 seconds
        }
    }
    
    private func resetDemo() {
        currentStage = "Ready to capture"
        frameCount = 0
        isProcessing = false
    }
}

// MARK: - Performance Comparison View

struct ProcessingComparisonView: View {
    @State private var showMetrics = false
    
    // Sample performance data
    private let performanceData = [
        ("Processing Speed", "🦀 1.2s", "🍎 2.1s"),
        ("Color Quality", "🦀 Excellent", "🍎 Good"),
        ("Compatibility", "🦀 Requires FFI", "🍎 Native"),
        ("Reliability", "🦀 85%", "🍎 98%"),
        ("Features", "🦀 Advanced", "🍎 Standard")
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button(action: { showMetrics.toggle() }) {
                HStack {
                    Text("Performance Comparison")
                        .font(.headline)
                    Spacer()
                    Image(systemName: showMetrics ? "chevron.up" : "chevron.down")
                }
            }
            .buttonStyle(PlainButtonStyle())
            
            if showMetrics {
                VStack(spacing: 0) {
                    // Header
                    HStack {
                        Text("Metric")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        Text("Rust FFI")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                        
                        Text("Swift Native")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                    }
                    .font(.caption)
                    .padding(.vertical, 8)
                    .background(Color.gray.opacity(0.1))
                    
                    // Data rows
                    ForEach(Array(performanceData.enumerated()), id: \.offset) { index, data in
                        HStack {
                            Text(data.0)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            
                            Text(data.1)
                                .frame(maxWidth: .infinity)
                            
                            Text(data.2)
                                .frame(maxWidth: .infinity)
                        }
                        .font(.caption)
                        .padding(.vertical, 6)
                        .background(index % 2 == 0 ? Color.clear : Color.gray.opacity(0.05))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .transition(.opacity.combined(with: .scale))
            }
        }
        .animation(.easeInOut, value: showMetrics)
    }
}

// MARK: - Preview

#Preview {
    SimplifiedDualPathView()
}

#Preview("Comparison") {
    ProcessingComparisonView()
        .padding()
}