const std = @import("std");
const utils = @import("utils");
const zigimg = @import("zigimg");

const Rgba = zigimg.color.Rgba32;

pub const Rgb565 = packed struct {
    r: u5,
    g: u6,
    b: u5,

    // Convert RGB888 to RGB565
    pub fn init(r: u8, g: u8, b: u8) Rgb565 {
        return Rgb565{
            .r = @truncate(r >> 3), // 8-bit to 5-bit: keep top 5 bits
            .g = @truncate(g >> 2), // 8-bit to 6-bit: keep top 6 bits
            .b = @truncate(b >> 3), // 8-bit to 5-bit: keep top 5 bits
        };
    }

    // Convert RGB565 back to RGB888
    pub fn toRgba(self: Rgb565) Rgba {
        return Rgba.initRgba(
            (@as(u8, self.r) << 3) | (@as(u8, self.r) >> 2), // Scale 5-bit to 8-bit
            (@as(u8, self.g) << 2) | (@as(u8, self.g) >> 4), // Scale 6-bit to 8-bit
            (@as(u8, self.b) << 3) | (@as(u8, self.b) >> 2), // Scale 5-bit to 8-bit
            255,
        );
    }

    pub fn compare(self: Rgb565, other: Rgb565) i2 {
        // Compare r first
        if (self.r < other.r) return -1;
        if (self.r > other.r) return 1;

        // r values are equal, compare g
        if (self.g < other.g) return -1;
        if (self.g > other.g) return 1;

        // r and g values are equal, compare b
        if (self.b < other.b) return -1;
        if (self.b > other.b) return 1;

        // All values are equal
        return 0;
    }
};

test "ensure rgba properly convert rgb565 to rgba" {
    // https://pkg.go.dev/seedhammer.com/image/rgb565 for testing
    const color = Rgb565.init(71, 47, 146).toRgba();

    try std.testing.expectEqual(66, color.r);
    try std.testing.expectEqual(44, color.g);
    try std.testing.expectEqual(148, color.b);
}

const Block = extern struct {
    color_0: Rgb565,
    color_1: Rgb565,

    indices: u32,

    pub fn init(read_seeker: anytype) !Block {
        var block: Block = undefined;
        const size = try read_seeker.read(std.mem.asBytes(&block));
        if (size != @sizeOf(Block)) {
            return error.InvalidInput;
        }
        return block;
    }

    pub fn decompress(self: Block) [16]Rgba {
        const color_0 = self.color_0.toRgba();
        const color_1 = self.color_1.toRgba();

        var pixels: [16]Rgba = undefined;
        var palette = [4]Rgba{ color_0, color_1, undefined, undefined };

        if (self.color_0.compare(self.color_1) > 0) {
            // no alpha mode
            palette[2] = interpolateColor(color_0, color_1, 1.0 / 3.0);
            palette[3] = interpolateColor(color_0, color_1, 2.0 / 3.0);
        } else {
            // 1-bit alpha mode: Color0 <= Color1
            palette[2] = interpolateColor(color_0, color_1, 0.5);
            palette[3] = Rgba.initRgba(0, 0, 0, 0);
        }
        var indices = self.indices;
        for (0..16) |i| {
            const color_index = @as(u2, @truncate(indices & 0x3));
            indices >>= 2;
            pixels[i] = palette[color_index];
        }
        return pixels;
    }
};

test "ensure Block is right size" {
    try std.testing.expect(@sizeOf(Block) == 8);
}

// Interpolate between two colors
fn interpolateColor(c0: Rgba, c1: Rgba, factor: f32) Rgba {
    const inv_factor = 1.0 - factor;
    return Rgba.initRgba(
        @as(u8, @intFromFloat(@as(f32, @floatFromInt(c0.r)) * inv_factor + @as(f32, @floatFromInt(c1.r)) * factor)),
        @as(u8, @intFromFloat(@as(f32, @floatFromInt(c0.g)) * inv_factor + @as(f32, @floatFromInt(c1.g)) * factor)),
        @as(u8, @intFromFloat(@as(f32, @floatFromInt(c0.b)) * inv_factor + @as(f32, @floatFromInt(c1.b)) * factor)),
        255,
    );
}

pub fn decompress(read_seeker: anytype, image: *zigimg.Image) !void {
    for (0..image.height / 4) |blocks_y| {
        for (0..image.width / 4) |blocks_x| {
            const pixels = (try Block.init(read_seeker)).decompress();

            for (0..4) |y| {
                for (0..4) |x| {
                    const src_idx = y * 4 + x;
                    const dst_x = blocks_x * 4 + x;
                    const dst_y = blocks_y * 4 + y;
                    const dst_idx = dst_y * image.width + dst_x;

                    image.pixels.rgba32[dst_idx] = pixels[src_idx];
                }
            }
        }
    }
}

test "decompress" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var buffer = utils.BufferReader.init(&[_]u8{
        // Block 1 (top-left 4x4)
        0xFF, 0x07, // color0 (red in RGB565)
        0x00, 0x00, // color1 (black in RGB565)
        0x00, 0x00, 0x00, 0x00, // indices (all use color0)

        // Block 2 (top-right 4x4)
        0x00, 0xF8, // color0 (blue in RGB565)
        0xFF, 0xFF, // color1 (white in RGB565)
        0xFF, 0xFF, 0xFF, 0xFF, // indices (all use color1)

        // Block 3 (bottom-left 4x4)
        0xE0, 0x07, // color0 (green in RGB565)
        0x00, 0x00, // color1 (black in RGB565)
        0x55, 0x55, 0x55, 0x55, // indices (checkerboard pattern)

        // Block 4 (bottom-right 4x4)
        0xFF, 0xFF, // color0 (white in RGB565)
        0x00, 0x00, // color1 (black in RGB565)
        0xAA, 0xAA, 0xAA, 0xAA, // indices (inverted checkerboard)
    });
    var image = try zigimg.Image.create(allocator, 8, 8, .rgba32);
    defer image.deinit();

    try decompress(&buffer, &image);

    // Print first few pixels for verification
    std.debug.print("Decompressed 8x8 DXT1 texture:\n", .{});
    for (0..4) |y| {
        for (0..8) |x| {
            const pixel = image.pixels.rgba32[y * 8 + x];
            std.debug.print("({}) ", .{pixel});
        }
        std.debug.print("\n", .{});
    }
}
