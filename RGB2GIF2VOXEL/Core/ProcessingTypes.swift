//
//  ProcessingTypes.swift
//  RGB2GIF2VOXEL
//
//  Shared types for dual processing path system
//

import Foundation

// MARK: - Processing Path Types

/// Processing path options available to user
public enum ProcessingPath: String, CaseIterable, Identifiable {
    case rustFFI = "Rust FFI"
    case swift = "Swift Native"
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .rustFFI:
            return "🦀 Advanced Path"
        case .swift:
            return "🍎 Reliable Path"
        }
    }
    
    public var description: String {
        switch self {
        case .rustFFI:
            return "High-performance Rust processing with advanced quantization"
        case .swift:
            return "Native iOS processing with ImageIO framework"
        }
    }
    
    public var features: [String] {
        switch self {
        case .rustFFI:
            return [
                "NeuQuant color quantization",
                "Optimized palette generation", 
                "Advanced dithering algorithms",
                "Tensor data generation",
                "Multi-threaded processing"
            ]
        case .swift:
            return [
                "Native iOS ImageIO encoding",
                "Guaranteed compatibility",
                "Photos library integration",
                "Progress tracking",
                "Fallback reliability"
            ]
        }
    }
}

// MARK: - Processing Result Types

public struct ProcessingResult {
    public let gifData: Data
    public let tensorData: Data?
    public let processingPath: ProcessingPath
    public let metrics: ProcessingMetrics
    public let processingTime: TimeInterval
    
    public init(gifData: Data, tensorData: Data?, processingPath: ProcessingPath, metrics: ProcessingMetrics, processingTime: TimeInterval = 0.0) {
        self.gifData = gifData
        self.tensorData = tensorData
        self.processingPath = processingPath
        self.metrics = metrics
        self.processingTime = processingTime
    }
}

// MARK: - Performance Metrics

public struct ProcessingMetrics {
    public var processingTime: Double
    public var paletteSize: Int
    public var fileSize: Int
    
    // Reliability tracking
    public var rustSuccessCount: Int
    public var rustFailureCount: Int
    public var swiftSuccessCount: Int
    public var swiftFailureCount: Int
    public var averageRustTime: Double
    public var averageSwiftTime: Double
    
    public init(
        processingTime: Double = 0.0,
        paletteSize: Int = 256,
        fileSize: Int = 0
    ) {
        self.processingTime = processingTime
        self.paletteSize = paletteSize
        self.fileSize = fileSize
        
        // Initialize with sample data for demo
        self.rustSuccessCount = 17
        self.rustFailureCount = 3
        self.swiftSuccessCount = 24
        self.swiftFailureCount = 1
        self.averageRustTime = 1.2
        self.averageSwiftTime = 2.1
    }
    
    public var rustReliability: Double {
        let total = rustSuccessCount + rustFailureCount
        return total > 0 ? Double(rustSuccessCount) / Double(total) : 0.0
    }
    
    public var swiftReliability: Double {
        let total = swiftSuccessCount + swiftFailureCount
        return total > 0 ? Double(swiftSuccessCount) / Double(total) : 0.0
    }
    
    public mutating func recordProcessing(path: ProcessingPath, processingTime: Double, success: Bool) {
        switch path {
        case .rustFFI:
            if success {
                rustSuccessCount += 1
                averageRustTime = (averageRustTime * Double(rustSuccessCount - 1) + processingTime) / Double(rustSuccessCount)
            } else {
                rustFailureCount += 1
            }
        case .swift:
            if success {
                swiftSuccessCount += 1
                averageSwiftTime = (averageSwiftTime * Double(swiftSuccessCount - 1) + processingTime) / Double(swiftSuccessCount)
            } else {
                swiftFailureCount += 1
            }
        }
    }
}

// MARK: - Processing Configuration

public struct ProcessingConfiguration {
    public let targetSize: Int
    public let frameCount: Int
    public let qualityLevel: Float
    public let enableDithering: Bool
    public let generateTensor: Bool
    
    public init(
        targetSize: Int = 256,
        frameCount: Int = 256,
        qualityLevel: Float = 0.8,
        enableDithering: Bool = true,
        generateTensor: Bool = false
    ) {
        self.targetSize = targetSize
        self.frameCount = frameCount
        self.qualityLevel = qualityLevel
        self.enableDithering = enableDithering
        self.generateTensor = generateTensor
    }
    
    public static let defaultConfig = ProcessingConfiguration()
    
    public static let highQualityConfig = ProcessingConfiguration(
        targetSize: 256,
        frameCount: 256,
        qualityLevel: 0.95,
        enableDithering: true,
        generateTensor: true
    )
}

// MARK: - Processing State

public enum ProcessingState: Equatable {
    case idle
    case capturing(frameCount: Int)
    case processing(stage: String, progress: Float)
    case complete(result: ProcessingResult)
    case error(message: String)
    
    public static func == (lhs: ProcessingState, rhs: ProcessingState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle):
            return true
        case let (.capturing(lhsCount), .capturing(rhsCount)):
            return lhsCount == rhsCount
        case let (.processing(lhsStage, lhsProgress), .processing(rhsStage, rhsProgress)):
            return lhsStage == rhsStage && lhsProgress == rhsProgress
        case (.complete, .complete):
            return true
        case let (.error(lhsMessage), .error(rhsMessage)):
            return lhsMessage == rhsMessage
        default:
            return false
        }
    }
    
    public var isProcessing: Bool {
        switch self {
        case .processing:
            return true
        default:
            return false
        }
    }
    
    public var isCapturing: Bool {
        switch self {
        case .capturing:
            return true
        default:
            return false
        }
    }
}

// MARK: - Path Availability

public struct PathAvailability {
    public let rustFFIAvailable: Bool
    public let swiftAvailable: Bool
    public let recommendedPath: ProcessingPath
    public let lastChecked: Date
    
    public init(
        rustFFIAvailable: Bool,
        swiftAvailable: Bool = true,
        lastChecked: Date = Date()
    ) {
        self.rustFFIAvailable = rustFFIAvailable
        self.swiftAvailable = swiftAvailable
        self.recommendedPath = rustFFIAvailable ? .rustFFI : .swift
        self.lastChecked = lastChecked
    }
    
    public func isAvailable(_ path: ProcessingPath) -> Bool {
        switch path {
        case .rustFFI:
            return rustFFIAvailable
        case .swift:
            return swiftAvailable
        }
    }
}

// MARK: - Processing Errors

public enum ProcessingPathError: LocalizedError {
    case pathUnavailable(ProcessingPath)
    case bothPathsFailed(rustError: Error, swiftError: Error)
    case configurationError(String)
    
    public var errorDescription: String? {
        switch self {
        case .pathUnavailable(let path):
            return "\(path.displayName) processing path is unavailable"
        case .bothPathsFailed(let rustError, let swiftError):
            return "Both processing paths failed: Rust(\(rustError.localizedDescription)), Swift(\(swiftError.localizedDescription))"
        case .configurationError(let message):
            return "Configuration error: \(message)"
        }
    }
}