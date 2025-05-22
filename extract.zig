const std = @import("std");
const Allocator = std.mem.Allocator;

// MPQ constants
const MPQ_HEADER_SIGNATURE = 0x1A51504D; // 'MPQ\x1A'
const MPQ_USER_DATA_SIGNATURE = 0x1B51504D; // 'MPQ\x1B'
const HASH_TABLE_ENTRY_SIZE = 16;
const BLOCK_TABLE_ENTRY_SIZE = 16;
const LISTFILE_HASH_A = 0xFD5075AB;
const LISTFILE_HASH_B = 0xFF75F59B;

// Flags for files
const MPQ_FILE_IMPLODE = 0x00000100;
const MPQ_FILE_COMPRESS = 0x00000200;
const MPQ_FILE_ENCRYPTED = 0x00010000;
const MPQ_FILE_EXISTS = 0x80000000;

// Hash table entry structure
const HashEntry = struct {
    hash_a: u32,
    hash_b: u32,
    locale: u16,
    platform: u16,
    block_index: u32,
};

// Block table entry structure
const BlockEntry = struct {
    offset: u32,
    compressed_size: u32,
    file_size: u32,
    flags: u32,
};

// MPQ Header structure
const MpqHeader = struct {
    signature: u32,
    header_size: u32,
    archive_size: u32,
    format_version: u16,
    sector_size_shift: u16,
    hash_table_offset: u32,
    block_table_offset: u32,
    hash_table_entries: u32,
    block_table_entries: u32,
};

// Error set for MPQ operations
const MpqError = error{
    InvalidSignature,
    ListfileNotFound,
    ReadError,
    DecompressionError,
    DecryptionError,
    OutOfMemory,
};

// Hash functions used in MPQ
fn hashString(str: []const u8, hash_type: u32) u32 {
    var seed1: u32 = 0x7FED7FED;
    var seed2: u32 = 0xEEEEEEEE;

    for (str) |c| {
        const ch = std.ascii.toUpper(c);
        seed1 = cryptTable[(hash_type << 8) + ch] ^ (seed1 + seed2);
        seed2 = ch + seed1 + seed2 + (seed2 << 5) + 3;
    }

    return seed1;
}

// Initialize the encryption/decryption table
var cryptTable: [0x500]u32 = undefined;

fn initCryptTable() void {
    var seed: u32 = 0x00100001;

    for (0..0x100) |i| {
        var index = i;
        for (0..5) |_| {
            seed = (seed * 125 + 3) % 0x2AAAAB;
            const temp1 = (seed & 0xFFFF) << 0x10;

            seed = (seed * 125 + 3) % 0x2AAAAB;
            const temp2 = (seed & 0xFFFF);

            cryptTable[index] = temp1 | temp2;
            index += 0x100;
        }
    }
}

// Decrypt function for MPQ data
fn decrypt(data: []u8, key: u32) !void {
    if (data.len % 4 != 0) return error.DecryptionError;

    var foo = key;
    var seed2: u32 = 0xEEEEEEEE;

    var i: usize = 0;
    while (i < data.len) : (i += 4) {
        seed2 += cryptTable[0x400 + (foo & 0xFF)];

        var value = std.mem.readInt(u32, data[i..][0..4], .little);
        value ^= foo + seed2;

        foo = ((~foo << 0x15) + 0x11111111) | (foo >> 0x0B);
        seed2 = value + seed2 + (seed2 << 5) + 3;

        std.mem.writeInt(u32, data[i..][0..4], value, .little);
    }
}

