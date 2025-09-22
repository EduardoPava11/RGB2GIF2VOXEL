import Foundation
import Combine
// Note: Yams needs to be added via Swift Package Manager
// In Xcode: File → Add Package Dependencies → https://github.com/jpsim/Yams.git
#if canImport(Yams)
import Yams
#endif

/// Loads and manages YAML-based pipeline configuration
@MainActor
public class YAMLConfigurationLoader: ObservableObject {

    // MARK: - Published Properties
    @Published public private(set) var currentConfig: PipelineConfig?
    @Published public private(set) var isLoading = false
    @Published public private(set) var lastError: Error?

    // MARK: - Configuration Model
    public struct PipelineConfig: Codable {
        // Frame Capture
        public struct CaptureConfig: Codable {
            public let frameCount: Int
            public let fps: Int
            public let resolution: ResolutionConfig

            enum CodingKeys: String, CodingKey {
                case frameCount = "frame_count"
                case fps
                case resolution
            }
        }

        public struct ResolutionConfig: Codable {
            public let width: Int
            public let height: Int
        }

        // Color Quantization
        public struct QuantizationConfig: Codable {
            public let algorithm: String  // "libimagequant"
            public let paletteSize: Int
            public let qualityMin: Int
            public let qualityMax: Int
            public let speed: Int
            public let dithering: Double

            enum CodingKeys: String, CodingKey {
                case algorithm = "color_quantization"
                case paletteSize = "palette_size"
                case qualityMin = "quality_min"
                case qualityMax = "quality_max"
                case speed
                case dithering
            }
        }

        // GIF Encoding
        public struct GIFConfig: Codable {
            public let optimize: Bool
            public let loopCount: Int
            public let compression: String

            enum CodingKeys: String, CodingKey {
                case optimize
                case loopCount = "loop_count"
                case compression
            }
        }

        // Tensor Configuration
        public struct TensorConfig: Codable {
            public let dimensions: Int  // 256 for 256³ cube
            public let channelOrder: String  // "RGBA"
            public let normalize: Bool

            enum CodingKeys: String, CodingKey {
                case dimensions
                case channelOrder = "channel_order"
                case normalize
            }
        }

        // Performance
        public struct PerformanceConfig: Codable {
            public let parallel: Bool
            public let threads: Int?
            public let memoryLimit: String?  // e.g. "200MB"

            enum CodingKeys: String, CodingKey {
                case parallel = "use_parallel"
                case threads = "max_threads"
                case memoryLimit = "memory_limit"
            }
        }

        // Root configuration
        public let pipeline: String
        public let version: String
        public let capture: CaptureConfig
        public let quantization: QuantizationConfig
        public let gif: GIFConfig
        public let tensor: TensorConfig
        public let performance: PerformanceConfig
    }

    // MARK: - Initialization
    public init() {
        loadDefaultConfiguration()
    }

    // MARK: - Loading Methods

    /// Load configuration from bundled YAML file
    public func loadConfiguration(named filename: String) async -> Bool {
        await MainActor.run {
            self.isLoading = true
            self.lastError = nil
        }

        do {
            // Look for file in bundle
            guard let url = Bundle.main.url(forResource: filename, withExtension: "yaml") ??
                          Bundle.main.url(forResource: filename, withExtension: "yml") else {
                throw ConfigError.fileNotFound(filename)
            }

            let yamlString = try String(contentsOf: url, encoding: .utf8)
            #if canImport(Yams)
            let config = try YAMLDecoder().decode(PipelineConfig.self, from: yamlString)
            #else
            // Try to parse as JSON fallback
            let data = try Data(contentsOf: url)
            let config = try JSONDecoder().decode(PipelineConfig.self, from: data)
            #endif

            await MainActor.run {
                self.currentConfig = config
                self.isLoading = false
            }
            return true

        } catch {
            await MainActor.run {
                self.lastError = error
                self.isLoading = false
            }
            return false
        }
    }

    /// Load configuration from string
    public func loadConfigurationFromString(_ yamlString: String) throws -> PipelineConfig {
        #if canImport(Yams)
        return try YAMLDecoder().decode(PipelineConfig.self, from: yamlString)
        #else
        // Fallback: parse as JSON if Yams is not available
        if let data = yamlString.data(using: .utf8) {
            return try JSONDecoder().decode(PipelineConfig.self, from: data)
        }
        throw ConfigError.invalidFormat
        #endif
    }

    /// Load default configuration
    private func loadDefaultConfiguration() {
        let defaultYAML = """
        pipeline: "RGB→GIF→Voxel"
        version: "1.0.0"

        capture:
          frame_count: 256
          fps: 30
          resolution:
            width: 256
            height: 256

        quantization:
          color_quantization: "libimagequant"
          palette_size: 256
          quality_min: 70
          quality_max: 100
          speed: 5
          dithering: 1.0

        gif:
          optimize: true
          loop_count: 0
          compression: "lzw"

        tensor:
          dimensions: 256
          channel_order: "RGBA"
          normalize: false

        performance:
          use_parallel: true
          max_threads: null
          memory_limit: "200MB"
        """

        do {
            currentConfig = try loadConfigurationFromString(defaultYAML)
        } catch {
            print("Failed to load default configuration: \(error)")
        }
    }

