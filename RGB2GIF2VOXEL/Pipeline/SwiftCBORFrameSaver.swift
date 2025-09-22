//
//  SwiftCBORFrameSaver.swift
//  RGB2GIF2VOXEL
//
//  Native Swift CBOR implementation for frame saving
//  Optimized for performance with 256×256 frames
//

import Foundation
import OSLog
import Accelerate
import Combine

private let logger = Logger(subsystem: "com.yingif.rgb2gif2voxel", category: "SwiftCBORFrameSaver")

/// High-performance Swift native CBOR frame saver
@MainActor
public class SwiftCBORFrameSaver: ObservableObject {

    // MARK: - Properties

    @Published public var isWriterOpen = false
    @Published public var framesSaved = 0
    @Published public var totalBytesWritten: Int64 = 0

    private var sessionDirectory: URL?
    private var fileHandle: FileHandle?
    private var frameCount: Int = 0
    private var frameWidth: Int = 0
    private var frameHeight: Int = 0

    // Performance optimization: reuse buffers
    private var writeBuffer: UnsafeMutablePointer<UInt8>?
    private var bufferSize: Int = 0

    // MARK: - Error Types

    public enum FrameSaveError: LocalizedError {
        case notOpen
        case writeError(String)
        case invalidData
        case bufferAllocationFailed

        public var errorDescription: String? {
            switch self {
            case .notOpen:
                return "CBOR writer is not open"
            case .writeError(let msg):
                return "Write error: \(msg)"
            case .invalidData:
                return "Invalid frame data"
            case .bufferAllocationFailed:
                return "Failed to allocate buffer"
            }
        }
    }

    // MARK: - Initialization

    public init() {}

    deinit {
        if let buffer = writeBuffer {
            buffer.deallocate()
        }
    }

    // MARK: - Public API

    /// Open CBOR writer for a capture session
    public func openWriter(sessionId: String, frameCount: Int, width: Int, height: Int) throws {
        guard !isWriterOpen else {
            logger.warning("Writer already open, closing first")
            closeWriter()
            return  // Must exit the scope after guard fails
        }

        self.frameCount = frameCount
        self.frameWidth = width
        self.frameHeight = height

        // Create session directory
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        sessionDirectory = documentsPath.appendingPathComponent("cbor_sessions").appendingPathComponent(sessionId)

        try FileManager.default.createDirectory(at: sessionDirectory!, withIntermediateDirectories: true)

        // Write manifest
        let manifest = CaptureManifest(
            sessionId: sessionId,
            frameCount: frameCount,
            width: width,
            height: height,
            timestamp: Date()
        )

        let manifestURL = sessionDirectory!.appendingPathComponent("manifest.json")
        let manifestData = try JSONEncoder().encode(manifest)
        try manifestData.write(to: manifestURL)

        // Allocate reusable buffer (frame size + CBOR overhead)
        let expectedFrameSize = width * height * 4 // RGBA
        bufferSize = expectedFrameSize + 1024 // Add overhead for CBOR encoding
        writeBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)

        isWriterOpen = true
        framesSaved = 0
        totalBytesWritten = 0

