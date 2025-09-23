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
    private static let subsystem = "com.yingif.rgb2gif2voxel"

    public static let app = Logger(subsystem: subsystem, category: "app")
    public static let camera = Logger(subsystem: subsystem, category: "camera")
    public static let pipeline = Logger(subsystem: subsystem, category: "pipeline")
    public static let gif = Logger(subsystem: subsystem, category: "gif")
    public static let photos = Logger(subsystem: subsystem, category: "photos")
    public static let ffi = Logger(subsystem: subsystem, category: "ffi")
    public static let ui = Logger(subsystem: subsystem, category: "ui")
    public static let processing = Logger(subsystem: subsystem, category: "processing")
    public static let performance = Logger(subsystem: subsystem, category: "performance")
    public static let voxel = Logger(subsystem: subsystem, category: "voxel")
    public static let storage = Logger(subsystem: subsystem, category: "storage")
    public static let network = Logger(subsystem: subsystem, category: "network")
    public static let debug = Logger(subsystem: subsystem, category: "debug")
}

// MARK: - Signposting

public struct PipelineSignpost {
    public static let signposter = OSSignposter(subsystem: "com.yingif.rgb2gif2voxel", category: "Pipeline")

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