// yxcbor.zig - Fast streaming CBOR frame storage for RGB2GIF2VOXEL pipeline
// Optimized for 256×256 RGBA frames with minimal memory overhead

const std = @import("std");
const builtin = @import("builtin");

// CBOR tags for our custom types
const TAG_RGBA_FRAME: u64 = 0x1001;
const TAG_FRAME_MANIFEST: u64 = 0x1002;

// C-compatible manifest structure
pub const FrameManifest = extern struct {
    width: u32,
    height: u32,
    channels: u32,
    frame_count: u32,
};

// Global writer state for streaming API
var g_writer: ?Writer = null;
var g_reader: ?Reader = null;

const Writer = struct {
    dir_path: []u8,
    manifest: FrameManifest,
    frames_file: ?std.fs.File,
    current_frame: u32,
    allocator: std.mem.Allocator,
};

const Reader = struct {
    dir_path: []u8,
    manifest: FrameManifest,
    frames_file: ?std.fs.File,
    frame_offsets: []u64,
    allocator: std.mem.Allocator,
};

// CBOR encoding/decoding helpers
const cbor = struct {
    const MAJOR_UNSIGNED: u8 = 0x00;
    const MAJOR_NEGATIVE: u8 = 0x20;
    const MAJOR_BYTES: u8 = 0x40;
    const MAJOR_TEXT: u8 = 0x60;
    const MAJOR_ARRAY: u8 = 0x80;
    const MAJOR_MAP: u8 = 0xA0;
    const MAJOR_TAG: u8 = 0xC0;
    const MAJOR_SPECIAL: u8 = 0xE0;

    // Encoding functions
    fn writeTypeAndValue(writer: anytype, major: u8, value: u64) !void {
        if (value < 24) {
            try writer.writeByte(major | @as(u8, @intCast(value)));
        } else if (value <= 0xFF) {
            try writer.writeByte(major | 24);
            try writer.writeByte(@intCast(value));
        } else if (value <= 0xFFFF) {
            try writer.writeByte(major | 25);
            try writer.writeInt(u16, @intCast(value), .big);
        } else if (value <= 0xFFFFFFFF) {
            try writer.writeByte(major | 26);
            try writer.writeInt(u32, @intCast(value), .big);
        } else {
            try writer.writeByte(major | 27);
            try writer.writeInt(u64, value, .big);
        }
    }

    fn writeMapHeader(writer: anytype, size: usize) !void {
        try writeTypeAndValue(writer, MAJOR_MAP, size);
    }

    fn writeArrayHeader(writer: anytype, size: usize) !void {
        try writeTypeAndValue(writer, MAJOR_ARRAY, size);
    }

    fn writeTag(writer: anytype, tag: u64) !void {
        try writeTypeAndValue(writer, MAJOR_TAG, tag);
    }

    fn writeText(writer: anytype, text: []const u8) !void {
        try writeTypeAndValue(writer, MAJOR_TEXT, text.len);
        try writer.writeAll(text);
    }

    fn writeBytes(writer: anytype, bytes: []const u8) !void {
        try writeTypeAndValue(writer, MAJOR_BYTES, bytes.len);
        try writer.writeAll(bytes);
    }

    fn writeInt(writer: anytype, value: anytype) !void {
        const v = @as(u64, @intCast(value));
        try writeTypeAndValue(writer, MAJOR_UNSIGNED, v);
    }

    // Decoding functions
    fn readTypeAndValue(reader: anytype) !struct { major: u8, value: u64 } {
        const initial_byte = try reader.readByte();
        const major = initial_byte & 0xE0;
        const additional = initial_byte & 0x1F;

        const value: u64 = switch (additional) {
            0...23 => additional,
            24 => try reader.readByte(),
            25 => try reader.readInt(u16, .big),
            26 => try reader.readInt(u32, .big),
            27 => try reader.readInt(u64, .big),
            else => return error.InvalidCbor,
        };

        return .{ .major = major, .value = value };
    }

    fn readMapHeader(reader: anytype) !usize {
        const tv = try readTypeAndValue(reader);
        if (tv.major != MAJOR_MAP) return error.ExpectedMap;
        return @intCast(tv.value);
    }

    fn readArrayHeader(reader: anytype) !usize {
        const tv = try readTypeAndValue(reader);
        if (tv.major != MAJOR_ARRAY) return error.ExpectedArray;
        return @intCast(tv.value);
    }

    fn readTag(reader: anytype) !u64 {
        const tv = try readTypeAndValue(reader);
        if (tv.major != MAJOR_TAG) return error.ExpectedTag;
        return tv.value;
    }

    fn readText(allocator: std.mem.Allocator, reader: anytype) ![]u8 {
        const tv = try readTypeAndValue(reader);
        if (tv.major != MAJOR_TEXT) return error.ExpectedText;
        const buffer = try allocator.alloc(u8, @intCast(tv.value));
        _ = try reader.readAll(buffer);
        return buffer;
    }

    fn readBytes(allocator: std.mem.Allocator, reader: anytype) ![]u8 {
        const tv = try readTypeAndValue(reader);
        if (tv.major != MAJOR_BYTES) return error.ExpectedBytes;
        const buffer = try allocator.alloc(u8, @intCast(tv.value));
        _ = try reader.readAll(buffer);
        return buffer;
    }

    fn readInt(reader: anytype) !u64 {
        const tv = try readTypeAndValue(reader);
        if (tv.major != MAJOR_UNSIGNED) return error.ExpectedUnsigned;
        return tv.value;
    }

    fn skipValue(reader: anytype) !void {
        const tv = try readTypeAndValue(reader);

        switch (tv.major) {
            MAJOR_UNSIGNED, MAJOR_NEGATIVE, MAJOR_TAG, MAJOR_SPECIAL => {},
            MAJOR_BYTES, MAJOR_TEXT => {
                try reader.skipBytes(@intCast(tv.value), .{});
            },
            MAJOR_ARRAY => {
                var i: usize = 0;
                while (i < tv.value) : (i += 1) {
                    try skipValue(reader);
                }
            },
            MAJOR_MAP => {
                var i: usize = 0;
                while (i < tv.value) : (i += 1) {
                    try skipValue(reader); // key
                    try skipValue(reader); // value
                }
            },
            else => return error.InvalidCbor,
        }
    }
};