        logger.info("✅ Opened Swift CBOR writer for \(frameCount) frames at: \(self.sessionDirectory!.path)")
    }

    /// Save a frame using optimized CBOR encoding
    public func saveFrame(pixelBuffer: CVPixelBuffer, frameIndex: Int) throws {
        guard isWriterOpen else {
            throw FrameSaveError.notOpen
        }

        guard let buffer = writeBuffer else {
            throw FrameSaveError.bufferAllocationFailed
        }

        let startTime = CFAbsoluteTimeGetCurrent()

        // Lock the pixel buffer
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw FrameSaveError.invalidData
        }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)

        // Optimized CBOR encoding
        var offset = 0

        // CBOR Map header (5 items)
        buffer[offset] = 0xA5  // Map with 5 items
        offset += 1

        // 1. "v" : 1 (version)
        buffer[offset] = 0x61  // Text string of length 1
        offset += 1
        buffer[offset] = 0x76  // "v"
        offset += 1
        buffer[offset] = 0x01  // Unsigned int 1
        offset += 1

        // 2. "i" : frameIndex
        buffer[offset] = 0x61  // Text string of length 1
        offset += 1
        buffer[offset] = 0x69  // "i"
        offset += 1
        if frameIndex < 24 {
            buffer[offset] = UInt8(frameIndex)  // Small int
            offset += 1
        } else {
            buffer[offset] = 0x18  // Unsigned int 8-bit
            offset += 1
            buffer[offset] = UInt8(frameIndex)
            offset += 1
        }

        // 3. "w" : width
        buffer[offset] = 0x61  // Text string of length 1
        offset += 1
        buffer[offset] = 0x77  // "w"
        offset += 1
        writeCBORInt(width, to: buffer, at: &offset)

        // 4. "h" : height
        buffer[offset] = 0x61  // Text string of length 1
        offset += 1
        buffer[offset] = 0x68  // "h"
        offset += 1
        writeCBORInt(height, to: buffer, at: &offset)

        // 5. "d" : data (byte string)
        buffer[offset] = 0x61  // Text string of length 1
        offset += 1
        buffer[offset] = 0x64  // "d"
        offset += 1

        // Calculate data size
        let dataSize = width * height * 4

        // Write byte string header
        if dataSize < 24 {
            buffer[offset] = 0x40 | UInt8(dataSize)  // Byte string
            offset += 1
        } else if dataSize < 256 {
            buffer[offset] = 0x58  // Byte string 8-bit length
            offset += 1
            buffer[offset] = UInt8(dataSize)
            offset += 1
        } else if dataSize < 65536 {
            buffer[offset] = 0x59  // Byte string 16-bit length
            offset += 1
            buffer[offset] = UInt8((dataSize >> 8) & 0xFF)
            offset += 1
            buffer[offset] = UInt8(dataSize & 0xFF)
            offset += 1
        } else {
            buffer[offset] = 0x5A  // Byte string 32-bit length
            offset += 1
            buffer[offset] = UInt8((dataSize >> 24) & 0xFF)
            offset += 1
            buffer[offset] = UInt8((dataSize >> 16) & 0xFF)
            offset += 1
            buffer[offset] = UInt8((dataSize >> 8) & 0xFF)
            offset += 1
            buffer[offset] = UInt8(dataSize & 0xFF)
            offset += 1
        }

        // Copy pixel data efficiently using vImage
        if bytesPerRow == width * 4 {
            // Fast path: contiguous data
            memcpy(buffer.advanced(by: offset), baseAddress, dataSize)
        } else {
            // Slow path: row by row copy (handles padding)
            let source = baseAddress.assumingMemoryBound(to: UInt8.self)
            let dest = buffer.advanced(by: offset)
            for y in 0..<height {
                memcpy(dest.advanced(by: y * width * 4),
                       source.advanced(by: y * bytesPerRow),
                       width * 4)
            }
        }
        offset += dataSize

        // Write to file
        let frameURL = sessionDirectory!.appendingPathComponent("frame_\(String(format: "%04d", frameIndex)).cbor")
        let cborData = Data(bytesNoCopy: buffer, count: offset, deallocator: .none)
        try cborData.write(to: frameURL)

        framesSaved += 1
        totalBytesWritten += Int64(offset)

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        logger.debug("Frame \(frameIndex) saved: \(offset) bytes in \(elapsed * 1000)ms")
    }

    /// Close the CBOR writer
    public func closeWriter() {
        guard isWriterOpen else { return }

        isWriterOpen = false
        logger.info("✅ Closed Swift CBOR writer. Saved \(self.framesSaved) frames, \(self.totalBytesWritten) bytes total")
    }

    // MARK: - Private Helpers

    private func writeCBORInt(_ value: Int, to buffer: UnsafeMutablePointer<UInt8>, at offset: inout Int) {
        if value < 24 {
            buffer[offset] = UInt8(value)
            offset += 1
        } else if value < 256 {
            buffer[offset] = 0x18
            offset += 1
            buffer[offset] = UInt8(value)
            offset += 1
        } else if value < 65536 {
            buffer[offset] = 0x19
            offset += 1
            buffer[offset] = UInt8((value >> 8) & 0xFF)
            offset += 1
            buffer[offset] = UInt8(value & 0xFF)
            offset += 1
        } else {
            buffer[offset] = 0x1A
            offset += 1
            buffer[offset] = UInt8((value >> 24) & 0xFF)
            offset += 1
            buffer[offset] = UInt8((value >> 16) & 0xFF)
            offset += 1
            buffer[offset] = UInt8((value >> 8) & 0xFF)
            offset += 1
            buffer[offset] = UInt8(value & 0xFF)
            offset += 1
        }
    }
}

// MARK: - Supporting Types

private struct CaptureManifest: Codable {
    let sessionId: String
    let frameCount: Int
    let width: Int
    let height: Int
    let timestamp: Date
}