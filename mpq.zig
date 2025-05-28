const std = @import("std");
const extract = @import("./extract.zig");

/// Error types for MPQ operations
const MPQError = error{
    InvalidMPQFile,
    ReadError,
    SeekError,
    InvalidHashTable,
    InvalidBlockTable,
    InvalidFileEntry,
    DecompressionError,
    DecryptionError,
    FileNotFound,
    OutOfMemory,
};

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
    extended_block_table_offset: u64 align(1) = 0,
    hash_table_offset_high: u16 = 0,
    block_table_offset_high: u16 = 0,

    pub fn isValid(self: MPQHeader) bool {
        return std.mem.eql(u8, &self.magic, "MPQ\x1A");
    }

    pub fn sectorSize(self: MPQHeader) u32 {
        return @as(u32, 512) << @as(u5, @truncate(self.sector_size_shift));
    }

    pub fn init(reader: anytype) !MPQHeader {
        var header: MPQHeader = undefined;

        // // Seek to beginning of file
        // try file.seekTo(0);

        // Read the standard header
        const header_read = try reader.read(std.mem.asBytes(&header)[0 .. @sizeOf(MPQHeader) - 12]); // Exclude extended fields

        if (header_read < @sizeOf(MPQHeader) - 12) {
            return MPQError.ReadError;
        }

        // Check if it's a valid MPQ file
        if (!header.isValid()) {
            return MPQError.InvalidMPQFile;
        }

        // If this is a v1 header, read extended fields
        if (header.format_version >= 1 and header.header_size >= @sizeOf(MPQHeader)) {
            _ = try reader.read(std.mem.asBytes(&header)[@sizeOf(MPQHeader) - 12 ..]);
        }

        return header;
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

// Error type that readers can return
const ReaderError = error{
    EndOfStream,
    InvalidInput,
    BrokenPipe,
    SystemResources,
    OperationAborted,
    NotOpenForReading,
    WouldBlock,
    ConnectionResetByPeer,
    IsDir,
    AccessDenied,
    Unexpected,
};

// Memory buffer reader
const BufferReader = struct {
    buffer: []const u8,
    pos: usize,

    pub fn init(buffer: []const u8) BufferReader {
        return BufferReader{ .buffer = buffer, .pos = 0 };
    }

    pub fn read(self: *BufferReader, buffer: []u8) ReaderError!usize {
        if (self.pos >= self.buffer.len) return 0;

        const available = self.buffer.len - self.pos;
        const to_read = @min(buffer.len, available);

        @memcpy(buffer[0..to_read], self.buffer[self.pos .. self.pos + to_read]);
        self.pos += to_read;

        return to_read;
    }
};

test "basic MPQ header read" {
    var buffer = BufferReader.init("MPQ\x1a" ++ // magic number
        "\x2c\x00\x00\x00" ++ // header size (44)
        "\x2e\xef\xba\xab" ++ // archive size (~2.8GB)
        "\x01\x00" ++ // format version (1)
        "\x03\x00" ++ // sector size shift (512 << 3 = 4096)
        "\xae\x81\x86\xab" ++ // hash table offset
        "\xae\x81\xa6\xab" ++ // block table offset
        "\x00\x00\x02\x00" ++ // hash table entries
        "\xd8\x46\x01\x00" ++ // block table entries
        "");
    const header = try MPQHeader.init(&buffer);
    try std.testing.expect(header.isValid());
    try std.testing.expect(header.header_size == 44);
    try std.testing.expect(header.format_version == 1);
    // std.debug.print("{}", .{header});
}

const MPQ = struct {
    header: MPQHeader,
    hashTable: []MPQHashEntry,

    pub fn init(readseeker: anytype, allocator: std.mem.Allocator) !MPQ {
        const header = try MPQHeader.init(readseeker);
        return MPQ{
            .header = header,
            .hashTable = try readHashTable(
                readseeker,
                &header,
                allocator,
            ),
        };
    }
    pub fn fileByName(self: *const MPQ, name: []const u8) bool {
        return fileByHash(self, extract.FileNameHash.init(name));
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

pub fn readHashTable(readSeeker: anytype, header: *const MPQHeader, allocator: std.mem.Allocator) ![]MPQHashEntry {
    const table_size = header.hash_table_entries * @sizeOf(MPQHashEntry);

    // Allocate memory for the hash table
    const hash_entries = try allocator.alloc(MPQHashEntry, header.hash_table_entries);
    errdefer allocator.free(hash_entries);

    // Seek to the hash table position
    try readSeeker.seekTo(header.hash_table_offset);

    // Read the encrypted hash table
    const bytes_read = try readSeeker.read(std.mem.sliceAsBytes(hash_entries));
    if (bytes_read < table_size) {
        return MPQError.ReadError;
    }

    // Decrypt the hash table
    // MPQ uses a specific key for the hash table: "(hash table)"
    extract.decrypt(std.mem.bytesAsSlice(u32, std.mem.sliceAsBytes(hash_entries)), extract.HASH_TABLE_DECRYPTION_KEY);
    return hash_entries;
}

pub fn fileByHash(mpq: *const MPQ, fileHash: extract.FileNameHash) bool {
    const nb_entries = mpq.header.hash_table_entries;
    for (fileHash.hash_a & (nb_entries - 1)..nb_entries) |i| {
        const hash_entry = mpq.hashTable[i];

        if (hash_entry.block_index == 0xffffffff) {
            break;
        }

        if (hash_entry.name_hash_a == fileHash.hash_b and hash_entry.name_hash_b == fileHash.hash_c) {
            return true;
        }
    }
    return false;
}

pub fn main() !void {
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
    const mpq = try MPQ.init(file, allocator);
    std.debug.print("{}\n", .{mpq.fileByName("(listfile)")});
    // std.debug.print("{}\n", .{extract.fileNameHash("(listfile)")});
}
