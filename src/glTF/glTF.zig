const std = @import("std");
const utils = @import("utils");
const json = @import("json.zig");

const Error = error{
    InvalidFile,
    UnsupportedFormat,
    ReadError,
};

pub const Header = extern struct {
    magic: [4]u8,
    version: u32,
    length: u32,

    json_header: ChunkHeader,

    pub fn init(reader: anytype) !Header {
        var header: Header = undefined;

        const header_read = try reader.read(std.mem.asBytes(&header));

        if (header_read < @sizeOf(Header)) {
            return Error.ReadError;
        }
        if (!header.isValid()) {
            return Error.InvalidFile;
        }

        return header;
    }

    pub fn parseJSON(self: Header, readseeker: anytype, allocator: std.mem.Allocator) !json.Gltf {
        try readseeker.seekTo(@sizeOf(Header));
        const json_string = try allocator.alloc(u8, self.json_header.length);
        defer allocator.free(json_string);
        const bytes_read = try readseeker.read(json_string);
        if (bytes_read < self.json_header.length) {
            return Error.ReadError;
        }
        errdefer std.debug.print("failed parsing {s}", .{json_string});
        return json.Gltf.parseFromString(allocator, json_string);
    }

    pub fn isValid(self: Header) bool {
        return std.mem.eql(u8, std.mem.asBytes(&self.magic), "glTF");
    }
};

test "header size is correct" {
    try std.testing.expect(@sizeOf(Header) == 20);
}

pub const ChunkHeader = extern struct {
    length: u32,
    kind: [4]u8,
};