// Function to find the listfile in the MPQ archive
fn extractListfile(allocator: Allocator, file_path: []const u8) ![]u8 {
    initCryptTable();

    var file = try std.fs.cwd().openFile(file_path, .{});
    defer file.close();

    // Read MPQ header
    var header_buffer: [32]u8 = undefined;
    const header_bytes_read = try file.read(&header_buffer);
    if (header_bytes_read < @sizeOf(MpqHeader)) return MpqError.ReadError;

    // Parse MPQ header
    const signature = std.mem.readInt(u32, header_buffer[0..4], .little);
    if (signature != MPQ_HEADER_SIGNATURE) {
        // Check if there's a user data block
        if (signature == MPQ_USER_DATA_SIGNATURE) {
            // User data block exists, skip to the actual MPQ header
            const user_data_size = std.mem.readInt(u32, header_buffer[4..8], .little);
            try file.seekTo(user_data_size);
            const actual_header_bytes_read = try file.read(&header_buffer);
            if (actual_header_bytes_read < @sizeOf(MpqHeader)) return MpqError.ReadError;

            const actual_signature = std.mem.readInt(u32, header_buffer[0..4], .little);
            if (actual_signature != MPQ_HEADER_SIGNATURE) return MpqError.InvalidSignature;
        } else {
            return MpqError.InvalidSignature;
        }
    }

    const header = MpqHeader{
        .signature = signature,
        .header_size = std.mem.readInt(u32, header_buffer[4..8], .little),
        .archive_size = std.mem.readInt(u32, header_buffer[8..12], .little),
        .format_version = std.mem.readInt(u16, header_buffer[12..14], .little),
        .sector_size_shift = std.mem.readInt(u16, header_buffer[14..16], .little),
        .hash_table_offset = std.mem.readInt(u32, header_buffer[16..20], .little),
        .block_table_offset = std.mem.readInt(u32, header_buffer[20..24], .little),
        .hash_table_entries = std.mem.readInt(u32, header_buffer[24..28], .little),
        .block_table_entries = std.mem.readInt(u32, header_buffer[28..32], .little),
    };

    // Read hash table
    try file.seekTo(header.hash_table_offset);
    const hash_table_size = header.hash_table_entries * HASH_TABLE_ENTRY_SIZE;
    var hash_table_data = try allocator.alloc(u8, hash_table_size);
    defer allocator.free(hash_table_data);

    if ((try file.read(hash_table_data)) != hash_table_size) return MpqError.ReadError;

    // Decrypt hash table
    try decrypt(hash_table_data, std.math.rotl(u32, header.hash_table_entries, 0x10) + 0xC3AF5B99);

    // Find the listfile entry in the hash table
    var listfile_block_index: ?u32 = null;
    var i: usize = 0;
    while (i < hash_table_size) : (i += HASH_TABLE_ENTRY_SIZE) {
        const hash_entry = HashEntry{
            .hash_a = std.mem.readInt(u32, hash_table_data[i..][0..4], .little),
            .hash_b = std.mem.readInt(u32, hash_table_data[i + 4 ..][0..4], .little),
            .locale = std.mem.readInt(u16, hash_table_data[i + 8 ..][0..2], .little),
            .platform = std.mem.readInt(u16, hash_table_data[i + 10 ..][0..2], .little),
            .block_index = std.mem.readInt(u32, hash_table_data[i + 12 ..][0..4], .little),
        };

        if (hash_entry.hash_a == LISTFILE_HASH_A and hash_entry.hash_b == LISTFILE_HASH_B and hash_entry.block_index != 0xFFFFFFFF) {
            listfile_block_index = hash_entry.block_index;
            break;
        }
    }

    if (listfile_block_index == null) return MpqError.ListfileNotFound;

    // Read block table
    try file.seekTo(header.block_table_offset);
    const block_table_size = header.block_table_entries * BLOCK_TABLE_ENTRY_SIZE;
    var block_table_data = try allocator.alloc(u8, block_table_size);
    defer allocator.free(block_table_data);

    if ((try file.read(block_table_data)) != block_table_size) return MpqError.ReadError;

    // Decrypt block table
    try decrypt(block_table_data, std.math.rotl(u32, header.block_table_entries, 0x10) + 0xC3AF5B99);

    // Get the listfile block entry
    const block_entry_pos = listfile_block_index.? * BLOCK_TABLE_ENTRY_SIZE;
    const block_entry = BlockEntry{
        .offset = std.mem.readInt(u32, block_table_data[block_entry_pos..][0..4], .little),
        .compressed_size = std.mem.readInt(u32, block_table_data[block_entry_pos + 4 ..][0..4], .little),
        .file_size = std.mem.readInt(u32, block_table_data[block_entry_pos + 8 ..][0..4], .little),
        .flags = std.mem.readInt(u32, block_table_data[block_entry_pos + 12 ..][0..4], .little),
    };

    // Check if the file exists
    if ((block_entry.flags & MPQ_FILE_EXISTS) == 0) return MpqError.ListfileNotFound;

    // Read the listfile data
    try file.seekTo(block_entry.offset);
    const compressed_data = try allocator.alloc(u8, block_entry.compressed_size);
    defer allocator.free(compressed_data);

    if ((try file.read(compressed_data)) != block_entry.compressed_size) return MpqError.ReadError;

    // Check if the file is encrypted
    if ((block_entry.flags & MPQ_FILE_ENCRYPTED) != 0) {
        // Calculate encryption key for "(listfile)"
        const listfile_name = "(listfile)";
        const decrypt_key = hashString(listfile_name, 0x300);
        try decrypt(compressed_data, decrypt_key);
    }

    // Handle decompression if needed
    var listfile_data: []u8 = undefined;
    if (block_entry.compressed_size < block_entry.file_size) {
        // File is compressed
        if (((block_entry.flags & MPQ_FILE_COMPRESS) != 0) or ((block_entry.flags & MPQ_FILE_IMPLODE) != 0)) {
            // Simple decompression approach (for demonstration)
            // In a real implementation, you would need proper decompression algorithms
            // This implementation just copies the data directly
            listfile_data = try allocator.alloc(u8, block_entry.file_size);
            @memcpy(listfile_data, compressed_data);
            return listfile_data;
        }
    }

    // If not compressed or encrypted, just return the data
    listfile_data = try allocator.alloc(u8, block_entry.compressed_size);
    @memcpy(listfile_data, compressed_data);
    return listfile_data;
}

pub fn main() !void {
    var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = general_purpose_allocator.deinit();
    const allocator = general_purpose_allocator.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    // Skip the executable name
    _ = args.next();

    // Get the MPQ file path from command line argument
    const file_path = args.next() orelse {
        // std.debug.print("Usage: {s} <mpq_file_path>\n", .{std.process.args().next().?});
        std.process.exit(1);
    };

    // Extract the listfile
    std.debug.print("Extracting listfile from: {s}\n", .{file_path});

    const listfile_data = extractListfile(allocator, file_path) catch |err| {
        switch (err) {
            MpqError.InvalidSignature => std.debug.print("Error: Not a valid MPQ file\n", .{}),
            MpqError.ListfileNotFound => std.debug.print("Error: Listfile not found in the archive\n", .{}),
            MpqError.ReadError => std.debug.print("Error: Failed to read from the MPQ file\n", .{}),
            MpqError.DecompressionError => std.debug.print("Error: Failed to decompress listfile data\n", .{}),
            MpqError.DecryptionError => std.debug.print("Error: Failed to decrypt listfile data\n", .{}),
            MpqError.OutOfMemory => std.debug.print("Error: Out of memory\n", .{}),
            else => std.debug.print("Error: Unknown error occurred\n", .{}),
        }
        std.process.exit(1);
    };
    defer allocator.free(listfile_data);

    // Print the listfile content
    std.debug.print("\nListfile contents:\n{s}\n", .{listfile_data});
}
