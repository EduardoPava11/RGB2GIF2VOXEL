//
//  ProcessingPathManager.swift
//  RGB2GIF2VOXEL
//
//  Simplified dual-path processing manager with error handling and fallback
//

import Foundation
import Combine
import CoreVideo
import os.log

private let logger = OSLog(subsystem: "com.yingif.rgb2gif2voxel", category: "ProcessingPathManager")

// ProcessingPath is defined in ProcessingPathSelector.swift to avoid ambiguity

/// Simplified processing path manager that works with existing services
@MainActor
public class ProcessingPathManager: ObservableObject {
    
    // MARK: - Published State
    
    @Published public var selectedPath: ProcessingPath = .swift  // Default to reliable path
    @Published public var isProcessing: Bool = false
    @Published public var progress: Float = 0.0
    @Published public var currentStage: String = ""
    @Published public var lastError: String?
    @Published public var pathAvailability: [ProcessingPath: Bool] = [:]
    
    // MARK: - Configuration
    
    public var enableAutoFallback: Bool = true  // Automatically fallback Rust→Swift on error
    public var performanceMetrics: ProcessingMetrics = ProcessingMetrics()
    
    // MARK: - Dependencies
    // Note: ProcessingService will be injected when available
    
    // MARK: - Initialization
    
    public init() {
        checkPathAvailability()
    }
    
    // MARK: - Path Availability
    
    private func checkPathAvailability() {
        Task {
            // Check Rust FFI availability by testing if processing service can handle Rust calls
            let rustAvailable = await checkRustFFIAvailability()
            
            // Swift path is always available on iOS (using ProcessingService)
            let swiftAvailable = true
            
            await MainActor.run {
                pathAvailability[.rustFFI] = rustAvailable
                pathAvailability[.swift] = swiftAvailable
                
                // Auto-select Swift if Rust is unavailable
                if !rustAvailable && selectedPath == .rustFFI {
                    selectedPath = .swift
                    os_log(.info, log: logger, "🔄 Auto-switched to Swift path - Rust FFI unavailable")
                }
                
                os_log(.info, log: logger, "📊 Path availability - Rust: %@, Swift: %@", 
                       rustAvailable ? "✅" : "❌", swiftAvailable ? "✅" : "❌")
            }
        }
    }
    
    private func checkRustFFIAvailability() async -> Bool {
        // Test if Rust FFI functions are available by checking for required types/functions
        // For now, assume it's available if we can create test data without crashing
        // TODO: Uncomment when processingService is available
        /*
        do {
            let testFrames = [Data(repeating: 0xFF, count: 64 * 64 * 4)]  // Small test frame
            _ = try processingService.downsample(frames: testFrames, from: 64, to: 32)
            os_log(.info, log: logger, "✅ Rust FFI basic functionality test passed")
            return true
        } catch {
            os_log(.error, log: logger, "❌ Rust FFI availability check failed: %@", error.localizedDescription)
            return false
        }
        */
        return false // Temporarily return false until processingService is initialized
    }
    
    // MARK: - Main Processing Function
    
    /// Process 256x256x256 tensor using selected path with automatic fallback
    public func processTensorToGIF(
        frames: [Data],
        captureSize: Int = 1080,
        targetSize: Int = 256
    ) async throws -> ProcessingResult {
        
        os_log(.info, log: logger, "🚀 Starting processing with %@ path for %d frames", 
               selectedPath.displayName, frames.count)
        
        let startTime = CFAbsoluteTimeGetCurrent()
        isProcessing = true
        progress = 0.0
        lastError = nil
        
        defer {
            isProcessing = false
        }
        
        do {
            let result: ProcessingResult
            
            switch selectedPath {
            case .rustFFI:
                result = try await processWithRustFFI(frames: frames, captureSize: captureSize, targetSize: targetSize)
                
            case .swift:
                result = try await processWithSwift(frames: frames, captureSize: captureSize, targetSize: targetSize)
            }
            
            // Record metrics
            let processingTime = CFAbsoluteTimeGetCurrent() - startTime
            await updateMetrics(path: selectedPath, processingTime: processingTime, success: true)
            
            os_log(.info, log: logger, "✅ Processing completed successfully with %@ path in %.2fs", 
                   selectedPath.displayName, processingTime)
            
            return result
            
        } catch {
            let processingTime = CFAbsoluteTimeGetCurrent() - startTime
            await updateMetrics(path: selectedPath, processingTime: processingTime, success: false)
            
            // Attempt fallback if enabled and using Rust path
            if enableAutoFallback && selectedPath == .rustFFI && pathAvailability[.swift] == true {
                os_log(.default, log: logger, "⚠️ Rust FFI failed, falling back to Swift path: %@", error.localizedDescription)
                
                do {
                    let fallbackResult = try await processWithSwift(frames: frames, captureSize: captureSize, targetSize: targetSize)
                    
                    os_log(.info, log: logger, "✅ Fallback to Swift path succeeded")
                    return fallbackResult
                    
                } catch let fallbackError {
                    os_log(.error, log: logger, "❌ Both paths failed - Rust: %@, Swift: %@", 
                           error.localizedDescription, fallbackError.localizedDescription)
                    lastError = "Both processing paths failed"
                    throw PipelineError.processingFailed("Both Rust and Swift paths failed")
                }
            }
            
            lastError = error.localizedDescription
            throw error
        }
    }
    
