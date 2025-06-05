const std = @import("std");
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
    pub fn toRgba(self: Rgb565) zigimg.color.Rgba32 {
        return Rgba.initRgba(
            (@as(u8, self.r) << 3) | (@as(u8, self.r) >> 2), // Scale 5-bit to 8-bit
            (@as(u8, self.g) << 2) | (@as(u8, self.g) >> 4), // Scale 6-bit to 8-bit
            (@as(u8, self.b) << 3) | (@as(u8, self.b) >> 2), // Scale 5-bit to 8-bit
            @as(u8, 255),
        );
    }
};

const DXT1Block = struct {
    color_0: Rgb565,
    color_1: Rgb565,

    indices: u32,
};

fn rgba(color: Rgb565) Rgba {
    return Rgba.initRgba(
        zigimg.color.scaleToIntColor(u8, color.r),
        zigimg.color.scaleToIntColor(u8, color.g),
        zigimg.color.scaleToIntColor(u8, color.b),
        @as(u8, 255),
    );
}

fn rgb565ToRgb(color: Rgb565) Rgba {
    const r5 = @as(u8, color.r) & 0x1F;
    const g6 = @as(u8, color.b) & 0x3F;
    const b5 = @as(u8, color.g) & 0x1F;

    // Expand to 8-bit by replicating high bits
    return Rgba.initRgba(
        (r5 << 3) | (r5 >> 2),
        (g6 << 2) | (g6 >> 4),
        (b5 << 3) | (b5 >> 2),
        @as(u8, 255),
    );
}

test "ensure rgba properly convert rgb565 to rgba" {
    // https://pkg.go.dev/seedhammer.com/image/rgb565 for testing
    const color = Rgb565.init(71, 47, 146).toRgba();

    try std.testing.expectEqual(66, color.r);
    try std.testing.expectEqual(44, color.g);
    try std.testing.expectEqual(148, color.b);
}

// pub fn decompress(block: DXT1Block, pixels: []zigimg.color.Rgba32) !void {
//     const color_0 = rgba(block.color_0);
//     const color_1 = rgba(block.color_1);

//     // build color palette
//     var palette = [4]zigimg.color.Rgba32{

//     };

//     // direct colors
//     // palette[0] =

// }

// pub fn decodeDXT1(readseeker: anytype, width: u32, height: u32, allocator: std.mem.Allocator) !zigimg.Image {
//     const image = try zigimg.Image.create(
//         allocator,
//         width,
//         height,
//         .rgba32,
//     );
//     // var buf: [8]u8 = undefined;
//     for (0..height / 4) |y| {
//         for (0..width / 4) |x| {
//             const block: DXT1Block = undefined;
//             _ = try readseeker.read(std.mem.asBytes(&block));
//             const pixels: [16]zigimg.color.Rgba32 = undefined;
//             // image.pixels.rgba[y+x]
//         }
//     }
//     // for (image.pixels.rgba32, 0..) |_, i| {
//     //     image.pixels.rgba32[i] = zigimg.color.Rgba32.initRgba(255, 50, 25, 3);
//     // }
//     return zigimg.Image;
// }
