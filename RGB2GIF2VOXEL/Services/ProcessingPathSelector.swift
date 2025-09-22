//
//  ProcessingPathSelector.swift
//  RGB2GIF2VOXEL
//
//  Manages choice between Rust FFI (advanced) and Swift (reliable) processing paths
//

import Foundation
import Combine
import CoreVideo
import os.log

private let logger = OSLog(subsystem: "com.yingif.rgb2gif2voxel", category: "ProcessingPathSelector")

// ProcessingPath and related types are defined in ProcessingTypes.swift

/// Service that manages dual processing paths and user selection
@MainActor
public class ProcessingPathSelector: ObservableObject {
    
    // MARK: - Published State
    
    @Published public var selectedPath: ProcessingPath = .swift  // Default to reliable path
    @Published public var isProcessing: Bool = false
    @Published public var progress: Float = 0.0
    @Published public var currentStage: String = ""
    @Published public var lastError: ProcessingError?
    @Published public var pathAvailability: [ProcessingPath: Bool] = [:]
    
    // MARK: - Processing Components
    
    // TODO: These will be initialized when dependencies are available
    // private var rustProcessor: RustProcessor?
    // private var swiftEncoder: NativeGIFEncoder?
    
    // MARK: - Configuration
    
    public var enableAutoFallback: Bool = true  // Automatically fallback Rust→Swift on error
    public var performanceMetrics: ProcessingMetrics = ProcessingMetrics()
    
    // MARK: - Initialization
    
    public init() {
        checkPathAvailability()
        setupBindings()
    }
    
    private func setupBindings() {
        // TODO: Bind processor state when available
        // For now, just initialize with default values
    }
    
    // MARK: - Path Availability
    
    private func checkPathAvailability() {
        Task {
            // Check Rust FFI availability
            let rustAvailable = await checkRustFFIAvailability()
            
            // Swift path is always available on iOS
            let swiftAvailable = true
            
            await MainActor.run {
                pathAvailability[.rustFFI] = rustAvailable
                pathAvailability[.swift] = swiftAvailable
                
                // Auto-select Swift if Rust is unavailable
                if !rustAvailable && selectedPath == .rustFFI {
                    selectedPath = .swift
                    os_log(.info, log: logger, "🔄 Auto-switched to Swift path - Rust FFI unavailable")
                }
            }
        }
    }
    
    private func checkRustFFIAvailability() async -> Bool {
        // Test if Rust FFI bindings are properly linked and functional
        // TODO: Uncomment when rustProcessor is initialized
        /*
        do {
            // Try a minimal Rust FFI call to test connectivity
            let testFrames = [Data(repeating: 0xFF, count: 256 * 256 * 4)]  // Single white frame
            let result = await rustProcessor.processFramesToGIF(
                frames: testFrames,
                width: 256,
                height: 256
            )
            return result != nil
        } catch {
            os_log(.error, log: logger, "❌ Rust FFI availability check failed: %@", error.localizedDescription)
            return false
        }
        */
        return false  // Rust not available until initialized
    }
    
    // MARK: - Main Processing Function
    
    /// Process 256x256x256 tensor using selected path with automatic fallback
    public func processTensorToGIF(
        frames: [Data],
        width: Int = 256,
        height: Int = 256
    ) async throws -> ProcessingResult {
        
        os_log(.info, log: logger, "🚀 Starting processing with %@ path", selectedPath.displayName)
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        do {
            let result: ProcessingResult
            
            switch selectedPath {
            case .rustFFI:
                result = try await processWithRustFFI(frames: frames, width: width, height: height)
                
            case .swift:
                result = try await processWithSwift(frames: frames, width: width, height: height)
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
                os_log(.info, log: logger, "⚠️ Rust FFI failed, falling back to Swift path: %@", error.localizedDescription)
                
                do {
                    let fallbackResult = try await processWithSwift(frames: frames, width: width, height: height)
                    
                    os_log(.info, log: logger, "✅ Fallback to Swift path succeeded")
                    return fallbackResult
                    
                } catch let fallbackError {
                    os_log(.error, log: logger, "❌ Both paths failed - Rust: %@, Swift: %@", 
                           error.localizedDescription, fallbackError.localizedDescription)
                    throw ProcessingError.bothPathsFailed(rustError: error, swiftError: fallbackError)
                }
            }
            
            throw error
        }
    }
    
    // MARK: - Rust FFI Processing
    