// Save manifest file
fn saveManifest(dir_path: []const u8, manifest: *const FrameManifest) !void {
    var path_buf: [4096]u8 = undefined;
    const manifest_path = try std.fmt.bufPrint(&path_buf, "{s}/manifest.cbor", .{dir_path});

    const file = try std.fs.cwd().createFile(manifest_path, .{});
    defer file.close();

    const writer = file.writer();

    // Write tagged manifest
    try cbor.writeTag(writer, TAG_FRAME_MANIFEST);
    try cbor.writeMapHeader(writer, 4);

    try cbor.writeText(writer, "width");
    try cbor.writeInt(writer, manifest.width);

    try cbor.writeText(writer, "height");
    try cbor.writeInt(writer, manifest.height);

    try cbor.writeText(writer, "channels");
    try cbor.writeInt(writer, manifest.channels);

    try cbor.writeText(writer, "frame_count");
    try cbor.writeInt(writer, manifest.frame_count);
}

// Load manifest file
fn loadManifest(allocator: std.mem.Allocator, dir_path: []const u8) !FrameManifest {
    var path_buf: [4096]u8 = undefined;
    const manifest_path = try std.fmt.bufPrint(&path_buf, "{s}/manifest.cbor", .{dir_path});

    const file = try std.fs.cwd().openFile(manifest_path, .{});
    defer file.close();

    var read_buf: [4096]u8 = undefined;
    const reader = file.reader(&read_buf);

    // Read tag
    const tag = try cbor.readTag(reader);
    if (tag != TAG_FRAME_MANIFEST) return error.InvalidManifest;

    const map_size = try cbor.readMapHeader(reader);

    var manifest = FrameManifest{
        .width = 0,
        .height = 0,
        .channels = 0,
        .frame_count = 0,
    };

    var i: usize = 0;
    while (i < map_size) : (i += 1) {
        const key = try cbor.readText(allocator, reader);
        defer allocator.free(key);

        if (std.mem.eql(u8, key, "width")) {
            manifest.width = @intCast(try cbor.readInt(reader));
        } else if (std.mem.eql(u8, key, "height")) {
            manifest.height = @intCast(try cbor.readInt(reader));
        } else if (std.mem.eql(u8, key, "channels")) {
            manifest.channels = @intCast(try cbor.readInt(reader));
        } else if (std.mem.eql(u8, key, "frame_count")) {
            manifest.frame_count = @intCast(try cbor.readInt(reader));
        } else {
            try cbor.skipValue(reader);
        }
    }

    return manifest;
}

// ============ C API Implementation ============

