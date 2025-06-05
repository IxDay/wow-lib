const std = @import("std");
const zigimg = @import("zigimg");
const dxt1 = @import("./dxt1.zig");

/// Error types for MPQ operations
const Error = error{
    InvalidFile,
    UnsupportedFormat,
    ReadError,
};

// BLP Color Encoding enum
const ColorEncoding = enum(u8) {
    jpeg = 0,
    palette = 1,
    dxt = 2,
    argb8888 = 3,
    argb8888_dup = 4, // same decompression, likely other PIXEL_FORMAT

    pub fn format(
        self: ColorEncoding,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        try writer.print("{s}", .{switch (self) {
            ColorEncoding.jpeg => "jpeg",
            ColorEncoding.palette => "palette",
            ColorEncoding.dxt => "dxt",
            ColorEncoding.argb8888 => "argb8888",
            ColorEncoding.argb8888_dup => "argb8888 dup",
        }});
    }
};

const PixelFormat = enum(u8) {
    dxt1 = 0,
    dxt3 = 1,
    argb8888 = 2,
    argb1555 = 3,
    argb4444 = 4,
    rgb565 = 5,
    a8 = 6,
    dxt5 = 7,
    unspecified = 8,
    argb2565 = 9,
    bc5 = 11, // DXGI_FORMAT_BC5_UNORM
    num_pixel_formats = 12, // (no idea if format=10 exists)

    pub fn format(
        self: PixelFormat,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        try writer.print("{s}", .{switch (self) {
            PixelFormat.dxt1 => "dxt1",
            PixelFormat.dxt3 => "dxt3",
            PixelFormat.argb8888 => "argb8888",
            PixelFormat.argb1555 => "argb1555",
            PixelFormat.argb4444 => "argb4444",
            PixelFormat.rgb565 => "rgb565",
            PixelFormat.a8 => "a8",
            PixelFormat.dxt5 => "dxt5",
            PixelFormat.unspecified => "unspecified",
            PixelFormat.argb2565 => "argb2565",
            PixelFormat.bc5 => "bc5", // DXGI_FORMAT_BC5_UNOdxt1RM
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

const DecompressFunc = *const fn (anytype, u32, u32, std.mem.Allocator) zigimg.Image;

const Format = enum(u24) {
    jpeg = 0,

    paletted_alpha_none = paletted(Alpha.none),
    paletted_alpha_1 = paletted(Alpha.depth_1),
    paletted_alpha_4 = paletted(Alpha.depth_4),
    paletted_alpha_8 = paletted(Alpha.depth_8),

    raw_bgra = @as(u24, @intFromEnum(ColorEncoding.argb8888)) << 16,

    dxt_1_no_alpha = dxt(PixelFormat.dxt1, Alpha.none),
    dxt_1_alpha_1 = dxt(PixelFormat.dxt1, Alpha.depth_1),

    dxt_3_alpha_4 = dxt(PixelFormat.dxt3, Alpha.depth_4),
    dxt_3_alpha_8 = dxt(PixelFormat.dxt3, Alpha.depth_8),

    dxt_5_alpha_8 = dxt(PixelFormat.dxt5, Alpha.depth_8),

    fn paletted(depth: Alpha) u24 {
        return @as(u24, @intFromEnum(ColorEncoding.palette)) << 16 | @intFromEnum(depth);
    }

    fn dxt(format: PixelFormat, depth: Alpha) u24 {
        return @as(u24, @intFromEnum(ColorEncoding.dxt)) << 16 |
            @as(u16, @intFromEnum(format)) << 8 | @intFromEnum(depth);
    }

    pub fn init(header: Header) !Format {
        return switch (header.color_encoding) {
            ColorEncoding.jpeg => Format.jpeg,
            ColorEncoding.palette => @enumFromInt(paletted(header.alpha_depth)),
            ColorEncoding.dxt => @enumFromInt(dxt(header.preferred_format, header.alpha_depth)),
            else => error.UnsupportedFormat,
        };
    }
};

const Alpha = enum(u8) {
    none = 0,
    depth_1 = 1 << 0,
    depth_4 = 1 << 2,
    depth_8 = 1 << 3,
};

/// MPQ Header structure (standard format)
/// https://wowdev.wiki/BLP#Header
pub const Header = extern struct {
    // Magic identifier (always BLP2)
    magic: [4]u8,
    // Format version (always 1)
    format_version: u32,
    // Color encoding
    color_encoding: ColorEncoding,
    alpha_depth: Alpha,
    preferred_format: PixelFormat,
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

        try writer.print("BLP Header (size {d}):\n", .{@sizeOf(Header)});
        try writer.print("  Magic: {s} (Valid: {})\n", .{ self.magic, self.isValid() });
        try writer.print("  Format Version: {}\n", .{self.format_version});
        try writer.print("  Format: {}\n", .{try Format.init(self)});
        try writer.print("  Color Encoding: {}\n", .{self.color_encoding});
        try writer.print("  Alpha: {}\n", .{self.alpha_depth});
        try writer.print("  Pixel Format: {}\n", .{self.preferred_format});
        try writer.print("  Mips: {}\n", .{self.has_mips});
        try writer.print("  Size: {d}x{d}\n", .{ self.width, self.height });
        try writer.print("  Mip offsets: {any}\n", .{self.mip_offsets});
        try writer.print("  Mip sizes: {any}\n", .{self.mip_sizes});
    }
};

pub const BLP = struct {
    header: Header,

    pub fn init(read_seeker: anytype) !BLP {
        const header = try Header.init(read_seeker);
        return BLP{
            .header = header,
        };
    }

    pub fn toImg(self: *const BLP, read_seeker: anytype, allocator: std.mem.Allocator) !zigimg.Image {
        const format = try Format.init(self.header);
        // we only extract the first and biggest mip
        try read_seeker.seekTo(self.header.mip_offsets[0]);

        var image = try zigimg.Image.create(
            allocator,
            self.header.width,
            self.header.height,
            .rgba32,
        );
        try switch (format) {
            Format.dxt_1_alpha_1 => dxt1.decompress(read_seeker, &image),
            else => Error.UnsupportedFormat,
        };
        return image;
    }
};
