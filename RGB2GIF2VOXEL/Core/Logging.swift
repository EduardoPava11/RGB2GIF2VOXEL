//
//  Logging.swift
//  RGB2GIF2VOXEL
//
//  Unified logging with os.Logger and OSSignposter for profiling
//

import Foundation
import os

// MARK: - Loggers

public enum Log {
    static let app = Logger(subsystem: "com.rgb2gif2voxel", category: "app")
    static let camera = Logger(subsystem: "com.rgb2gif2voxel", category: "camera")
    static let pipeline = Logger(subsystem: "com.rgb2gif2voxel", category: "pipeline")
    static let gif = Logger(subsystem: "com.rgb2gif2voxel", category: "gif")
    static let photos = Logger(subsystem: "com.rgb2gif2voxel", category: "photos")
    static let ffi = Logger(subsystem: "com.rgb2gif2voxel", category: "ffi")
    static let ui = Logger(subsystem: "com.rgb2gif2voxel", category: "ui")
}

// MARK: - Signposting

public struct PipelineSignpost {
    public static let signposter = OSSignposter(subsystem: "com.rgb2gif2voxel", category: "Pipeline")

    public enum Phase: String {
        case capture = "Capture"
        case downsample = "Downsample"
        case cborEncode = "CBOR_Encode"
        case rustFFI = "Rust_FFI"
        case swiftGIF = "Swift_GIF"
        case savePhotos = "Save_Photos"
        case fullPipeline = "Full_Pipeline"
    }

    public static func begin(_ phase: Phase) -> OSSignpostIntervalState {
        let id = signposter.makeSignpostID()
        let name: StaticString
        switch phase {
        case .capture: name = "Capture"
        case .downsample: name = "Downsample"
        case .cborEncode: name = "CBOR_Encode"
        case .rustFFI: name = "Rust_FFI"
        case .swiftGIF: name = "Swift_GIF"
        case .savePhotos: name = "Save_Photos"
        case .fullPipeline: name = "Full_Pipeline"
        }

        return signposter.beginInterval(name, id: id)
    }

    public static func end(_ phase: Phase, _ state: OSSignpostIntervalState) {
        let name: StaticString
        switch phase {
        case .capture: name = "Capture"
        case .downsample: name = "Downsample"
        case .cborEncode: name = "CBOR_Encode"
        case .rustFFI: name = "Rust_FFI"
        case .swiftGIF: name = "Swift_GIF"
        case .savePhotos: name = "Save_Photos"
        case .fullPipeline: name = "Full_Pipeline"
        }
        signposter.endInterval(name, state)
    }
}

// MARK: - Performance Measurement

public struct PerformanceMeasure {
    private let start: CFAbsoluteTime
    private let phase: String

    public init(phase: String) {
        self.phase = phase
        self.start = CFAbsoluteTimeGetCurrent()
        Log.pipeline.debug("Starting: \(phase, privacy: .public)")
    }

    public func end() {
        let duration = (CFAbsoluteTimeGetCurrent() - start) * 1000
        Log.pipeline.info("\(phase, privacy: .public) completed in \(duration, format: .fixed(precision: 2))ms")
    }
}

// MARK: - Convenience Extensions

extension Logger {
    public func measure<T>(_ label: String, _ block: () throws -> T) rethrows -> T {
        let measure = PerformanceMeasure(phase: label)
        defer { measure.end() }
        return try block()
    }

    public func measureAsync<T>(_ label: String, _ block: () async throws -> T) async rethrows -> T {
        let measure = PerformanceMeasure(phase: label)
        defer { measure.end() }
        return try await block()
    }
}