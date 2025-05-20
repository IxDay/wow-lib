const std = @import("std");

/// MPQ Header structure (standard format)
const MPQHeader = extern struct {
    // Magic identifier, must be "MPQ\x1A" (0x1A544D50 in little-endian)
    magic: [4]u8,
    // Size of the header, usually 32 bytes (0x20)
    header_size: u32,
    // Size of the archive
    archive_size: u32,
    // Format version (0 = original, 1 = extended)
    format_version: u16,
    // Sector size (usually 4096, as 512 << sector_size_shift)
    sector_size_shift: u16,
    // Offset to the hash table
    hash_table_offset: u32,
    // Offset to the block table
    block_table_offset: u32,
    // Number of entries in the hash table
    hash_table_entries: u32,
    // Number of entries in the block table
    block_table_entries: u32,

    // Extended MPQ Header fields (v1)
    extended_block_table_offset: u64 = 0,
    hash_table_offset_high: u16 = 0,
    block_table_offset_high: u16 = 0,

    pub fn isValid(self: MPQHeader) bool {
        return std.mem.eql(u8, &self.magic, "MPQ\x1A");
    }

    pub fn sectorSize(self: MPQHeader) u32 {
        return @as(u32, 512) << @as(u5, @truncate(self.sector_size_shift));
    }

    pub fn format(
        self: MPQHeader,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        try writer.print("MPQ Header:\n", .{});
        try writer.print("  Magic: {s} (Valid: {})\n", .{ self.magic, self.isValid() });
        try writer.print("  Header Size: 0x{X} ({} bytes)\n", .{ self.header_size, self.header_size });
        try writer.print("  Archive Size: 0x{X} ({} bytes)\n", .{ self.archive_size, self.archive_size });
        try writer.print("  Format Version: {}\n", .{self.format_version});
        try writer.print("  Sector Size: {} bytes\n", .{self.sectorSize()});
        try writer.print("  Hash Table Offset: 0x{X}\n", .{self.hash_table_offset});
        try writer.print("  Block Table Offset: 0x{X}\n", .{self.block_table_offset});
        try writer.print("  Hash Table Entries: {}\n", .{self.hash_table_entries});
        try writer.print("  Block Table Entries: {}\n", .{self.block_table_entries});

        if (self.format_version >= 1) {
            try writer.print("  Extended Block Table Offset: 0x{X}\n", .{self.extended_block_table_offset});
            try writer.print("  Hash Table Offset High: 0x{X}\n", .{self.hash_table_offset_high});
            try writer.print("  Block Table Offset High: 0x{X}\n", .{self.block_table_offset_high});
        }
    }
};

/// Error types for MPQ operations
const MPQError = error{
    InvalidMPQFile,
    ReadError,
    SeekError,
};

/// Read an MPQ header from a file
pub fn readMPQHeader(file: std.fs.File) !MPQHeader {
    var header: MPQHeader = undefined;

    // Seek to beginning of file
    try file.seekTo(0);

    // Read the standard header
    const header_read = try file.read(std.mem.asBytes(&header)[0 .. @sizeOf(MPQHeader) - 12]); // Exclude extended fields

    if (header_read < @sizeOf(MPQHeader) - 12) {
        return MPQError.ReadError;
    }

    // Check if it's a valid MPQ file
    if (!header.isValid()) {
        return MPQError.InvalidMPQFile;
    }

    // If this is a v1 header, read extended fields
    if (header.format_version >= 1 and header.header_size >= @sizeOf(MPQHeader)) {
        _ = try file.read(std.mem.asBytes(&header)[@sizeOf(MPQHeader) - 12 ..]);
    }

    return header;
}

pub fn main() !void {
    // Get allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Get args
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    // Skip program name
    _ = args.next();

    // Get MPQ file path
    const mpq_path = args.next() orelse {
        std.debug.print("Usage: {s} <mpq_file_path>\n", .{std.os.argv[0]});
        return error.InvalidArgs;
    };
    // Open MPQ file
    const file = std.fs.cwd().openFile(mpq_path, .{}) catch |err| {
        std.debug.print("Failed to open MPQ file: {}\n", .{err});
        return err;
    };
    defer file.close();

    // Read MPQ header
    const header = readMPQHeader(file) catch |err| {
        std.debug.print("Failed to read MPQ header: {}\n", .{err});
        return err;
    };

    // Print header information
    std.debug.print("{s}\n", .{header});

    return;
}
