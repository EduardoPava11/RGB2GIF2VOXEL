// yxcbor_simple.zig - Simplified CBOR frame storage for iOS
// C ABI for Swift integration

const std = @import("std");

// Frame manifest structure
const FrameManifest = extern struct {
    width: u32,
    height: u32,
    channels: u32,
    frame_count: u32,
};

// Simple frame save - raw binary format with header
export fn yxcbor_save_frame(
    path_ptr: [*:0]const u8,
    rgba_data: [*]const u8,
    width: u32,
    height: u32,
    index: u32,
) c_int {
    const path = std.mem.span(path_ptr);
    const data_size = width * height * 4;

    // Open file for writing
    const file = std.fs.cwd().createFile(path, .{}) catch return -1;
    defer file.close();

    // Write simple header (not full CBOR for now)
    // Magic: "YXFR" (4 bytes)
    _ = file.write("YXFR") catch return -2;

    // Write metadata (20 bytes)
    var meta_buf: [20]u8 = undefined;
    std.mem.writeInt(u32, meta_buf[0..4], index, .little);
    std.mem.writeInt(u32, meta_buf[4..8], width, .little);
    std.mem.writeInt(u32, meta_buf[8..12], height, .little);
    std.mem.writeInt(u32, meta_buf[12..16], 0x41424752, .little); // "RGBA"
    std.mem.writeInt(u32, meta_buf[16..20], data_size, .little);
    _ = file.write(&meta_buf) catch return -3;

    // Write frame data
    const data_slice = rgba_data[0..data_size];
    _ = file.write(data_slice) catch return -4;

    return 0; // Success
}

// Load frame from disk
export fn yxcbor_load_frame(
    path_ptr: [*:0]const u8,
    out_rgba: [*]u8,
    out_width: *u32,
    out_height: *u32,
    out_index: *u32,
) c_int {
    const path = std.mem.span(path_ptr);

    // Open file for reading
    const file = std.fs.cwd().openFile(path, .{}) catch return -1;
    defer file.close();

    // Read and verify magic
    var magic: [4]u8 = undefined;
    _ = file.read(&magic) catch return -2;
    if (!std.mem.eql(u8, &magic, "YXFR")) return -5;

    // Read metadata
    var meta_buf: [20]u8 = undefined;
    _ = file.read(&meta_buf) catch return -3;

    const index = std.mem.readInt(u32, meta_buf[0..4], .little);
    const width = std.mem.readInt(u32, meta_buf[4..8], .little);
    const height = std.mem.readInt(u32, meta_buf[8..12], .little);
    // _ = std.mem.readInt(u32, meta_buf[12..16], .little); // format
    const data_size = std.mem.readInt(u32, meta_buf[16..20], .little);

    // Validate size
    if (data_size != width * height * 4) return -6;

    // Read frame data
    const out_slice = out_rgba[0..data_size];
    _ = file.read(out_slice) catch return -4;

    // Set output parameters
    out_index.* = index;
    out_width.* = width;
    out_height.* = height;

    return 0; // Success
}

// Save batch of frames to directory
export fn yxcbor_save_batch(
    dir_ptr: [*:0]const u8,
    frames: [*]const [*]const u8,
    n_frames: u32,
    width: u32,
    height: u32,
) c_int {
    const dir_path = std.mem.span(dir_ptr);

    // Create directory
    std.fs.cwd().makePath(dir_path) catch return -1;

    // Save each frame
    var path_buf: [512]u8 = undefined;
    var i: u32 = 0;
    while (i < n_frames) : (i += 1) {
        const path_str = std.fmt.bufPrintZ(
            &path_buf,
            "{s}/frame_{d:0>3}.yxfr",
            .{ dir_path, i }
        ) catch return -2;

        const result = yxcbor_save_frame(
            path_str.ptr,
            frames[i],
            width,
            height,
            i
        );

        if (result != 0) return result;
    }

    // Write manifest file
    const manifest_path = std.fmt.bufPrintZ(
        &path_buf,
        "{s}/manifest.json",
        .{dir_path}
    ) catch return -2;

    const manifest_file = std.fs.cwd().createFile(
        manifest_path,
        .{}
    ) catch return -7;
    defer manifest_file.close();

    // Write simple JSON manifest
    const manifest_json = std.fmt.allocPrint(
        std.heap.raw_c_allocator,
        "{{\"version\":1,\"frames\":{d},\"width\":{d},\"height\":{d},\"format\":\"RGBA8888\"}}",
        .{ n_frames, width, height }
    ) catch return -8;
    defer std.heap.raw_c_allocator.free(manifest_json);

    _ = manifest_file.write(manifest_json) catch return -9;

    return 0; // Success
}

// Get frame path for given index
export fn yxcbor_get_frame_path(
    dir_ptr: [*:0]const u8,
    index: u32,
    out_path: [*]u8,
    max_len: u32,
) c_int {
    const dir_path = std.mem.span(dir_ptr);

    var path_buf: [512]u8 = undefined;
    const path_str = std.fmt.bufPrintZ(
        &path_buf,
        "{s}/frame_{d:0>3}.yxfr",
        .{ dir_path, index }
    ) catch return -1;

    const path_len = path_str.len;
    if (path_len >= max_len) return -2;

    @memcpy(out_path[0..path_len], path_str[0..path_len]);
    out_path[path_len] = 0;

    return 0;
}

// ========== Streaming API ==========

// Global writer state (simplified)
var g_writer_file: ?std.fs.File = null;
var g_writer_count: u32 = 0;
var g_writer_manifest: FrameManifest = undefined;

