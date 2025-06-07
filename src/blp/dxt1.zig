const std = @import("std");
const utils = @import("utils");
const zigimg = @import("zigimg");

const Rgba = zigimg.color.Rgba32;

pub const Rgb565 = packed struct {
    encoding: u16,

    pub fn init(r: u8, g: u8, b: u8) Rgb565 {
        const r5 = r >> 3; // Truncate 8-bit red to 5-bit (keep upper 5 bits)
        const g6 = g >> 2; // Truncate 8-bit green to 6-bit (keep upper 6 bits)
        const b5 = b >> 3; // Truncate 8-bit blue to 5-bit (keep upper 5 bits)

        return Rgb565{
            .encoding = (@as(u16, r5) << 11) | (@as(u16, g6) << 5) | @as(u16, b5),
        };
    }

    // Convert RGB565 back to RGB888
    pub fn toRgba(self: Rgb565) Rgba {
        const r: u8 = @truncate((self.encoding >> 11) & 0x1F);
        const g: u8 = @truncate((self.encoding >> 5) & 0x3F);
        const b: u8 = @truncate(self.encoding & 0x1F);
        return Rgba{
            .r = (r << 3) | (r >> 2),
            .g = (g << 2) | (g >> 4),
            .b = (b << 3) | (b >> 2),
            .a = 0xff,
        };
    }

    pub fn compare(self: Rgb565, other: Rgb565) i2 {
        if (self.encoding > other.encoding) return 1;
        if (self.encoding < other.encoding) return -1;
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

test "DXT1 decompress" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const red = Rgba.initRgb(255, 0, 0);
    const green = Rgba.initRgb(0, 255, 0);
    const blue = Rgba.initRgb(0, 0, 255);
    const black = Rgba.initRgb(0, 0, 0);
    const expected = [64]Rgba{
        red,  red,  red,  red,  green, green, green, green,
        red,  red,  red,  red,  green, green, green, green,
        red,  red,  red,  red,  green, green, green, green,
        red,  red,  red,  red,  green, green, green, green,
        blue, blue, blue, blue, black, black, black, black,
        blue, blue, blue, blue, black, black, black, black,
        blue, blue, blue, blue, black, black, black, black,
        blue, blue, blue, blue, black, black, black, black,
    };

    var image = try zigimg.Image.create(allocator, 8, 8, .rgba32);
    defer image.deinit();

    var buffer = utils.BufferReader.init(&[_]u8{
        // Block 1 (top-left) RED
        0x00, 0xf8, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        // Block 2 (top-right) GREEN
        0xe0, 0x07, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        // Block 3 (bottom-left) BLUE
        0x1f, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        // Block 4 (bottom-right) BLACK
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    });

    try decompress(&buffer, &image);

    // Print first few pixels for verification
    for (0..8) |y| {
        for (0..8) |x| {
            const pixel = image.pixels.rgba32[y * 8 + x];
            // std.debug.print(
            //     "\x1b[38;2;{};{};{}m█\x1b[0m",
            //     .{ pixel.r, pixel.g, pixel.b },
            // );
            try std.testing.expectEqualDeep(expected[y * 8 + x], pixel);
        }
        // std.debug.print("\n", .{});
    }
}
