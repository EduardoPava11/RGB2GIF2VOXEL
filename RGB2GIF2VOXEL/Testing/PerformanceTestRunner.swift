// PerformanceTestRunner.swift
// Simple test runner for minimal performance validation

import Foundation
import SwiftUI
import Combine

public class PerformanceTestRunner: ObservableObject {
    @Published public var isRunning = false
    @Published public var results: PerformanceResults?
    @Published public var report: ValidationReport?
    
    private let testSuite = MinimalPerformanceTest()
    
    public init() {}
    
    /// Run performance tests asynchronously
    @MainActor
    public func runTests() async {
        isRunning = true
        results = nil
        report = nil
        
        // Run tests on background queue
        let testResults = await withTaskGroup(of: PerformanceResults.self) { group in
            group.addTask {
                return await self.testSuite.runBenchmarks()
            }
            // Wait for the first (and only) result from the group
            for await result in group {
                return result
            }
            // Fallback if no results
            return PerformanceResults(
                uikitResizeTime: -1,
                visionProcessingTime: -1,
                compressionTime: -1,
                compressionRatio: 1.0,
                timestamp: Date()
            )
        }
        
        results = testResults
        report = testSuite.validateClaims(testResults)
        isRunning = false
    }
    
    /// Get formatted results for display
    public var formattedResults: String {
        guard let results = results else { return "No results yet" }
        return results.summary
    }
    
    /// Get formatted validation report
    public var formattedReport: String {
        guard let report = report else { return "No validation report yet" }
        return report.report
    }
}

// MARK: - SwiftUI Test View

public struct PerformanceTestView: View {
    @StateObject private var runner = PerformanceTestRunner()
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 20) {
            Text("RGB2GIF2VOXEL Performance Validation")
                .font(.title2)
                .fontWeight(.bold)
            
            if runner.isRunning {
                ProgressView("Running performance tests...")
                    .progressViewStyle(CircularProgressViewStyle())
            } else {
                Button("Run Performance Tests") {
                    Task {
                        await runner.runTests()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(runner.isRunning)
            }
            
            if runner.results != nil {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Results:")
                        .font(.headline)
                    
                    Text(runner.formattedResults)
                        .font(.system(.body, design: .monospaced))
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                }
            }
            
            if let _ = runner.report {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Validation Report:")
                        .font(.headline)
                    
                    Text(runner.formattedReport)
                        .font(.system(.body, design: .monospaced))
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                }
            }
            
            Spacer()
        }
        .padding()
    }
}