// Open writer for streaming frames
export fn yxcbor_open_writer(dir_path: [*:0]const u8, manifest: *const FrameManifest) c_int {
    // Close any existing writer
    if (g_writer_file) |file| {
        file.close();
        g_writer_file = null;
    }

    const dir_str = std.mem.span(dir_path);

    // Create directory
    std.fs.makeDirAbsolute(dir_str) catch |err| {
        std.debug.print("Failed to create directory: {}\n", .{err});
        return -2;
    };

    // Save manifest
    const manifest_path = std.fmt.allocPrint(std.heap.page_allocator, "{s}/manifest.cbor", .{dir_str}) catch return -4;
    defer std.heap.page_allocator.free(manifest_path);

    const manifest_file = std.fs.createFileAbsolute(manifest_path, .{}) catch return -3;
    defer manifest_file.close();

    // Write simple binary manifest
    _ = manifest_file.write(std.mem.asBytes(manifest)) catch return -3;

    // Open frames file for streaming
    const frames_path = std.fmt.allocPrint(std.heap.page_allocator, "{s}/frames.cbor", .{dir_str}) catch return -4;
    defer std.heap.page_allocator.free(frames_path);

    g_writer_file = std.fs.createFileAbsolute(frames_path, .{}) catch return -5;
    g_writer_count = 0;
    g_writer_manifest = manifest.*;

    // Write array header for expected frame count
    const header = [_]u8{0x9A} ++ std.mem.toBytes(std.mem.nativeToBig(u32, manifest.frame_count));
    _ = g_writer_file.?.write(&header) catch return -6;

    return 0;
}

// Write a single frame
export fn yxcbor_write_frame(rgba_ptr: [*]const u8, len: u32) c_int {
    const file = g_writer_file orelse return -1;

    const expected_len = g_writer_manifest.width * g_writer_manifest.height * g_writer_manifest.channels;
    if (len != expected_len) return -2;

    const rgba_slice = rgba_ptr[0..len];

    // Write CBOR byte string header
    const size_bytes = std.mem.toBytes(std.mem.nativeToBig(u32, len));
    _ = file.write(&[_]u8{0x5A}) catch return -6; // Major type 2 (byte string), 4-byte length
    _ = file.write(&size_bytes) catch return -6;

    // Write frame data
    _ = file.write(rgba_slice) catch return -6;

    g_writer_count += 1;
    return 0;
}

// Close writer
export fn yxcbor_close_writer() c_int {
    if (g_writer_file) |file| {
        file.close();
        g_writer_file = null;
    }
    return 0;
}

// ========== Reader API ==========

var g_reader_file: ?std.fs.File = null;
var g_reader_manifest: FrameManifest = undefined;
var g_reader_offsets: []u64 = undefined;

// Open reader for streaming frames
export fn yxcbor_open_reader(dir_path: [*:0]const u8, out_manifest: *FrameManifest) c_int {
    // Close any existing reader
    if (g_reader_file) |file| {
        file.close();
        g_reader_file = null;
    }

    const dir_str = std.mem.span(dir_path);

    // Read manifest
    const manifest_path = std.fmt.allocPrint(std.heap.page_allocator, "{s}/manifest.cbor", .{dir_str}) catch return -4;
    defer std.heap.page_allocator.free(manifest_path);

    const manifest_file = std.fs.openFileAbsolute(manifest_path, .{}) catch return -3;
    defer manifest_file.close();

    _ = manifest_file.read(std.mem.asBytes(&g_reader_manifest)) catch return -3;
    out_manifest.* = g_reader_manifest;

    // Open frames file
    const frames_path = std.fmt.allocPrint(std.heap.page_allocator, "{s}/frames.cbor", .{dir_str}) catch return -4;
    defer std.heap.page_allocator.free(frames_path);

    g_reader_file = std.fs.openFileAbsolute(frames_path, .{}) catch return -5;

    // Build offset table for random access
    g_reader_offsets = std.heap.page_allocator.alloc(u64, g_reader_manifest.frame_count) catch return -7;

    // Skip array header
    _ = g_reader_file.?.seekBy(5) catch return -10;

    // Calculate offsets
    var offset: u64 = 5;
    const frame_size = g_reader_manifest.width * g_reader_manifest.height * g_reader_manifest.channels;
    const cbor_overhead = 5; // 1 byte type + 4 bytes length

    for (0..g_reader_manifest.frame_count) |i| {
        g_reader_offsets[i] = offset;
        offset += cbor_overhead + frame_size;
    }

    return 0;
}

// Read a specific frame by index
export fn yxcbor_read_frame(index: u32, out_rgba: [*]u8, len: u32) c_int {
    const file = g_reader_file orelse return -1;

    if (index >= g_reader_manifest.frame_count) return -2;

    const expected_len = g_reader_manifest.width * g_reader_manifest.height * g_reader_manifest.channels;
    if (len != expected_len) return -3;

    // Seek to frame
    _ = file.seekTo(g_reader_offsets[index] + 5) catch return -10; // +5 to skip CBOR header

    // Read frame data
    const out_slice = out_rgba[0..len];
    _ = file.read(out_slice) catch return -10;

    return 0;
}

// Close reader
export fn yxcbor_close_reader() c_int {
    if (g_reader_file) |file| {
        file.close();
        g_reader_file = null;
    }
    if (g_reader_offsets.len > 0) {
        std.heap.page_allocator.free(g_reader_offsets);
    }
    return 0;
}