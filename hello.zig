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

/// MPQ Block Table Entry structure
const MPQBlockEntry = extern struct {
    // File position in the archive
    file_position: u32,
    // Compressed file size
    compressed_size: u32,
    // Uncompressed file size
    file_size: u32,
    // File flags
    flags: u32,

    // Block entry flag constants
    pub const FLAG_FILE_IMPLODE: u32 = 0x00000100;
    pub const FLAG_FILE_COMPRESSED: u32 = 0x00000200;
    pub const FLAG_FILE_ENCRYPTED: u32 = 0x00010000;
    pub const FLAG_FILE_EXISTS: u32 = 0x80000000;
    pub const FLAG_COMPRESSION_MASK: u32 = 0x0000FF00;

    pub fn isCompressed(self: MPQBlockEntry) bool {
        return (self.flags & FLAG_FILE_COMPRESSED) != 0;
    }

    pub fn isEncrypted(self: MPQBlockEntry) bool {
        return (self.flags & FLAG_FILE_ENCRYPTED) != 0;
    }

    pub fn exists(self: MPQBlockEntry) bool {
        return (self.flags & FLAG_FILE_EXISTS) != 0;
    }

    pub fn compressionType(self: MPQBlockEntry) u32 {
        return self.flags & FLAG_COMPRESSION_MASK;
    }

    pub fn format(
        self: MPQBlockEntry,
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

    // Decrypt the hash table
    // MPQ uses a specific key for the hash table: "(hash table)"
    const HASH_TABLE_KEY: u32 = 0xC3AF5B79; // Precomputed hash for "(hash table)"

    // Cast to u32 array for decryption
    const data_u32 = std.mem.bytesAsSlice(u32, std.mem.sliceAsBytes(hash_entries));
    decryptMPQTable(data_u32, HASH_TABLE_KEY);

    return hash_entries;
}

/// Read and decrypt the MPQ block table
pub fn readBlockTable(file: std.fs.File, header: MPQHeader, allocator: std.mem.Allocator) ![]MPQBlockEntry {
    const table_size = header.block_table_entries * @sizeOf(MPQBlockEntry);

    // Allocate memory for the block table
    const block_entries = try allocator.alloc(MPQBlockEntry, header.block_table_entries);
    errdefer allocator.free(block_entries);

    // Seek to the block table position
    try file.seekTo(header.block_table_offset);

    // Read the encrypted block table
    const bytes_read = try file.read(std.mem.sliceAsBytes(block_entries));
    if (bytes_read < table_size) {
        return MPQError.ReadError;
    }

    // Decrypt the block table
    // MPQ uses a specific key for the block table: "(block table)"
    const BLOCK_TABLE_KEY: u32 = 0xEC83B3A3; // Precomputed hash for "(block table)"

    // Cast to u32 array for decryption
    const data_u32 = std.mem.bytesAsSlice(u32, std.mem.sliceAsBytes(block_entries));
    decryptMPQTable(data_u32, BLOCK_TABLE_KEY);

    return block_entries;
}

/// Find a file in the hash table by name
pub fn findFile(hash_table: []const MPQHashEntry, filename: []const u8) ?u32 {
    // Calculate hash values for the filename
    const hashes = hashFilename(filename);

    // Compute the hash table index (using hash A modulo table size)
    var index = hashes.hash_a % @as(u32, @truncate(hash_table.len));
    const start_index = index;

    // Linear probing to find the right entry
    while (true) {
        const entry = hash_table[index];

        // Check if this is our file
        if (entry.isValid() and entry.name_hash_a == hashes.hash_a and entry.name_hash_b == hashes.hash_b) {
            return entry.block_index;
        }

        // If we hit an empty entry, the file doesn't exist
        if (entry.isEmpty()) {
            return null;
        }

        // Move to the next entry
        index = (index + 1) % @as(u32, @truncate(hash_table.len));

        // If we've checked the entire table, exit
        if (index == start_index) {
            return null;
        }
    }

    return null;
}

/// Generate decryption key for a file
fn generateFileKey(filename: []const u8, file_offset: u32, file_size: u32) u32 {
    var key = hashString(filename, 0x300);
    key = (key + file_offset) ^ file_size;
    return key;
}

/// Decrypt a block of data
fn decryptBlock(data: []u8, key: u32) void {
    // Convert to u32 slice for easier processing
    const data_u32 = std.mem.bytesAsSlice(u32, data[0 .. @divFloor(data.len, 4) * 4]);
    var seed = key;

    for (data_u32) |*value| {
        seed = (seed * 0x343FD) + 0x269EC3;
        value.* ^= seed;
    }
}

/// Decompress a sector
fn decompressSector(compressed: []const u8, decompressed: []u8, compression_type: u32) !usize {
    // This is a simplified implementation - in a real parser, you'd implement
    // various decompression algorithms based on the compression_type

    // For demonstration, we'll just copy the data (as if uncompressed)
    if (compression_type == 0) { // No compression
        std.mem.copy(u8, decompressed, compressed);
        return compressed.len;
    }

    // In a real implementation, you'd handle different compression types:
    // - PKWARE implode
    // - zlib/deflate
    // - bzip2
    // - etc.

    // For now, we'll just report an error
    return MPQError.DecompressionError;
}

/// Extract a file from the MPQ archive
pub fn extractFile(file: std.fs.File, header: MPQHeader, hash_table: []const MPQHashEntry, block_table: []const MPQBlockEntry, filename: []const u8, allocator: std.mem.Allocator) ![]u8 {
    // Find the file in the hash table
    const block_index = findFile(hash_table, filename) orelse {
        return MPQError.FileNotFound;
    };

    // Get the block entry
    if (block_index >= block_table.len) {
        return MPQError.InvalidFileEntry;
    }

    const block_entry = block_table[block_index];

    // Check if the file exists
    if (!block_entry.exists()) {
        return MPQError.FileNotFound;
    }

    // Allocate memory for the file
    const file_data = try allocator.alloc(u8, block_entry.file_size);
    errdefer allocator.free(file_data);

    // If the file isn't compressed or encrypted, just read it directly
    if (!block_entry.isCompressed() and !block_entry.isEncrypted()) {
        try file.seekTo(block_entry.file_position);
        const bytes_read = try file.read(file_data);
        if (bytes_read != block_entry.file_size) {
            return MPQError.ReadError;
        }
        return file_data;
    }

    // For compressed/encrypted files, we need to read the sector table first
    const sector_size = header.sectorSize();
    const sectors = @divFloor(block_entry.file_size + sector_size - 1, sector_size);
    const sector_table_size = (sectors + 1) * 4; // +1 for the end marker

    // Read the sector offset table
    const sector_offsets = try allocator.alloc(u32, sectors + 1);
    defer allocator.free(sector_offsets);

    try file.seekTo(block_entry.file_position);

    // Read and potentially decrypt the sector offset table
    {
        const sector_table_buf = try allocator.alloc(u8, sector_table_size);
        defer allocator.free(sector_table_buf);

        const bytes_read = try file.read(sector_table_buf);
        if (bytes_read != sector_table_size) {
            return MPQError.ReadError;
        }

        // If the file is encrypted, decrypt the sector table
        if (block_entry.isEncrypted()) {
            const key = generateFileKey(filename, block_entry.file_position, block_entry.file_size);
            decryptBlock(sector_table_buf, key);
        }

        // Convert to u32 array
        const offsets_slice = std.mem.bytesAsSlice(u32, sector_table_buf);
        std.mem.copy(u32, sector_offsets, offsets_slice);
    }

    // Process each sector
    var bytes_extracted: usize = 0;
    var buffer = try allocator.alloc(u8, sector_size);
    defer allocator.free(buffer);

    for (0..sectors) |i| {
        const sector_offset = block_entry.file_position + sector_offsets[i];
        const next_offset = block_entry.file_position + sector_offsets[i + 1];
        const sector_compressed_size = next_offset - sector_offset;

        // Read the compressed sector
        try file.seekTo(sector_offset);
        var compressed_sector = try allocator.alloc(u8, sector_compressed_size);
        defer allocator.free(compressed_sector);

        const bytes_read = try file.read(compressed_sector);
        if (bytes_read != sector_compressed_size) {
            return MPQError.ReadError;
        }

        // If encrypted, decrypt the sector
        if (block_entry.isEncrypted()) {
            const key = generateFileKey(filename, sector_offset, block_entry.file_size);
            decryptBlock(compressed_sector, key);
        }

        // Calculate actual decompressed size for this sector
        const decompressed_size = @min(sector_size, block_entry.file_size - bytes_extracted);

        // Decompress the sector
        if (block_entry.isCompressed()) {
            _ = try decompressSector(compressed_sector, buffer[0..decompressed_size], block_entry.compressionType());
        } else {
            std.mem.copy(u8, buffer[0..decompressed_size], compressed_sector[0..decompressed_size]);
        }

        // Copy to output buffer
        std.mem.copy(u8, file_data[bytes_extracted..], buffer[0..decompressed_size]);
        bytes_extracted += decompressed_size;

        // If we've extracted all the file data, we're done
        if (bytes_extracted >= block_entry.file_size) {
            break;
        }
    }

    return file_data;
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

/// Extract and parse the (listfile) to get a list of all files in the archive
pub fn extractListfile(file: std.fs.File, header: MPQHeader, hash_table: []const MPQHashEntry, block_table: []const MPQBlockEntry, allocator: std.mem.Allocator) ![][]u8 {
    // Try to extract the (listfile)
    const listfile_data = extractFile(file, header, hash_table, block_table, "(listfile)", allocator) catch |err| {
        std.debug.print("Failed to extract (listfile): {}\n", .{err});
        return err;
    };
    defer allocator.free(listfile_data);

    // Count the number of lines (files)
    var num_files: usize = 0;
    var last_was_newline = true;

    for (listfile_data) |c| {
        if (c == '\n') {
            last_was_newline = true;
        } else if (last_was_newline) {
            num_files += 1;
            last_was_newline = false;
        }
    }

    // Allocate array for filenames
    var filenames = try allocator.alloc([]u8, num_files);
    errdefer {
        for (filenames) |fname| {
            allocator.free(fname);
        }
        allocator.free(filenames);
    }

    // Parse the listfile content
    var file_index: usize = 0;
    var line_start: usize = 0;
    var i: usize = 0;

    while (i <= listfile_data.len) {
        const is_end = i == listfile_data.len;
        const is_newline = !is_end and listfile_data[i] == '\n';

        if (is_end or is_newline) {
            // Skip empty lines
            if (i > line_start) {
                // Extract line without trailing carriage return if present
                var line_end = i;
                if (line_end > line_start and listfile_data[line_end - 1] == '\r') {
                    line_end -= 1;
                }

                // Copy the filename
                const filename = try allocator.alloc(u8, line_end - line_start);
                std.mem.copy(u8, filename, listfile_data[line_start..line_end]);
                filenames[file_index] = filename;
                file_index += 1;
            }

            line_start = i + 1;
        }

        i += 1;
    }

    // Resize the array in case we had empty lines
    if (file_index < num_files) {
        filenames = allocator.realloc(filenames, file_index) catch filenames[0..file_index];
    }

    return filenames;
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
        std.debug.print("Usage: {s} <mpq_file_path> [extract_filename | list | extract-all]\n", .{std.os.argv[0]});
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
    std.debug.print("{}\n", .{header});

    // Read hash table
    const hash_table = readHashTable(file, header, allocator) catch |err| {
        std.debug.print("Failed to read hash table: {}\n", .{err});
        return err;
    };
    defer allocator.free(hash_table);

    // Read block table
    const block_table = readBlockTable(file, header, allocator) catch |err| {
        std.debug.print("Failed to read block table: {}\n", .{err});
        return err;
    };
    defer allocator.free(block_table);

    // Print hash table entries
    const stdout = std.io.getStdOut().writer();
    std.debug.print("\nHash Table Entries:\n", .{});
    for (hash_table, 0..) |entry, i| {
        if (entry.isValid()) {
            try stdout.print("Entry {d}: {}\n", .{ i, entry });
        }
    }

    // Print block table entries
    std.debug.print("\nBlock Table Entries:\n", .{});
    for (block_table, 0..) |entry, i| {
        if (entry.exists()) {
            try stdout.print("Entry {d}: {}\n", .{ i, entry });
        }
    }

    // Check command or filename for extraction
    const command = args.next();
    if (command) |cmd| {
        if (std.mem.eql(u8, cmd, "list")) {
            // Extract and display the list of files
            std.debug.print("\nExtracting listfile...\n", .{});
            const filenames = extractListfile(file, header, hash_table, block_table, allocator) catch |err| {
                std.debug.print("Failed to extract listfile: {}\n", .{err});
                return;
            };
            defer {
                for (filenames) |fname| {
                    allocator.free(fname);
                }
                allocator.free(filenames);
            }

            std.debug.print("\nFiles in archive ({} files):\n", .{filenames.len});
            for (filenames, 0..) |filename, i| {
                try stdout.print("{d}: {s}\n", .{ i + 1, filename });
            }
        } else if (std.mem.eql(u8, cmd, "extract-all")) {
            // Extract all files in the archive
            std.debug.print("\nExtracting all files...\n", .{});

            // First get the list of files
            const filenames = extractListfile(file, header, hash_table, block_table, allocator) catch |err| {
                std.debug.print("Failed to extract listfile: {}\n", .{err});
                return;
            };
            defer {
                for (filenames) |fname| {
                    allocator.free(fname);
                }
                allocator.free(filenames);
            }

            // Create output directory
            const output_dir = try std.fmt.allocPrint(allocator, "{s}_extracted", .{std.fs.path.basename(mpq_path)});
            defer allocator.free(output_dir);

            std.fs.cwd().makeDir(output_dir) catch |err| {
                if (err != error.PathAlreadyExists) {
                    std.debug.print("Failed to create output directory: {}\n", .{err});
                    return err;
                }
            };

            // Extract each file
            var success_count: usize = 0;
            for (filenames) |filename| {
                std.debug.print("Extracting: {s}\n", .{filename});

                const file_data = extractFile(file, header, hash_table, block_table, filename, allocator) catch |err| {
                    std.debug.print("  Failed: {}\n", .{err});
                    continue;
                };
                defer allocator.free(file_data);

                // Create full path with directories
                const full_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ output_dir, filename });
                defer allocator.free(full_path);

                // Create parent directories if needed
                if (std.fs.path.dirname(full_path)) |dir_path| {
                    var iter_path = dir_path;
                    while (iter_path.len > 0) {
                        std.fs.cwd().makeDir(iter_path) catch |err| {
                            if (err != error.PathAlreadyExists) {
                                // Just log and continue
                                std.debug.print("  Warning: couldn't create directory {s}: {}\n", .{ iter_path, err });
                            }
                        };
                        iter_path = std.fs.path.dirname(iter_path) orelse break;
                    }
                }

                // Write the file
                const output_file = std.fs.cwd().createFile(full_path, .{}) catch |err| {
                    std.debug.print("  Failed to create file: {}\n", .{err});
                    continue;
                };
                defer output_file.close();

                output_file.write(file_data) catch |err| {
                    std.debug.print("  Failed to write file: {}\n", .{err});
                    continue;
                };

                success_count += 1;
            }

            std.debug.print("\nExtraction complete. Successfully extracted {}/{} files to {s}\n", .{ success_count, filenames.len, output_dir });
        } else {
            // Extract a specific file
            std.debug.print("\nExtracting file: {s}\n", .{cmd});

            const file_data = extractFile(file, header, hash_table, block_table, cmd, allocator) catch |err| {
                std.debug.print("Failed to extract file: {}\n", .{err});
                return err;
            };
            defer allocator.free(file_data);

            // Write the file to disk
            const output_path = try std.fmt.allocPrint(allocator, "{s}.extracted", .{cmd});
            defer allocator.free(output_path);

            const output_file = try std.fs.cwd().createFile(output_path, .{});
            defer output_file.close();

            _ = try output_file.write(file_data);
            std.debug.print("File extracted to: {s} ({} bytes)\n", .{ output_path, file_data.len });
        }
    }

    return;
}
