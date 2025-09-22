// qoi.zig
// QOI (Quite OK Image) format implementation for fast intermediate storage
// 20-50x faster encoding than PNG, 3-4x faster decoding

const std = @import("std");

// QOI format constants
const QOI_MAGIC = [4]u8{ 'q', 'o', 'i', 'f' };
const QOI_HEADER_SIZE = 14;
const QOI_PADDING_SIZE = 8;

const QOI_OP_RGB = 0b11111110;
const QOI_OP_RGBA = 0b11111111;
const QOI_OP_INDEX = 0b00000000;
const QOI_OP_DIFF = 0b01000000;
const QOI_OP_LUMA = 0b10000000;
const QOI_OP_RUN = 0b11000000;

pub const QoiHeader = struct {
    magic: [4]u8,
    width: u32,
    height: u32,
    channels: u8, // 3 = RGB, 4 = RGBA
    colorspace: u8, // 0 = sRGB with linear alpha, 1 = all linear
};

pub const QoiEncoder = struct {
    allocator: std.mem.Allocator,
    width: u32,
    height: u32,
    channels: u8,

    pub fn init(allocator: std.mem.Allocator, width: u32, height: u32, channels: u8) QoiEncoder {
        return .{
            .allocator = allocator,
            .width = width,
            .height = height,
            .channels = channels,
        };
    }

    /// Encode raw pixel data to QOI format (20-50x faster than PNG)
    pub fn encode(self: *const QoiEncoder, pixels: []const u8) ![]u8 {
        const pixel_count = self.width * self.height;
        const max_size = QOI_HEADER_SIZE + pixel_count * (if (self.channels == 4) 5 else 4) + QOI_PADDING_SIZE;

        var output = try self.allocator.alloc(u8, max_size);
        var pos: usize = 0;

        // Write header
        std.mem.copy(u8, output[pos..pos + 4], &QOI_MAGIC);
        pos += 4;
        std.mem.writeIntBig(u32, output[pos..pos + 4], self.width);
        pos += 4;
        std.mem.writeIntBig(u32, output[pos..pos + 4], self.height);
        pos += 4;
        output[pos] = self.channels;
        pos += 1;
        output[pos] = 0; // sRGB colorspace
        pos += 1;

        // Color cache for QOI_OP_INDEX
        var index = [_][4]u8{[_]u8{0} ** 4} ** 64;
        var prev_pixel = [4]u8{ 0, 0, 0, 255 };

        var run: u8 = 0;
        var px_pos: usize = 0;

        while (px_pos < pixels.len) {
            var pixel = [4]u8{
                pixels[px_pos],
                pixels[px_pos + 1],
                pixels[px_pos + 2],
                if (self.channels == 4) pixels[px_pos + 3] else 255,
            };

            if (std.mem.eql(u8, &pixel, &prev_pixel)) {
                run += 1;
                if (run == 62 or px_pos + self.channels >= pixels.len) {
                    output[pos] = QOI_OP_RUN | (run - 1);
                    pos += 1;
                    run = 0;
                }
            } else {
                if (run > 0) {
                    output[pos] = QOI_OP_RUN | (run - 1);
                    pos += 1;
                    run = 0;
                }

                const index_pos = hashPixel(pixel);

                if (std.mem.eql(u8, &index[index_pos], &pixel)) {
                    output[pos] = QOI_OP_INDEX | @intCast(u8, index_pos);
                    pos += 1;
                } else {
                    index[index_pos] = pixel;

                    if (pixel[3] == prev_pixel[3]) {
                        const vr = @intCast(i8, pixel[0]) - @intCast(i8, prev_pixel[0]);
                        const vg = @intCast(i8, pixel[1]) - @intCast(i8, prev_pixel[1]);
                        const vb = @intCast(i8, pixel[2]) - @intCast(i8, prev_pixel[2]);

                        const vr_vg = vr - vg;
                        const vb_vg = vb - vg;

                        if (vr > -3 and vr < 2 and vg > -3 and vg < 2 and vb > -3 and vb < 2) {
                            output[pos] = QOI_OP_DIFF | (@intCast(u8, vr + 2) << 4) |
                                         (@intCast(u8, vg + 2) << 2) | @intCast(u8, vb + 2);
                            pos += 1;
                        } else if (vr_vg > -9 and vr_vg < 8 and vg > -33 and vg < 32 and vb_vg > -9 and vb_vg < 8) {
                            output[pos] = QOI_OP_LUMA | @intCast(u8, vg + 32);
                            output[pos + 1] = (@intCast(u8, vr_vg + 8) << 4) | @intCast(u8, vb_vg + 8);
                            pos += 2;
                        } else {
                            output[pos] = QOI_OP_RGB;
                            output[pos + 1] = pixel[0];
                            output[pos + 2] = pixel[1];
                            output[pos + 3] = pixel[2];
                            pos += 4;
                        }
                    } else {
                        output[pos] = QOI_OP_RGBA;
                        output[pos + 1] = pixel[0];
                        output[pos + 2] = pixel[1];
                        output[pos + 3] = pixel[2];
                        output[pos + 4] = pixel[3];
                        pos += 5;
                    }
                }
            }

            prev_pixel = pixel;
            px_pos += self.channels;
        }

        // Write end padding
        for (0..QOI_PADDING_SIZE) |i| {
            output[pos + i] = if (i < 7) 0 else 1;
        }
        pos += QOI_PADDING_SIZE;

        // Resize to actual size
        return self.allocator.realloc(output, pos) catch output[0..pos];
    }

    fn hashPixel(pixel: [4]u8) u6 {
        return @truncate(u6, (pixel[0] *% 3 +% pixel[1] *% 5 +% pixel[2] *% 7 +% pixel[3] *% 11));
    }
};

