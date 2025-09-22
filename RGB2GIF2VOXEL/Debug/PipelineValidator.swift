import Foundation
import UIKit
import AVFoundation
import CoreMedia

/// Validates the complete capture pipeline
public class PipelineValidator {

    // MARK: - Validation Results

    public struct ValidationResult {
        let component: String
        let isValid: Bool
        let message: String
        let error: Error?
    }

    // MARK: - Public API

    public static func validateFullPipeline() -> [ValidationResult] {
        var results: [ValidationResult] = []

        // 1. Validate configuration
        results.append(validateConfiguration())

        // 2. Validate camera access
        results.append(validateCameraAccess())

        // 3. Validate Rust FFI
        results.append(validateRustFFI())

        // 4. Validate data flow
        results.append(validateDataFlow())

        // 5. Validate memory constraints
        results.append(validateMemoryConstraints())

        // 6. Validate GIF encoding
        results.append(validateGIFEncoding())

        return results
    }

    // MARK: - Component Validation

    private static func validateConfiguration() -> ValidationResult {
        let isValid = CaptureConfiguration.availableCubeSizes == [528, 264, 132] &&
                     CaptureConfiguration.availablePaletteSizes == [64, 128, 256]

        return ValidationResult(
            component: "Configuration",
            isValid: isValid,
            message: isValid ? "Configuration valid" : "Invalid configuration",
            error: nil
        )
    }

    private static func validateCameraAccess() -> ValidationResult {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        let isValid = status == .authorized || status == .notDetermined

        return ValidationResult(
            component: "Camera Access",
            isValid: isValid,
            message: "Camera status: \(status)",
            error: isValid ? nil : CaptureError.cameraAccessDenied
        )
    }

    private static func validateRustFFI() -> ValidationResult {
        do {
            // Test processor creation
            let processor = YinGifProcessor()

            // Test frame processing
            let testData = Data(repeating: 0xFF, count: 1024)
            _ = try processor.processFrame(
                bgraData: testData,
                width: 32,
                height: 32,
                targetSize: 16,
                paletteSize: 16
            )

            return ValidationResult(
                component: "Rust FFI",
                isValid: true,
                message: "Rust FFI operational",
                error: nil
            )
        } catch {
            return ValidationResult(
                component: "Rust FFI",
                isValid: false,
                message: "Rust FFI failed",
                error: error
            )
        }
    }

    private static func validateDataFlow() -> ValidationResult {
        // Create test components
        let controller = CubeClipController(sideN: 8, paletteSize: 16)

        // Simulate frame capture
        controller.startCapture()

        // Create mock frame with RGBA data
        let mockRgbaData = Data(repeating: 0xFF, count: 8 * 8 * 4)
        let mockFrame = QuantizedFrame(
            index: 0,
            data: mockRgbaData,
            width: 8,
            height: 8
        )

        // Ingest frames
        for _ in 0..<8 {
            _ = controller.ingestFrame(mockFrame)
        }

        // Try to build tensor
        let tensor = controller.buildCubeTensor()
        let isValid = tensor != nil

        return ValidationResult(
            component: "Data Flow",
            isValid: isValid,
            message: isValid ? "Data flow operational" : "Data flow failed",
            error: isValid ? nil : CaptureError.tensorBuildFailed
        )
    }

    private static func validateMemoryConstraints() -> ValidationResult {
        let maxMemoryMB = 200.0 // Conservative limit
        var isValid = true
        var message = "Memory constraints OK"

        for cubeSize in CaptureConfiguration.availableCubeSizes {
            let memoryMB = CaptureConfiguration.memoryInMB(for: cubeSize)
            if memoryMB > maxMemoryMB {
                isValid = false
                message = "\(cubeSize)³ exceeds memory limit (\(memoryMB) MB)"
                break
            }
        }

        return ValidationResult(
            component: "Memory",
            isValid: isValid,
            message: message,
            error: isValid ? nil : CaptureError.insufficientMemory
        )
    }

    private static func validateGIFEncoding() -> ValidationResult {
        // Create small test tensor
        let testData = CubeTensorData(
            size: 8,
            indices: Array(repeating: 0, count: 512),
            palette: Array(repeating: 0xFFFFFF, count: 16),
            paletteSize: 16
        )

        // Try to encode
        let gifData = GIF89aEncoder.encode(tensor: testData, delayMs: 40)
        let isValid = gifData != nil

        return ValidationResult(
            component: "GIF Encoding",
            isValid: isValid,
            message: isValid ? "GIF encoding works" : "GIF encoding failed",
            error: isValid ? nil : CaptureError.gifEncodingFailed("Test failed")
        )
    }

    // MARK: - Diagnostic Output

    public static func printValidationReport() {
        print("=" * 50)
        print("PIPELINE VALIDATION REPORT")
        print("=" * 50)

        let results = validateFullPipeline()
        var allValid = true

        for result in results {
            let status = result.isValid ? "✅" : "❌"
            print("\(status) \(result.component): \(result.message)")
            if let error = result.error {
                print("   Error: \(error.localizedDescription)")
            }
            allValid = allValid && result.isValid
        }

        print("=" * 50)
        print(allValid ? "✅ ALL SYSTEMS OPERATIONAL" : "❌ ISSUES DETECTED")
        print("=" * 50)
    }
}

// MARK: - String Extension for Repeat

private extension String {
    static func * (left: String, right: Int) -> String {
        return String(repeating: left, count: right)
    }
}