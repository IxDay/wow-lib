const std = @import("std");

const asciiToUpperTable = [256]u8{
    // Control characters
    0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, '\t', '\n', 0x0B, 0x0C, '\r', 0x0E, 0x0F,
    0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18, 0x19, 0x1A, 0x1B, 0x1C, 0x1D, 0x1E, 0x1F,
    // Space, punctuation, digits (now slash is backslash)
    ' ',  '!',  '"',  '#',  '$',  '%',  '&',  '\'', '(',  ')',  '*',  '+',  ',',  '-',  '.',  '\\',
    // Digits, punctuation
    '0',  '1',  '2',  '3',  '4',  '5',  '6',  '7',  '8',  '9',  ':',  ';',  '<',  '=',  '>',  '?',
    // @, uppercase A-O
    '@',  'A',  'B',  'C',  'D',  'E',  'F',  'G',  'H',  'I',  'J',  'K',  'L',  'M',  'N',  'O',
    // Uppercase P-Z, brackets
    'P',  'Q',  'R',  'S',  'T',  'U',  'V',  'W',  'X',  'Y',  'Z',  '[',  '\\', ']',  '^',  '_',
    // Backtick, lowercase a-o (now uppercase)
    '`',  'A',  'B',  'C',  'D',  'E',  'F',  'G',  'H',  'I',  'J',  'K',  'L',  'M',  'N',  'O',
    // Lowercase p-z (now uppercase), braces, DEL
    'P',  'Q',  'R',  'S',  'T',  'U',  'V',  'W',  'X',  'Y',  'Z',  '{',  '|',  '}',  '~',  0x7F,
    // Extended ASCII
    0x80, 0x81, 0x82, 0x83, 0x84, 0x85, 0x86, 0x87, 0x88, 0x89, 0x8A, 0x8B, 0x8C, 0x8D, 0x8E, 0x8F,
    0x90, 0x91, 0x92, 0x93, 0x94, 0x95, 0x96, 0x97, 0x98, 0x99, 0x9A, 0x9B, 0x9C, 0x9D, 0x9E, 0x9F,
    0xA0, 0xA1, 0xA2, 0xA3, 0xA4, 0xA5, 0xA6, 0xA7, 0xA8, 0xA9, 0xAA, 0xAB, 0xAC, 0xAD, 0xAE, 0xAF,
    0xB0, 0xB1, 0xB2, 0xB3, 0xB4, 0xB5, 0xB6, 0xB7, 0xB8, 0xB9, 0xBA, 0xBB, 0xBC, 0xBD, 0xBE, 0xBF,
    0xC0, 0xC1, 0xC2, 0xC3, 0xC4, 0xC5, 0xC6, 0xC7, 0xC8, 0xC9, 0xCA, 0xCB, 0xCC, 0xCD, 0xCE, 0xCF,
    0xD0, 0xD1, 0xD2, 0xD3, 0xD4, 0xD5, 0xD6, 0xD7, 0xD8, 0xD9, 0xDA, 0xDB, 0xDC, 0xDD, 0xDE, 0xDF,
    0xE0, 0xE1, 0xE2, 0xE3, 0xE4, 0xE5, 0xE6, 0xE7, 0xE8, 0xE9, 0xEA, 0xEB, 0xEC, 0xED, 0xEE, 0xEF,
    0xF0, 0xF1, 0xF2, 0xF3, 0xF4, 0xF5, 0xF6, 0xF7, 0xF8, 0xF9, 0xFA, 0xFB, 0xFC, 0xFD, 0xFE, 0xFF,
};

test "transform lowercase to uppercase and slash to backslash" {
    try std.testing.expect(asciiToUpperTable['/'] == '\\');
    for ('a'..'z') |c| {
        try std.testing.expect(asciiToUpperTable[c] == std.ascii.toUpper(@intCast(c)));
    }
}