pub const QoiDecoder = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) QoiDecoder {
        return .{ .allocator = allocator };
    }

    /// Decode QOI format to raw pixels (3-4x faster than PNG)
    pub fn decode(self: *const QoiDecoder, data: []const u8) !struct { pixels: []u8, header: QoiHeader } {
        if (data.len < QOI_HEADER_SIZE) return error.InvalidQoiFile;

        // Parse header
        var header = QoiHeader{
            .magic = data[0..4].*,
            .width = std.mem.readIntBig(u32, data[4..8]),
            .height = std.mem.readIntBig(u32, data[8..12]),
            .channels = data[12],
            .colorspace = data[13],
        };

        if (!std.mem.eql(u8, &header.magic, &QOI_MAGIC)) return error.InvalidQoiMagic;

        const pixel_count = header.width * header.height;
        const output_size = pixel_count * header.channels;
        var pixels = try self.allocator.alloc(u8, output_size);

        // Color cache
        var index = [_][4]u8{[_]u8{0} ** 4} ** 64;
        var pixel = [4]u8{ 0, 0, 0, 255 };

        var pos: usize = QOI_HEADER_SIZE;
        var px_pos: usize = 0;
        var run: u8 = 0;

        while (px_pos < output_size) {
            if (run > 0) {
                run -= 1;
            } else if (pos < data.len) {
                const b1 = data[pos];
                pos += 1;

                if (b1 == QOI_OP_RGB) {
                    pixel[0] = data[pos];
                    pixel[1] = data[pos + 1];
                    pixel[2] = data[pos + 2];
                    pos += 3;
                } else if (b1 == QOI_OP_RGBA) {
                    pixel[0] = data[pos];
                    pixel[1] = data[pos + 1];
                    pixel[2] = data[pos + 2];
                    pixel[3] = data[pos + 3];
                    pos += 4;
                } else if ((b1 & 0b11000000) == QOI_OP_INDEX) {
                    pixel = index[b1 & 0b00111111];
                } else if ((b1 & 0b11000000) == QOI_OP_DIFF) {
                    pixel[0] +%= @bitCast(i8, ((b1 >> 4) & 0b11) -% 2);
                    pixel[1] +%= @bitCast(i8, ((b1 >> 2) & 0b11) -% 2);
                    pixel[2] +%= @bitCast(i8, (b1 & 0b11) -% 2);
                } else if ((b1 & 0b11000000) == QOI_OP_LUMA) {
                    const b2 = data[pos];
                    pos += 1;
                    const vg = @bitCast(i8, (b1 & 0b00111111) -% 32);
                    pixel[0] +%= vg +% @bitCast(i8, ((b2 >> 4) & 0b1111) -% 8);
                    pixel[1] +%= vg;
                    pixel[2] +%= vg +% @bitCast(i8, (b2 & 0b1111) -% 8);
                } else if ((b1 & 0b11000000) == QOI_OP_RUN) {
                    run = b1 & 0b00111111;
                }

                index[hashPixel(pixel)] = pixel;
            }

            pixels[px_pos] = pixel[0];
            pixels[px_pos + 1] = pixel[1];
            pixels[px_pos + 2] = pixel[2];
            if (header.channels == 4) {
                pixels[px_pos + 3] = pixel[3];
            }

            px_pos += header.channels;
        }

        return .{ .pixels = pixels, .header = header };
    }

    fn hashPixel(pixel: [4]u8) u6 {
        return @truncate(u6, (pixel[0] *% 3 +% pixel[1] *% 5 +% pixel[2] *% 7 +% pixel[3] *% 11));
    }
};