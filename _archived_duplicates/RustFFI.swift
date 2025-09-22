// RustFFI.swift
// Real Rust FFI function declarations

import Foundation

// MARK: - Rust FFI Functions
// These functions are implemented in the Rust library (rust-core)
// and exposed via C ABI through the XCFramework

// Process batch of RGBA frames
// Downsizes each frame using Lanczos3 and quantizes colors using NeuQuant
@_silgen_name("yx_proc_batch_rgba8")
func yx_proc_batch_rgba8(
    frames: UnsafePointer<UnsafePointer<UInt8>?>?,
    n: Int32,
    width: Int32,
    height: Int32,
    targetSide: Int32,
    paletteSize: Int32,
    outIndices: UnsafeMutablePointer<UInt8>?,
    outPalettes: UnsafeMutablePointer<UInt32>?
) -> Int32

// Encode indexed frames to GIF89a
// Creates animated GIF with local palettes per frame
@_silgen_name("yx_gif_encode")
func yx_gif_encode(
    indices: UnsafePointer<UInt8>?,
    palettes: UnsafePointer<UInt32>?,
    n: Int32,
    side: Int32,
    delayCentiseconds: Int32,
    outBuf: UnsafeMutablePointer<UInt8>?,
    outLen: UnsafeMutablePointer<Int>?
) -> Int32

// MARK: - CBOR I/O Functions (implemented in libyxcbor.a)

// Frame manifest structure for CBOR I/O
public struct yx_frame_manifest {
    public var width: UInt32
    public var height: UInt32
    public var channels: UInt32
    public var frame_count: UInt32

    public init(width: UInt32 = 256, height: UInt32 = 256, channels: UInt32 = 4, frame_count: UInt32 = 256) {
        self.width = width
        self.height = height
        self.channels = channels
        self.frame_count = frame_count
    }
}

// Open CBOR writer for streaming frames
@_silgen_name("yxcbor_open_writer")
func yxcbor_open_writer(
    _ path: UnsafePointer<CChar>?,
    _ manifest: UnsafePointer<yx_frame_manifest>?
) -> Int32

// Write a frame to CBOR stream
@_silgen_name("yxcbor_write_frame")
func yxcbor_write_frame(
    _ data: UnsafePointer<UInt8>?,
    _ size: UInt32
) -> Int32

// Close CBOR writer
@_silgen_name("yxcbor_close_writer")
func yxcbor_close_writer() -> Int32

// Open CBOR reader
@_silgen_name("yxcbor_open_reader")
func yxcbor_open_reader(
    _ path: UnsafePointer<CChar>?,
    _ manifest: UnsafeMutablePointer<yx_frame_manifest>?
) -> Int32

// Read a frame from CBOR stream
@_silgen_name("yxcbor_read_frame")
func yxcbor_read_frame(
    _ index: UInt32,
    _ buffer: UnsafeMutablePointer<UInt8>?,
    _ size: UInt32
) -> Int32

// Close CBOR reader
@_silgen_name("yxcbor_close_reader")
func yxcbor_close_reader() -> Int32

// Legacy processor functions (also implemented in Rust)
@_silgen_name("yingif_processor_new")
func yingif_processor_new() -> OpaquePointer?

@_silgen_name("yingif_processor_free")
func yingif_processor_free(_ processor: OpaquePointer?)

@_silgen_name("yingif_process_frame")
func yingif_process_frame(
    _ processor: OpaquePointer?,
    _ bgraData: UnsafeRawPointer?,
    _ width: Int32,
    _ height: Int32,
    _ targetSize: Int32,
    _ paletteSize: Int32,
    _ indices: UnsafeMutablePointer<UInt8>?,
    _ palette: UnsafeMutablePointer<UInt32>?
) -> Int32

@_silgen_name("yingif_create_gif89a")
func yingif_create_gif89a(
    _ indices: UnsafePointer<UInt8>?,
    _ palette: UnsafePointer<UInt32>?,
    _ cubeSize: Int32,
    _ paletteSize: Int32,
    _ delayMs: Int32,
    _ outData: UnsafeMutablePointer<UInt8>?,
    _ outCapacity: Int32,
    _ outSize: UnsafeMutablePointer<Int32>?
) -> Int32

@_silgen_name("yingif_estimate_gif_size")
func yingif_estimate_gif_size(
    _ cubeSize: Int32,
    _ paletteSize: Int32
) -> Int32