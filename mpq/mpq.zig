const header = @import("./header");
const utils = @import("./utils");
const std = @import("std");

const MPQ = struct {
    header: header.MPQHeader,
    hashTable: std.ArrayList(MPQHashEntry),

    pub fn init(read_seeker: anytype, allocator: std.mem.Allocator) !MPQ {
        const header = try MPQHeader.init(read_seeker);
        return MPQ{
            .header = header,
            .hashTable = try readHashTable(
                read_seeker,
                &header,
                allocator,
            ),
        };
    }
    pub fn fileByName(self: *const MPQ, name: []const u8) bool {
        return fileByHash(self, extract.FileNameHash.init(name));
    }

    pub fn deinit(self: *const MPQ) void {
        self.hashTable.deinit();
    }
};

pub fn fileByHash(mpq: *const MPQ, fileHash: utils.FileNameHash) bool {
    const nb_entries = mpq.header.hash_table_entries;
    for (fileHash.hash_a & (nb_entries - 1)..nb_entries) |i| {
        const hash_entry = mpq.hashTable[i];

        if (hash_entry.block_index == 0xffffffff) {
            break;
        }

        if (hash_entry.isMatching(fileHash)) {
            return true;
        }
    }
    return false;
}
