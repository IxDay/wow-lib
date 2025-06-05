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

        try writer.print("{s}", .{switch (self) {
            BLPColorEncoding.color_jpeg => "jpeg",
            BLPColorEncoding.color_palette => "palette",
            BLPColorEncoding.color_dxt => "dxt",
            BLPColorEncoding.color_argb8888 => "argb8888",
            BLPColorEncoding.color_argb8888_dup => "argb8888 dup",
        }});
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

    pub fn format(
        self: BLPPixelFormat,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        try writer.print("{s}", .{switch (self) {
            BLPPixelFormat.pixel_dxt1 => "dxt1",
            BLPPixelFormat.pixel_dxt3 => "dxt3",
            BLPPixelFormat.pixel_argb8888 => "argb8888",
            BLPPixelFormat.pixel_argb1555 => "argb1555",
            BLPPixelFormat.pixel_argb4444 => "argb4444",
            BLPPixelFormat.pixel_rgb565 => "rgb565",
            BLPPixelFormat.pixel_a8 => "a8",
            BLPPixelFormat.pixel_dxt5 => "dxt5",
            BLPPixelFormat.pixel_unspecified => "unspecified",
            BLPPixelFormat.pixel_argb2565 => "argb2565",
            BLPPixelFormat.pixel_bc5 => "bc5", // DXGI_FORMAT_BC5_UNOdxt1RM
            else => "invalid...",
        }});
    }
};

const MipmapLevelAndFlag = enum(u8) {
    mips_none = 0x0,
    mips_generated = 0x1,
    mips_handmade = 0x2,

    // You can also define mask constants
    pub const flags_mipmap_mask = 0xF; // level
    pub const flags_unk_0x10 = 0x10;

    pub fn format(
        self: MipmapLevelAndFlag,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        try writer.print("{s}", .{switch (self) {
            MipmapLevelAndFlag.mips_none => "none",
            MipmapLevelAndFlag.mips_generated => "generated",
            MipmapLevelAndFlag.mips_handmade => "handmade",
        }});
    }
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
        try writer.print("  Pixel Format: {}\n", .{self.preferred_format});
        try writer.print("  Mips: {}\n", .{self.has_mips});
        try writer.print("  Size: {d}x{d}\n", .{ self.width, self.height });
    }
};
