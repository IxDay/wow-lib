const std = @import("std");
const utils = @import("utils.zig");

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

pub const Type = enum(u32) {
    TableOffset = 0 << 8, // 0
    NameA = 1 << 8, // 256
    NameB = 2 << 8, // 512
    FileKey = 3 << 8, // 768
};

// string computes the hash of a string.
pub fn string(str: []const u8, hash_type: Type) u32 {
    var seed1: u32 = 0x7fed7fed;
    var seed2: u32 = 0xeeeeeeee;

    for (str) |c| {
        const ch = utils.asciiToUpperTable[c];
        seed1 = crypt_table[@intFromEnum(hash_type) + ch] ^ (seed1 +% seed2);
        seed2 = ch +% seed1 +% seed2 +% (seed2 << 5) +% 3;
    }

    return seed1;
}

pub const HASH_TABLE_DECRYPTION_KEY = 0xc3af3770;
pub const BLOCK_TABLE_DECRYPTION_KEY = 0xec83b3a3;

test "hashString is working properly against known values" {
    var key: u32 = undefined;

    // https://github.com/icza/mpq/blob/d3cdc0b651b74fcb355a8c48b734a969a806e45e/mpq.go#L367-L368
    key = string("(hash table)", Type.FileKey);
    try std.testing.expect(key == HASH_TABLE_DECRYPTION_KEY);

    // https://github.com/icza/mpq/blob/d3cdc0b651b74fcb355a8c48b734a969a806e45e/mpq.go#L389-L390
    key = string("(block table)", Type.FileKey);
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

pub const FileName = struct {
    hash_a: u32,
    hash_b: u32,
    hash_c: u32,

    pub fn init(filename: []const u8) FileName {
        return FileName{
            .hash_a = string(filename, Type.TableOffset),
            .hash_b = string(filename, Type.NameA),
            .hash_c = string(filename, Type.NameB),
        };
    }
};

test "hash (filelist) special key is correct" {
    const hash = FileName.init("(listfile)");
    try std.testing.expect(hash.hash_a == 0x5F3DE859);
    try std.testing.expect(hash.hash_b == 0xFD657910);
    try std.testing.expect(hash.hash_c == 0x4E9B98A7);
}

pub fn main() !void {
    return;
}