// Writer API
export fn yxcbor_open_writer(dir_path: [*:0]const u8, manifest: *const FrameManifest) c_int {
    if (g_writer != null) return -1; // Already open

    const allocator = std.heap.raw_c_allocator;
    const dir_slice = std.mem.span(dir_path);

    // Create directory
    std.fs.cwd().makePath(dir_slice) catch return -2;

    // Save manifest
    saveManifest(dir_slice, manifest) catch return -3;

    // Open frames file
    var path_buf: [4096]u8 = undefined;
    const frames_path = std.fmt.bufPrint(&path_buf, "{s}/frames.cbor", .{dir_slice}) catch return -4;

    const frames_file = std.fs.cwd().createFile(frames_path, .{}) catch return -5;

    // Write CBOR array header for frames
    var write_buf: [4096]u8 = undefined;
    const writer = frames_file.writer(&write_buf);
    cbor.writeArrayHeader(writer, manifest.frame_count) catch {
        frames_file.close();
        return -6;
    };

    // Initialize writer state
    const dir_copy = allocator.alloc(u8, dir_slice.len) catch {
        frames_file.close();
        return -7;
    };
    @memcpy(dir_copy, dir_slice);

    g_writer = Writer{
        .dir_path = dir_copy,
        .manifest = manifest.*,
        .frames_file = frames_file,
        .current_frame = 0,
        .allocator = allocator,
    };

    return 0; // Success
}

export fn yxcbor_write_frame(rgba_ptr: [*]const u8, len: u32) c_int {
    const writer_state = g_writer orelse return -1;

    if (writer_state.current_frame >= writer_state.manifest.frame_count) return -2;

    const expected_len = writer_state.manifest.width * writer_state.manifest.height * writer_state.manifest.channels;
    if (len != expected_len) return -3;

    const file = writer_state.frames_file orelse return -4;
    var write_buf: [262144]u8 = undefined; // 256KB buffer for frame data
    const writer = file.writer(&write_buf);

    // Write tagged frame data
    const rgba_slice = rgba_ptr[0..len];
    cbor.writeTag(writer, TAG_RGBA_FRAME) catch return -5;
    cbor.writeBytes(writer, rgba_slice) catch return -6;

    g_writer.?.current_frame += 1;

    return 0; // Success
}

export fn yxcbor_close_writer() c_int {
    if (g_writer) |*writer_state| {
        if (writer_state.frames_file) |file| {
            file.close();
        }
        writer_state.allocator.free(writer_state.dir_path);
        g_writer = null;
        return 0;
    }
    return -1; // Not open
}

// Reader API
export fn yxcbor_open_reader(dir_path: [*:0]const u8, out_manifest: *FrameManifest) c_int {
    if (g_reader != null) return -1; // Already open

    const allocator = std.heap.raw_c_allocator;
    const dir_slice = std.mem.span(dir_path);

    // Load manifest
    const manifest = loadManifest(allocator, dir_slice) catch return -2;
    out_manifest.* = manifest;

    // Open frames file
    var path_buf: [4096]u8 = undefined;
    const frames_path = std.fmt.bufPrint(&path_buf, "{s}/frames.cbor", .{dir_slice}) catch return -3;

    const frames_file = std.fs.cwd().openFile(frames_path, .{}) catch return -4;

    // Read array header and build offset table
    var read_buf: [4096]u8 = undefined;
    const reader = frames_file.reader(&read_buf);
    const array_size = cbor.readArrayHeader(reader) catch {
        frames_file.close();
        return -5;
    };

    if (array_size != manifest.frame_count) {
        frames_file.close();
        return -6;
    }

    // Build frame offset table for random access
    const frame_offsets = allocator.alloc(u64, manifest.frame_count) catch {
        frames_file.close();
        return -7;
    };

    var i: u32 = 0;
    while (i < manifest.frame_count) : (i += 1) {
        frame_offsets[i] = frames_file.getPos() catch {
            allocator.free(frame_offsets);
            frames_file.close();
            return -8;
        };

        // Skip frame data
        cbor.skipValue(reader) catch {
            allocator.free(frame_offsets);
            frames_file.close();
            return -9;
        };
    }

    // Initialize reader state
    const dir_copy = allocator.alloc(u8, dir_slice.len) catch {
        allocator.free(frame_offsets);
        frames_file.close();
        return -10;
    };
    @memcpy(dir_copy, dir_slice);

    g_reader = Reader{
        .dir_path = dir_copy,
        .manifest = manifest,
        .frames_file = frames_file,
        .frame_offsets = frame_offsets,
        .allocator = allocator,
    };

    return 0; // Success
}

