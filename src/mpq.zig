const std = @import("std");
const utils = @import("./utils.zig");
const hash = @import("./hash.zig");

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
pub const Header = extern struct {
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

    pub fn isValid(self: Header) bool {
        return std.mem.eql(u8, &self.magic, "MPQ\x1A") or
            std.mem.eql(u8, &self.magic, "MPQ\x1B");
    }

    pub fn hasUserData(self: Header) bool {
        return self.magic[3] == '\x1B';
    }

    pub fn sectorSize(self: Header) u32 {
        return @as(u32, 512) << @intCast(self.sector_size_shift);
    }

    pub fn init(reader: anytype) !Header {
        var header: Header = undefined;

        // // Seek to beginning of file
        // try file.seekTo(0);

        // Read the standard header
        const header_read = try reader.read(std.mem.asBytes(&header)[0 .. @sizeOf(Header) - 12]); // Exclude extended fields

        if (header_read < @sizeOf(Header) - 12) {
            return MPQError.ReadError;
        }

        // Check if it's a valid MPQ file
        if (!header.isValid()) {
            return MPQError.InvalidMPQFile;
        }

        // If this is a v1 header, read extended fields
        if (header.format_version >= 1 and header.header_size >= @sizeOf(Header)) {
            _ = try reader.read(std.mem.asBytes(&header)[@sizeOf(Header) - 12 ..]);
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

        try writer.print("MPQ Header:\n", .{});
        try writer.print("  Magic: {s} (Valid: {})\n", .{ self.magic, self.isValid() });
        try writer.print("  User Data: {}\n", .{self.hasUserData()});
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

test "basic MPQ header read" {
    var buffer = utils.BufferReader.init("MPQ\x1a" ++ // magic number
        "\x2c\x00\x00\x00" ++ // header size (44)
        "\x2e\xef\xba\xab" ++ // archive size (~2.8GB)
        "\x01\x00" ++ // format version (1)
        "\x03\x00" ++ // sector size shift (512 << 3 = 4096)
        "\xae\x81\x86\xab" ++ // hash table offset
        "\xae\x81\xa6\xab" ++ // block table offset
        "\x00\x00\x02\x00" ++ // hash table entries
        "\xd8\x46\x01\x00" ++ // block table entries
        "");
    const header = try Header.init(&buffer);
    try std.testing.expect(header.isValid());
    try std.testing.expect(header.header_size == 44);
    try std.testing.expect(header.format_version == 1);
    // std.debug.print("{}", .{header});
}

pub const MPQ = struct {
    header: Header,
    hash_table: std.ArrayList(HashEntry),
    block_table: std.ArrayList(BlockEntry),
    block_entry_indices: std.ArrayList(usize),
    files_count: u32,

    pub fn init(read_seeker: anytype, allocator: std.mem.Allocator) !MPQ {
        const header = try Header.init(read_seeker);
        var mpq = MPQ{
            .header = header,
            .hash_table = undefined,
            .block_table = undefined,
            .block_entry_indices = undefined,
            .files_count = 0,
        };
        try readHashTable(&mpq, read_seeker, allocator);
        try readBlockTable(&mpq, read_seeker, allocator);
        return mpq;
    }
    pub fn fileByName(self: *const MPQ, read_seeker: anytype, name: []const u8, allocator: std.mem.Allocator) !?[]u8 {
        const entry = try hashEntry(self, hash.FileName.init(name));
        var counter: u32 = 0;

        for (0..entry.hash.block_index) |i| {
            if (!self.block_table.items[i].exists()) counter += 1;
        }

        const file_index = entry.hash.block_index - counter;
        if (file_index < 0 or file_index > self.files_count) {
            return null;
        }
        const block_entry_index = self.block_entry_indices.items[file_index];
        const block_entry = self.block_table.items[block_entry_index];
        const block_size = self.header.sectorSize();
        const block_offset = block_entry.file_position;
        const block_count = if (block_entry.isSingle())
            1
        else
            (block_entry.file_size + block_size - 1) / block_size;

        const packed_block_offsets = try allocator.alloc(
            u32,
            if (block_entry.hasExtra()) block_count + 2 else block_count + 1,
        );
        if (block_entry.isCompressed() and !block_entry.isSingle()) {
            try read_seeker.seekTo(block_offset);
            _ = try read_seeker.read(std.mem.sliceAsBytes(packed_block_offsets));
            if (block_entry.isEncrypted()) {
                return MPQError.InvalidMPQFile;
            }
        } else {
            if (!block_entry.isSingle()) {
                for (0..block_count) |i| {
                    packed_block_offsets[i] = @as(u32, @truncate(i)) * block_size;
                }
                packed_block_offsets[block_count] = block_size;
            } else {
                packed_block_offsets[0] = 0;
                packed_block_offsets[1] = block_size;
            }
        }
        const content = try allocator.alloc(u8, block_entry.file_size);
        var index: u32 = 0;
        var buffer: []u8 = undefined;

        for (0..block_count) |i| {
            var unpacked_size: u32 = block_entry.file_size - block_size * @as(u32, @truncate(i));
            if (block_entry.isSingle()) {
                unpacked_size = block_entry.file_size;
            } else if (i < block_count - 1) {
                unpacked_size = block_size;
            }
            buffer = try allocator.alloc(u8, packed_block_offsets[i + 1] - packed_block_offsets[i]);

            try read_seeker.seekTo(block_entry.file_position + packed_block_offsets[i]);
            _ = try read_seeker.read(std.mem.sliceAsBytes(buffer));
            if (block_entry.isEncrypted()) {
                return MPQError.InvalidMPQFile; // not supported yet
            }

            if (block_entry.isCompressedMulti()) {}
            index += unpacked_size;
        }
        return null;
    }

    pub fn deinit(self: *const MPQ) void {
        self.hash_table.deinit();
        self.block_table.deinit();
        self.block_entry_indices.deinit();
    }
};

/// MPQ Hash Table Entry structure
const HashEntry = extern struct {
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

    pub fn isEmpty(self: HashEntry) bool {
        return self.name_hash_a == EMPTY;
    }

    pub fn isDeleted(self: HashEntry) bool {
        return self.name_hash_a == DELETED;
    }

    pub fn isValid(self: HashEntry) bool {
        return !self.isEmpty() and !self.isDeleted();
    }

    pub fn isMatching(self: HashEntry, file_hash: hash.FileName) bool {
        return self.name_hash_a == file_hash.hash_b and self.name_hash_b == file_hash.hash_c;
    }

    pub fn format(
        self: HashEntry,
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

pub fn readHashTable(mpq: *MPQ, read_seeker: anytype, allocator: std.mem.Allocator) !void {
    const table_size = mpq.header.hash_table_entries * @sizeOf(HashEntry);

    // Allocate memory for the hash table
    const hash_entries = try allocator.alloc(HashEntry, mpq.header.hash_table_entries);
    errdefer allocator.free(hash_entries);

    // Seek to the hash table position
    try read_seeker.seekTo(mpq.header.hash_table_offset);

    // Read the encrypted hash table
    const bytes_read = try read_seeker.read(std.mem.sliceAsBytes(hash_entries));
    if (bytes_read < table_size) {
        return MPQError.ReadError;
    }

    // Decrypt the hash table
    // MPQ uses a specific key for the hash table: "(hash table)"
    hash.decrypt(std.mem.bytesAsSlice(u32, std.mem.sliceAsBytes(hash_entries)), hash.HASH_TABLE_DECRYPTION_KEY);
    mpq.hash_table = std.ArrayList(HashEntry).fromOwnedSlice(allocator, hash_entries);
}

pub fn hashEntry(mpq: *const MPQ, file_hash: hash.FileName) !struct { hash: HashEntry, pos: usize } {
    const nb_entries = mpq.header.hash_table_entries;
    for (file_hash.hash_a & (nb_entries - 1)..nb_entries) |i| {
        const hash_entry = mpq.hash_table.items[i];

        if (hash_entry.block_index == 0xffffffff) {
            break;
        }

        if (hash_entry.isMatching(file_hash)) {
            return .{ .hash = hash_entry, .pos = i };
        }
    }
    return MPQError.FileNotFound;
}

/// MPQ Block Table Entry structure
const BlockEntry = extern struct {
    // File position in the archive
    file_position: u32,
    // Compressed file size
    compressed_size: u32,
    // Uncompressed file size
    file_size: u32,
    // File flags
    flags: u32,

    // Block entry flag constants
    pub const Flags = enum(u32) {
        // Flag indicating that block is a file, and follows the file data format; otherwise, block is free space or unused.
        file = 0x80000000,

        // Flag indicating that file is stored as a single unit, rather than split into sectors.
        single = 0x01000000,

        //Flag indicating that the file has checksums for each sector (explained in the File Data section). Ignored if file is not compressed or imploded.
        extra = 0x04000000,

        // Flag indicating that the file is compressed.
        compressed = 0x0000FF00,

        // Flag indicating that the file is compressed with pkware algorithm.
        pkware = 0x00000100,

        // Flag indicating that the file is under multiple compression.
        compressed_multi = 0x00000200,

        // Flag indicating that the file is encrypted.
        encrypted = 0x00010000,
    };

    pub fn isCompressed(self: BlockEntry) bool {
        return (self.flags & @intFromEnum(BlockEntry.Flags.compressed)) != 0;
    }

    pub fn isCompressedMulti(self: BlockEntry) bool {
        return (self.flags & @intFromEnum(BlockEntry.Flags.compressed_multi)) != 0;
    }

    pub fn isEncrypted(self: BlockEntry) bool {
        return (self.flags & @intFromEnum(BlockEntry.Flags.encrypted)) != 0;
    }

    pub fn isSingle(self: BlockEntry) bool {
        return (self.flags & @intFromEnum(BlockEntry.Flags.single)) != 0;
    }

    pub fn hasExtra(self: BlockEntry) bool {
        return (self.flags & @intFromEnum(BlockEntry.Flags.extra)) != 0;
    }

    pub fn exists(self: BlockEntry) bool {
        return (self.flags & @intFromEnum(BlockEntry.Flags.file)) != 0;
    }

    pub fn compressionType(self: BlockEntry) u32 {
        return self.flags & @intFromEnum(BlockEntry.Flags.compressed);
    }

    pub fn format(
        self: BlockEntry,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        try writer.print("Block Entry:\n", .{});
        try writer.print("  File Position: 0x{X}\n", .{self.file_position});
        try writer.print("  Compressed Size: {} bytes\n", .{self.compressed_size});
        try writer.print("  File Size: {} bytes\n", .{self.file_size});
        try writer.print("  Flags: 0x{X}\n", .{self.flags});
        try writer.print("  - Exists: {}\n", .{self.exists()});
        try writer.print("  - Compressed: {}\n", .{self.isCompressed()});
        try writer.print("  - Encrypted: {}\n", .{self.isEncrypted()});
        if (self.isCompressed()) {
            try writer.print("  - Compression Type: 0x{X}\n", .{self.compressionType()});
        }
    }
};

pub fn readBlockTable(mpq: *MPQ, read_seeker: anytype, allocator: std.mem.Allocator) !void {
    const count_entries = mpq.header.block_table_entries;
    const table_size = count_entries * @sizeOf(BlockEntry);

    // Allocate memory for the block table
    const block_entries = try allocator.alloc(BlockEntry, count_entries);
    errdefer allocator.free(block_entries);

    // Seek to the block table position
    try read_seeker.seekTo(mpq.header.block_table_offset);

    // Read the encrypted block table
    const bytes_read = try read_seeker.read(std.mem.sliceAsBytes(block_entries));
    if (bytes_read < table_size) {
        return MPQError.ReadError;
    }

    // Decrypt the block table
    // MPQ uses a specific key for the block table: "(block table)"
    hash.decrypt(std.mem.bytesAsSlice(u32, std.mem.sliceAsBytes(block_entries)), hash.BLOCK_TABLE_DECRYPTION_KEY);

    mpq.block_table = std.ArrayList(BlockEntry).fromOwnedSlice(allocator, block_entries);
    mpq.block_entry_indices = std.ArrayList(usize).init(allocator);
    for (0..count_entries) |i| {
        if (block_entries[i].flags & @intFromEnum(BlockEntry.Flags.file) != 0) {
            try mpq.block_entry_indices.append(i);
            mpq.files_count += 1;
        }
    }
}