    // MARK: - Configuration Conversion

    /// Convert to Rust processor options
    public func toProcessorOptions() -> ProcessorOptions? {
        guard let config = currentConfig else { return nil }

        return ProcessorOptions(
            quantize: QuantizeOpts(
                qualityMin: UInt8(config.quantization.qualityMin),
                qualityMax: UInt8(config.quantization.qualityMax),
                speed: Int32(config.quantization.speed),
                paletteSize: UInt16(config.quantization.paletteSize),
                ditheringLevel: Float(config.quantization.dithering),
                sharedPalette: true
            ),
            gif: GifOpts(
                width: UInt16(config.capture.resolution.width),
                height: UInt16(config.capture.resolution.height),
                frameCount: UInt16(config.capture.frameCount),
                fps: UInt16(config.capture.fps),
                loopCount: UInt16(config.gif.loopCount),
                optimize: config.gif.optimize,
                includeTensor: false  // Default to false
            ),
            parallel: config.performance.parallel
        )
    }

    // MARK: - Configuration Profiles

    public enum Profile: String, CaseIterable {
        case quality = "quality"
        case balanced = "balanced"
        case speed = "speed"
        case tiny = "tiny"

        var filename: String {
            "pipeline_config_\(rawValue)"
        }

        var displayName: String {
            switch self {
            case .quality: return "High Quality"
            case .balanced: return "Balanced"
            case .speed: return "Fast"
            case .tiny: return "Tiny File"
            }
        }
    }

    /// Load a predefined profile
    public func loadProfile(_ profile: Profile) async -> Bool {
        return await loadConfiguration(named: profile.filename)
    }

    // MARK: - Errors
    enum ConfigError: LocalizedError {
        case fileNotFound(String)
        case invalidFormat
        case missingRequiredField(String)

        var errorDescription: String? {
            switch self {
            case .fileNotFound(let name):
                return "Configuration file '\(name)' not found"
            case .invalidFormat:
                return "Invalid YAML format"
            case .missingRequiredField(let field):
                return "Missing required field: \(field)"
            }
        }
    }

    // MARK: - Memory Limit Parsing

    /// Parse memory limit string (e.g. "200MB") to bytes
    public func parseMemoryLimit(_ limitString: String?) -> Int64? {
        guard let limitString = limitString else { return nil }

        let pattern = #"(\d+(?:\.\d+)?)\s*([KMG]?B?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: limitString, range: NSRange(limitString.startIndex..., in: limitString)),
              let valueRange = Range(match.range(at: 1), in: limitString),
              let unitRange = Range(match.range(at: 2), in: limitString) else {
            return nil
        }

        guard let value = Double(limitString[valueRange]) else { return nil }
        let unit = String(limitString[unitRange]).uppercased()

        let multiplier: Double
        switch unit {
        case "KB", "K":
            multiplier = 1024
        case "MB", "M":
            multiplier = 1024 * 1024
        case "GB", "G":
            multiplier = 1024 * 1024 * 1024
        case "B", "":
            multiplier = 1
        default:
            return nil
        }

        return Int64(value * multiplier)
    }
}

// MARK: - SwiftUI Integration

import SwiftUI

/// View for selecting configuration profiles
public struct ConfigurationSelectorView: View {
    @StateObject private var loader = YAMLConfigurationLoader()
    @State private var selectedProfile: YAMLConfigurationLoader.Profile = .balanced

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Pipeline Configuration")
                .font(.headline)

            // Profile selector
            Picker("Profile", selection: $selectedProfile) {
                ForEach(YAMLConfigurationLoader.Profile.allCases, id: \.self) { profile in
                    Text(profile.displayName).tag(profile)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .onChange(of: selectedProfile) { newProfile in
                Task {
                    await loader.loadProfile(newProfile)
                }
            }

            // Current configuration display
            if let config = loader.currentConfig {
                ConfigDetailsView(config: config)
            }

            if loader.isLoading {
                ProgressView("Loading configuration...")
            }

            if let error = loader.lastError {
                Text(error.localizedDescription)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .padding()
    }
}

struct ConfigDetailsView: View {
    let config: YAMLConfigurationLoader.PipelineConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("\(config.capture.frameCount) frames @ \(config.capture.fps) fps", systemImage: "camera")
            Label("\(config.capture.resolution.width)×\(config.capture.resolution.height) resolution", systemImage: "aspectratio")
            Label("\(config.quantization.algorithm) with \(config.quantization.paletteSize) colors", systemImage: "paintpalette")
            Label("Speed: \(config.quantization.speed)/10", systemImage: "speedometer")
            if config.performance.parallel {
                Label("Parallel processing enabled", systemImage: "cpu")
            }
        }
        .font(.caption)
        .foregroundColor(.secondary)
    }
}