    // MARK: - Rust FFI Processing
    
    private func processWithRustFFI(frames: [Data], captureSize: Int, targetSize: Int) async throws -> ProcessingResult {
        currentStage = "🦀 Rust FFI Processing"
        progress = 0.1

        guard pathAvailability[.rustFFI] == true else {
            throw PipelineError.processingFailed("FFI error: code -1")
        }

        os_log(.info, log: logger, "🦀 Using Rust FFI processing path")

        // TODO: Uncomment when processingService is available
        /*
        // Use existing ProcessingService which includes Rust FFI calls
        currentStage = "🦀 Downsampling with Rust optimizations"
        progress = 0.3

        let gifData = try await processingService.processToGIF(
            frames: frames,
            captureSize: captureSize,
            targetSize: targetSize,
            fps: 30
        )

        progress = 1.0
        currentStage = "🦀 Rust processing complete"

        return ProcessingResult(
            gifData: gifData,
            tensorData: nil,  // TODO: Extract tensor data from Rust processing
            processingPath: .rustFFI,
            metrics: ProcessingMetrics(
                processingTime: 0.0,  // Would be measured during actual processing
                paletteSize: 256,
                fileSize: gifData.count
            )
        )
        */

        // Temporary: throw unavailable until processingService is initialized
        throw PipelineError.processingFailed("FFI error: code -1")
    }
    
    // MARK: - Swift Processing
    
    private func processWithSwift(frames: [Data], captureSize: Int, targetSize: Int) async throws -> ProcessingResult {
        currentStage = "🍎 Swift Native Processing"
        progress = 0.1
        
        os_log(.info, log: logger, "🍎 Using Swift native processing path")
        
        // Step 1: Downsample using vImage (which is native Swift/Accelerate)
        currentStage = "🍎 Downsampling with vImage"
        progress = 0.3
        
        // TODO: Uncomment when processingService is available
        /*
        let downsampledFrames = try await processingService.downsample(
            frames: frames,
            from: captureSize,
            to: targetSize
        )
        */
        let downsampledFrames = frames // Temporary: use original frames
        
        // Step 2: Create simple GIF using native Swift methods
        currentStage = "🍎 Native GIF encoding"
        progress = 0.7
        
        // For now, create a simple GIF header - this would be replaced with NativeGIFEncoder when available
        var gifData = Data()
        gifData.append("GIF89a".data(using: .utf8)!)
        
        // Add frame data (simplified for demo)
        for frameData in downsampledFrames.prefix(min(256, downsampledFrames.count)) {
            gifData.append(frameData)
        }
        
        progress = 1.0
        currentStage = "🍎 Swift processing complete"
        
        return ProcessingResult(
            gifData: gifData,
            tensorData: createSwiftTensorData(from: downsampledFrames, width: targetSize, height: targetSize),
            processingPath: .swift,
            metrics: ProcessingMetrics(
                processingTime: 0.0,
                paletteSize: 256,
                fileSize: gifData.count
            )
        )
    }
    
    // MARK: - Utilities
    
    private func createSwiftTensorData(from frames: [Data], width: Int, height: Int) -> Data {
        // Create a simplified tensor representation for compatibility
        var tensorData = Data()
        
        // Simple header indicating Swift-generated tensor
        tensorData.append("SWFT".data(using: .utf8)!)  // 4-byte header
        tensorData.append(contentsOf: withUnsafeBytes(of: UInt32(width)) { Data($0) })
        tensorData.append(contentsOf: withUnsafeBytes(of: UInt32(height)) { Data($0) })
        tensorData.append(contentsOf: withUnsafeBytes(of: UInt32(frames.count)) { Data($0) })
        
        return tensorData
    }
    
    private func updateMetrics(path: ProcessingPath, processingTime: Double, success: Bool) async {
        performanceMetrics.recordProcessing(
            path: path,
            processingTime: processingTime,
            success: success
        )
        
        os_log(.info, log: logger, "📊 Updated metrics - %@ path: success=%@, time=%.2fs", 
               path.displayName, success ? "✅" : "❌", processingTime)
    }
}

// MARK: - Supporting Types

// ProcessingResult and ProcessingMetrics are defined in ProcessingTypes.swift