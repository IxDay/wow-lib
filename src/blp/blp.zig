const std = @import("std");

/// Error types for MPQ operations
const Error = error{
    InvalidFile,
    ReadError,
};

const BlpPalPixel = struct {
    b: u8,
    g: u8,
    r: u8,
    pad: u8,
};

const Jpeg = struct {
    header_size: u32,
    header_data: [1020]u8,
};

// BLP Color Encoding enum
const BLPColorEncoding = enum(u8) {
    color_jpeg = 0,
    color_palette = 1,
    color_dxt = 2,
    color_argb8888 = 3,
    color_argb8888_dup = 4, // same decompression, likely other PIXEL_FORMAT

    pub fn format(
        self: BLPColorEncoding,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        const repr = switch (self) {
            BLPColorEncoding.color_jpeg => "jpeg",
            BLPColorEncoding.color_palette => "palette",
            BLPColorEncoding.color_dxt => "dxt",
            BLPColorEncoding.color_argb8888 => "argb8888",
            BLPColorEncoding.color_argb8888_dup => "argb8888 dup",
        };
        try writer.print("{s}", .{repr});
    }
};

const BLPPixelFormat = enum(u8) {
    pixel_dxt1 = 0,
    pixel_dxt3 = 1,
    pixel_argb8888 = 2,
    pixel_argb1555 = 3,
    pixel_argb4444 = 4,
    pixel_rgb565 = 5,
    pixel_a8 = 6,
    pixel_dxt5 = 7,
    pixel_unspecified = 8,
    pixel_argb2565 = 9,
    pixel_bc5 = 11, // DXGI_FORMAT_BC5_UNORM
    num_pixel_formats = 12, // (no idea if format=10 exists)
};

const MipmapLevelAndFlag = enum(u8) {
    mips_none = 0x0,
    mips_generated = 0x1,
    mips_handmade = 0x2, // not supported

    // You can also define mask constants
    pub const flags_mipmap_mask = 0xF; // level
    pub const flags_unk_0x10 = 0x10;
};

const ExtendedData = union(enum) {
    palette: [256]BlpPalPixel,
    jpeg: Jpeg,
};

/// MPQ Header structure (standard format)
/// https://wowdev.wiki/BLP#Header
pub const Header = extern struct {
    // Magic identifier (always BLP2)
    magic: [4]u8,
    // Format version (always 1)
    format_version: u32,
    // Color encoding
    color_encoding: BLPColorEncoding,
    alpha_size: u8,
    preferred_format: BLPPixelFormat,
    has_mips: MipmapLevelAndFlag,
    width: u32,
    height: u32,
    mip_offsets: [16]u32,
    mip_sizes: [16]u32,
    // extended: ExtendedData,

    pub fn isValid(self: Header) bool {
        return std.mem.eql(u8, &self.magic, "BLP2");
    }

    pub fn hasUserData(self: Header) bool {
        return self.magic[3] == '\x1B';
    }

    pub fn sectorSize(self: Header) u32 {
        return @as(u32, 512) << @intCast(self.sector_size_shift);
    }

    pub fn init(reader: anytype) !Header {
        var header: Header = undefined;

        // Read the standard header
        const header_read = try reader.read(std.mem.asBytes(&header));

        if (header_read < @sizeOf(Header)) {
            return Error.ReadError;
        }

        // Check if it's a valid BLP file
        if (!header.isValid()) {
            return Error.InvalidFile;
        }

        return header;
    }

    pub fn format(
        self: Header,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        try writer.print("BLP Header:\n", .{});
        try writer.print("  Magic: {s} (Valid: {})\n", .{ self.magic, self.isValid() });
        try writer.print("  Format Version: {}\n", .{self.format_version});
        try writer.print("  Color Encoding: {}\n", .{self.color_encoding});
    }
};