export fn yxcbor_read_frame(index: u32, out_rgba: [*]u8, len: u32) c_int {
    const reader_state = g_reader orelse return -1;

    if (index >= reader_state.manifest.frame_count) return -2;

    const expected_len = reader_state.manifest.width * reader_state.manifest.height * reader_state.manifest.channels;
    if (len != expected_len) return -3;

    const file = reader_state.frames_file orelse return -4;

    // Seek to frame position
    file.seekTo(reader_state.frame_offsets[index]) catch return -5;

    var read_buf: [262144]u8 = undefined; // 256KB buffer for frame data
    const reader = file.reader(&read_buf);

    // Read tag and verify
    const tag = cbor.readTag(reader) catch return -6;
    if (tag != TAG_RGBA_FRAME) return -7;

    // Read frame data
    const tv = cbor.readTypeAndValue(reader) catch return -8;
    if (tv.major != cbor.MAJOR_BYTES) return -9;
    if (tv.value != len) return -10;

    const out_slice = out_rgba[0..len];
    _ = reader.readAll(out_slice) catch return -11;

    return 0; // Success
}

export fn yxcbor_close_reader() c_int {
    if (g_reader) |*reader_state| {
        if (reader_state.frames_file) |file| {
            file.close();
        }
        reader_state.allocator.free(reader_state.frame_offsets);
        reader_state.allocator.free(reader_state.dir_path);
        g_reader = null;
        return 0;
    }
    return -1; // Not open
}

// Legacy batch API for compatibility
export fn yxcbor_save_frame(
    path: [*:0]const u8,
    rgba_data: [*]const u8,
    width: u32,
    height: u32,
    index: u32,
) c_int {
    _ = index;
    const path_slice = std.mem.span(path);
    const data_slice = rgba_data[0..(width * height * 4)];

    const file = std.fs.cwd().createFile(path_slice, .{}) catch return -1;
    defer file.close();

    var write_buf: [262144]u8 = undefined;
    const writer = file.writer(&write_buf);

    // Write simple CBOR byte string
    cbor.writeTag(writer, TAG_RGBA_FRAME) catch return -2;
    cbor.writeBytes(writer, data_slice) catch return -3;

    return 0;
}

export fn yxcbor_load_frame(
    path: [*:0]const u8,
    out_rgba: [*]u8,
    out_width: *u32,
    out_height: *u32,
    out_index: *u32,
) c_int {
    const path_slice = std.mem.span(path);

    const file = std.fs.cwd().openFile(path_slice, .{}) catch return -1;
    defer file.close();

    var read_buf: [262144]u8 = undefined;
    const reader = file.reader(&read_buf);

    // Read tag
    const tag = cbor.readTag(reader) catch return -2;
    if (tag != TAG_RGBA_FRAME) return -3;

    // Read byte data
    const allocator = std.heap.raw_c_allocator;
    const data = cbor.readBytes(allocator, reader) catch return -4;
    defer allocator.free(data);

    // Assume 256x256 for now
    out_width.* = 256;
    out_height.* = 256;
    out_index.* = 0;

    const expected_size = 256 * 256 * 4;
    if (data.len != expected_size) return -5;

    @memcpy(out_rgba[0..expected_size], data);

    return 0;
}

// Test functions
test "CBOR encode/decode roundtrip" {

    // Test data
    const test_data = [_]u8{0xFF} ** (256 * 256 * 4);
    const manifest = FrameManifest{
        .width = 256,
        .height = 256,
        .channels = 4,
        .frame_count = 3,
    };

    // Create temp directory
    const temp_dir = "test_cbor_frames";
    try std.fs.cwd().makePath(temp_dir);
    defer std.fs.cwd().deleteTree(temp_dir) catch {};

    // Write frames
    try std.testing.expectEqual(@as(c_int, 0), yxcbor_open_writer(temp_dir, &manifest));

    var i: u32 = 0;
    while (i < 3) : (i += 1) {
        try std.testing.expectEqual(@as(c_int, 0), yxcbor_write_frame(&test_data, test_data.len));
    }

    try std.testing.expectEqual(@as(c_int, 0), yxcbor_close_writer());

    // Read frames back
    var read_manifest: FrameManifest = undefined;
    try std.testing.expectEqual(@as(c_int, 0), yxcbor_open_reader(temp_dir, &read_manifest));

    try std.testing.expectEqual(manifest, read_manifest);

    var read_data: [256 * 256 * 4]u8 = undefined;
    i = 0;
    while (i < 3) : (i += 1) {
        try std.testing.expectEqual(@as(c_int, 0), yxcbor_read_frame(i, &read_data, read_data.len));
        try std.testing.expectEqualSlices(u8, &test_data, &read_data);
    }

    try std.testing.expectEqual(@as(c_int, 0), yxcbor_close_reader());
}