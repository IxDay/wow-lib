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

/// MPQ Hash Table Entry structure
const MPQHashEntry = extern struct {
    // File path hash part A
    name_hash_a: u32,
    // File path hash part B
    name_hash_b: u32,
    // Language of the file (locale)
    locale: u16,
    // Platform the file is used for
    platform: u16,
    // Index into the block table
    block_index: u32,

    // Constants for hash entry states
    const EMPTY: u32 = 0xFFFFFFFF;
    const DELETED: u32 = 0xFFFFFFFE;

    pub fn isEmpty(self: MPQHashEntry) bool {
        return self.name_hash_a == EMPTY;
    }

    pub fn isDeleted(self: MPQHashEntry) bool {
        return self.name_hash_a == DELETED;
    }

    pub fn isValid(self: MPQHashEntry) bool {
        return !self.isEmpty() and !self.isDeleted();
    }

    pub fn format(
        self: MPQHashEntry,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        if (self.isEmpty()) {
            try writer.print("Empty Hash Entry", .{});
            return;
        }

        if (self.isDeleted()) {
            try writer.print("Deleted Hash Entry", .{});
            return;
        }

        try writer.print("Hash Entry:\n", .{});
        try writer.print("  Name Hash A: 0x{X}\n", .{self.name_hash_a});
        try writer.print("  Name Hash B: 0x{X}\n", .{self.name_hash_b});
        try writer.print("  Locale: 0x{X}\n", .{self.locale});
        try writer.print("  Platform: 0x{X}\n", .{self.platform});
        try writer.print("  Block Index: {}\n", .{self.block_index});
    }
};

/// Error types for MPQ operations
const MPQError = error{
    InvalidMPQFile,
    ReadError,
    SeekError,
    InvalidHashTable,
    OutOfMemory,
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

/// Calculate a hash value for an MPQ key
fn hashString(str: []const u8, hash_type: u32) u32 {
    var seed1: u32 = 0x7FED7FED;
    var seed2: u32 = 0xEEEEEEEE;

    // Process each character
    for (str) |char| {
        // Convert to uppercase if it's a lowercase letter
        const upChar: u8 = if (char >= 'a' and char <= 'z') char - ('a' - 'A') else char;

        seed1 = crypto_table[(hash_type * 0x100) + upChar] ^ (seed1 + seed2);
        seed2 = upChar + seed1 + seed2 + (seed2 << 5) + 3;
    }

    return seed1;
}

/// Generate hash values for a filename
fn hashFilename(filename: []const u8) struct { hash_a: u32, hash_b: u32 } {
    const hash_a = hashString(filename, 0x100);
    const hash_b = hashString(filename, 0x200);

    return .{ .hash_a = hash_a, .hash_b = hash_b };
}

/// Decrypt MPQ table data
fn decryptMPQTable(data: []u32, key: u32) void {
    var seed = key;

    for (data) |*value| {
        // Update seed
        seed = (seed * 0x343FD) + 0x269EC3;

        // Decrypt the value
        value.* ^= seed;
    }
}

/// Read and decrypt the MPQ hash table
pub fn readHashTable(file: std.fs.File, header: MPQHeader, allocator: std.mem.Allocator) ![]MPQHashEntry {
    const table_size = header.hash_table_entries * @sizeOf(MPQHashEntry);

    // Allocate memory for the hash table
    const hash_entries = try allocator.alloc(MPQHashEntry, header.hash_table_entries);
    errdefer allocator.free(hash_entries);

    // Seek to the hash table position
    try file.seekTo(header.hash_table_offset);

    // Read the encrypted hash table
    const bytes_read = try file.read(std.mem.sliceAsBytes(hash_entries));
    if (bytes_read < table_size) {
        return MPQError.ReadError;
    }

    // // Decrypt the hash table
    // // MPQ uses a specific key for the hash table: "(hash table)"
    // const HASH_TABLE_KEY: u32 = 0xC3AF5B79; // Precomputed hash for "(hash table)"

    // // Cast to u32 array for decryption
    // const data_u32 = std.mem.bytesAsSlice(u32, std.mem.sliceAsBytes(hash_entries));
    // decryptMPQTable(data_u32, HASH_TABLE_KEY);

    return hash_entries;
}

// MPQ crypto table (normally this would be generated, but for brevity we'll use a placeholder)
// In a real implementation, you would generate this table or include the full table data
const crypto_table = [_]u32{
    // This is a placeholder - in a real implementation, this would be a 1024-entry table
    // Simplified demonstration values
    0x7FED7FED, 0xEEEEEEEE, // Add more values as needed
};

// Initialize the crypto table (in real implementation)
fn initCryptoTable() !void {
    // In a real implementation, this would initialize the full crypto table
    // For brevity, we're skipping the actual table generation
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

    // // Initialize crypto table
    // try initCryptoTable();

    // Read MPQ header
    const header = readMPQHeader(file) catch |err| {
        std.debug.print("Failed to read MPQ header: {}\n", .{err});
        return err;
    };

    // Print header information
    std.debug.print("{s}\n", .{header});

    // Read hash table
    const hash_table = readHashTable(file, header, allocator) catch |err| {
        std.debug.print("Failed to read hash table: {}\n", .{err});
        return err;
    };
    defer allocator.free(hash_table);

    // Print hash table entries
    const stdout = std.io.getStdOut().writer();
    std.debug.print("\nHash Table Entries:\n", .{});
    for (hash_table, 0..) |entry, i| {
        if (entry.isValid()) {
            try stdout.print("Entry {d}: {s}\n", .{ i, entry });
        }
    }

    return;
}