    private func processWithRustFFI(frames: [Data], width: Int, height: Int) async throws -> ProcessingResult {
        currentStage = "🦀 Rust FFI Processing"

        guard pathAvailability[.rustFFI] == true else {
            throw ProcessingError.pathUnavailable(.rustFFI)
        }

        // TODO: Uncomment when rustProcessor is initialized
        /*
        // Configure Rust processor for optimal quality
        rustProcessor.setQuantizationSpeed(3)  // High quality
        rustProcessor.setDimensions(width: UInt16(width), height: UInt16(height))
        rustProcessor.setFrameRate(30)
        rustProcessor.setIncludeTensor(true)  // Generate tensor data

        guard let rustResult = await rustProcessor.processFramesToGIF(
            frames: frames,
            width: width,
            height: height
        ) else {
            throw ProcessingError.rustProcessingFailed
        }

        return ProcessingResult(
            gifData: rustResult.gifData,
            tensorData: rustResult.tensorData,
            processingPath: .rustFFI,
            metrics: ProcessingMetrics(
                processingTime: Double(rustResult.processingTimeMs) / 1000.0,
                paletteSize: Int(rustResult.paletteSizeUsed),
                fileSize: Int(rustResult.finalFileSize)
            )
        )
        */

        // Temporary: throw unavailable until rustProcessor is initialized
        throw ProcessingError.pathUnavailable(.rustFFI)
    }
    
    // MARK: - Swift Processing

    private func processWithSwift(frames: [Data], width: Int, height: Int) async throws -> ProcessingResult {
        currentStage = "🍎 Swift Native Processing"

        // Convert Data frames to CVPixelBuffers for NativeGIFEncoder
        var pixelBuffers: [CVPixelBuffer] = []

        for frameData in frames {
            guard let pixelBuffer = createPixelBuffer(from: frameData, width: width, height: height) else {
                throw ProcessingError.swiftProcessingFailed(reason: "Failed to create pixel buffer")
            }
            pixelBuffers.append(pixelBuffer)
        }

        // Configure Swift encoder
        let config = NativeGIFEncoder.Configuration(
            frameDelay: 1.0/30.0,  // 30 FPS
            loopCount: 0,          // Infinite loop
            quality: 0.8,          // High quality
            enableDithering: true,
            colorCount: 256
        )

        // TODO: Uncomment when swiftEncoder is initialized
        /*
        // Process with Swift encoder
        let gifData = try await swiftEncoder.encodeGIF(frames: pixelBuffers, config: config)

        // Create a simple tensor representation (Swift doesn't generate same format as Rust)
        let tensorData = createSwiftTensorData(from: frames, width: width, height: height)

        return ProcessingResult(
            gifData: gifData,
            tensorData: tensorData,
            processingPath: .swift,
            metrics: ProcessingMetrics(
                processingTime: 0.0,  // Would be measured during actual processing
                paletteSize: 256,     // Swift uses fixed palette size
                fileSize: gifData.count
            )
        )
        */

        // Temporary: throw unavailable until swiftEncoder is initialized
        throw ProcessingError.pathUnavailable(.swift)
    }
    
    // MARK: - Utilities
    
    private func createPixelBuffer(from data: Data, width: Int, height: Int) -> CVPixelBuffer? {
        let attributes: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        
        var pixelBuffer: CVPixelBuffer?
        let result = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &pixelBuffer
        )
        
        guard result == kCVReturnSuccess, let buffer = pixelBuffer else {
            return nil
        }
        
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else {
            return nil
        }
        
        data.withUnsafeBytes { bytes in
            memcpy(baseAddress, bytes.baseAddress, min(data.count, width * height * 4))
        }
        
        return buffer
    }
    
    private func createSwiftTensorData(from frames: [Data], width: Int, height: Int) -> Data {
        // Create a simplified tensor representation for compatibility
        // Real tensor would require the same quantization as Rust path
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
    }
}

// MARK: - Supporting Types
// ProcessingResult and ProcessingMetrics are defined in ProcessingTypes.swift

// MARK: - Error Extensions

extension ProcessingError {
    static func pathUnavailable(_ path: ProcessingPath) -> ProcessingError {
        return .invalidInput // Extend this enum to include pathUnavailable case
    }
    
    static let rustProcessingFailed = ProcessingError.invalidInput // Extend this enum
    
    static func swiftProcessingFailed(reason: String) -> ProcessingError {
        return .invalidInput // Extend this enum
    }
    
    static func bothPathsFailed(rustError: Error, swiftError: Error) -> ProcessingError {
        return .invalidInput // Extend this enum with both errors
    }
}