const crypt_table: [0x500]u32 = blk: {
    @setEvalBranchQuota(10000);
    var table: [0x500]u32 = undefined;
    var seed: u32 = 0x00100001;

    for (0..0x100) |index1| {
        var index2 = index1;
        for (0..5) |_| {
            seed = (seed * 125 + 3) % 0x2AAAAB;
            const temp: u32 = (seed & 0xFFFF) << 0x10;
            seed = (seed * 125 + 3) % 0x2AAAAB;

            table[index2] = temp | (seed & 0xffff);
            index2 += 0x100;
        }
    }
    break :blk table;
};

const HashType = enum(u32) {
    TableOffset = 0 << 8, // 0
    NameA = 1 << 8, // 256
    NameB = 2 << 8, // 512
    FileKey = 3 << 8, // 768
};

// hashString computes the hash of a string.
pub fn hashString(str: []const u8, hash_type: HashType) u32 {
    var seed1: u32 = 0x7fed7fed;
    var seed2: u32 = 0xeeeeeeee;

    for (str) |c| {
        const ch = asciiToUpperTable[c];
        seed1 = crypt_table[@intFromEnum(hash_type) + ch] ^ (seed1 +% seed2);
        seed2 = ch +% seed1 +% seed2 +% (seed2 << 5) +% 3;
    }

    return seed1;
}

const HASH_TABLE_DECRYPTION_KEY = 0xc3af3770;
const BLOCK_TABLE_DECRYPTION_KEY = 0xec83b3a3;

test "hashString is working properly against known values" {
    var key: u32 = undefined;

    // https://github.com/icza/mpq/blob/d3cdc0b651b74fcb355a8c48b734a969a806e45e/mpq.go#L367-L368
    key = hashString("(hash table)", HashType.FileKey);
    try std.testing.expect(key == HASH_TABLE_DECRYPTION_KEY);

    // https://github.com/icza/mpq/blob/d3cdc0b651b74fcb355a8c48b734a969a806e45e/mpq.go#L389-L390
    key = hashString("(block table)", HashType.FileKey);
    try std.testing.expect(key == BLOCK_TABLE_DECRYPTION_KEY);
}

pub fn decrypt(data: []u32, key: u32) void {
    var seed1 = key;
    var seed2: u32 = 0xeeeeeeee;

    for (data, 0..) |_, i| {
        seed2 +%= crypt_table[0x400 + (seed1 & 0xff)];
        // littleEndian byte order:
        data[i] ^= seed1 +% seed2;
        seed1 = ((~seed1 << 0x15) +% 0x11111111) | (seed1 >> 0x0B);
        seed2 = data[i] +% seed2 +% (seed2 << 5) +% 3;
    }
}

test "decrypt function" {
    var data = "aaaa".*;

    data = "abcd".*;
    decrypt(@constCast(@alignCast(std.mem.bytesAsSlice(u32, &data))), 1);
    try std.testing.expectEqual(data, [_]u8{ 165, 132, 230, 39 });

    data = "abcd".*;
    decrypt(@constCast(@alignCast(std.mem.bytesAsSlice(u32, &data))), 2);
    try std.testing.expectEqual(data, [_]u8{ 106, 224, 148, 84 });
}

// FileNameHash returns different hashes of the file name,
// exactly the ones that are needed by MPQ.FileByHash().
pub fn fileNameHash(name: []const u8) struct { hash_a: u32, hash_b: u32, hash_c: u32 } {
    return .{
        .hash_a = hashString(name, HashType.TableOffset),
        .hash_b = hashString(name, HashType.NameA),
        .hash_c = hashString(name, HashType.NameB),
    };
}

test "hash (filelist) special key is correct" {
    const hash = fileNameHash("(listfile)");
    try std.testing.expect(hash.hash_a == 0x5F3DE859);
    try std.testing.expect(hash.hash_b == 0xFD657910);
    try std.testing.expect(hash.hash_c == 0x4E9B98A7);
}

const MPQ = struct {
    pub fn fileByHash() void {}
};

pub fn main() !void {
    return;
}
