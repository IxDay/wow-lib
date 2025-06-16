const std = @import("std");
const builtin = @import("builtin");

const c = @cImport({
    @cInclude("zlib.h");
    @cInclude("bzlib.h");
});

const DecompressError = error{
    InvalidInput,
    OutOfMemory,
    BufferTooSmall,
    DataError,
    IOError,
    Unknown,
};

pub fn decompressMulti(dst: []u8, src: []const u8) !void {
    if (src.len == dst.len) return @memcpy(dst, src);
    switch (src[0]) {
        0x02 => return decompressZlib(dst, src[1..]),
        0x03 => return decompressBzip2(dst, src[1..]),
        else => return DecompressError.InvalidInput,
    }
}

fn decompressBzip2(dst: []u8, src: []const u8) !void {
    var dst_len: c.uint = @intCast(dst.len);

    const result = c.BZ2_bzBuffToBuffDecompress(
        @ptrCast(dst.ptr),
        &dst_len,
        @constCast(src.ptr),
        @intCast(src.len),
        0,
        0,
    );

    switch (result) {
        c.BZ_OK => return,
        c.BZ_OUTBUFF_FULL => return DecompressError.BufferTooSmall,
        c.BZ_IO_ERROR => return DecompressError.IOError,
        else => return DecompressError.Unknown,
    }
}

fn decompressZlib(dst: []u8, src: []const u8) !void {
    // Convert Zig types to C types
    var dst_len: c.uLongf = @intCast(dst.len);
    const src_len: c.uLong = @intCast(src.len);

    // Call the C uncompress function
    const result = c.uncompress(@ptrCast(dst.ptr), // dest: [*c]Bytef
        &dst_len, // destLen: [*c]uLongf (pointer to length)
        @ptrCast(src.ptr), // source: [*c]const Bytef
        src_len // sourceLen: uLong
    );

    // Handle the result
    switch (result) {
        c.Z_OK => {
            // Success - check if we used the expected amount of output space
            if (dst_len != dst.len) {
                // Optionally handle case where decompressed size differs
                // For now, we'll allow it as long as it fits
            }
            return;
        },
        c.Z_MEM_ERROR => return DecompressError.OutOfMemory,
        c.Z_BUF_ERROR => return DecompressError.BufferTooSmall,
        c.Z_DATA_ERROR => return DecompressError.DataError,
        else => return DecompressError.Unknown,
    }
}

test "decompress" {
    // print(''.join(r'\x%02x'%i for i in zlib.compress(b"Hello World!")))
    const src_zlib = "\x02" ++ // zlib flag
        "\x78\x9c\xf2\x48\xcd\xc9\xc9\x57\x08\xcf\x2f" ++
        "\xca\x49\x51\x04\x04\x00\x00\xff\xff\x1c\x49\x04\x3e";
    var dst_zlib: [12]u8 = undefined;

    try decompressMulti(&dst_zlib, src_zlib);
    try std.testing.expectEqualStrings("Hello World!", &dst_zlib);

    // print(''.join(r'\x%02x'%i for i in bz2.compress(b"Hello World!")))
    const src_bzip2 = "\x03" ++ // bzip2 flag
        "\x42\x5a\x68\x39\x31\x41\x59\x26\x53\x59\x6b\x1a\x7c\xae\x00\x00\x01" ++
        "\x17\x80\x60\x00\x00\x40\x00\x80\x06\x04\x90\x00\x20\x00\x22\x06\x9a" ++
        "\x3d\x42\x0c\x98\x8e\x69\x73\x05\x01\xe2\xee\x48\xa7\x0a\x12\x0d\x63" ++
        "\x4f\x95\xc0";
    var dst_bzip2: [12]u8 = undefined;
    try decompressMulti(&dst_bzip2, src_bzip2);
    try std.testing.expectEqualStrings("Hello World!", &dst_bzip2);
}

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
pub const BufferReader = struct {
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

fn debugger(comptime T: type) type {
    return struct {
        value: T,
        indent: u8,

        const Self = @This();
        const ValueType = T;

        pub fn init(value: anytype, indent: u8) Self {
            return .{
                .value = value,
                .indent = indent,
            };
        }

        pub fn print(self: Self) void {
            switch (@typeInfo(ValueType)) {
                .@"struct" => self.printStruct(),
                .int => std.debug.print("{d}\n", .{self.value}),
                .pointer => |ptr| self.printPointer(ptr),
                .array => self.printArray(),
                .@"union" => |uni| std.debug.print("union {}", .{uni}),
                .@"enum" => |enm| std.debug.print("enum {}", .{enm}),
                .optional => {
                    if (self.value) |v| {
                        debug(v, self.indent);
                    } else {
                        std.debug.print("null\n", .{});
                    }
                },
                // consciously covered: .Type, .Float, .Void
                else => std.debug.print("{any}\n", .{self.value}),
            }
        }
        fn printArray(self: Self) void {
            if (comptime (@typeInfo(ValueType) != .array)) {
                @compileError("printStruct only available for struct");
            }
            if (std.meta.Child(ValueType) == u8) {
                std.debug.print("{s}\n", .{self.value});
            } else {
                self.printSlice();
            }
        }

        fn printStruct(self: Self) void {
            if (comptime (@typeInfo(ValueType) != .@"struct")) {
                @compileError("printStruct only available for struct");
            }
            std.debug.print("{}{{\n", .{ValueType});
            inline for (std.meta.fields(ValueType)) |field| {
                printIndent(self.indent);
                std.debug.print("{s}: ", .{field.name});
                debug(@field(self.value, field.name), self.indent + 2);
            }
            printIndent(self.indent - 2);
            std.debug.print("}}\n", .{});
        }

        fn printPointer(self: Self, ptr: std.builtin.Type.Pointer) void {
            // for (0..indent) |_| {
            //     std.debug.print(" ", .{});
            // }
            switch (ptr.size) {
                .one => {
                    std.debug.print("one: {}", .{ptr});
                    // [Option-less] Do not show opaque or function pointers
                    // if (ptr.child == anyopaque or
                    //     @typeInfo(ptr.child) == .@"fn")
                    //     return;

                    // [Option] Follow the pointer
                    // if (opt.ptr_deref) {
                    //     if (s.pointers.find(val)) {
                    //         try s.appendValSpecial(.recursion, c);
                    //     } else if (s.pointers.push(val)) {
                    //         try s.traverse(val.*, val_info, c);
                    //         s.pointers.pop();
                    //     } else { // pointers stack is full
                    //         try s.appendValSpecial(.skip, c);
                    //     }
                    // } else {
                    //     try s.appendValFmt("{*}", val, c);
                    // }
                },
                .c => {
                    // Can't follow C pointers
                    // try s.appendValSpecial(.unknown, c);
                },
                .many => {
                    std.debug.print("many: {}", .{ptr});
                    // [Option] Interpret [*:0]u8 as string
                    // if (opt.ptr_many_u8z_is_str and
                    //     ptr.child == u8 and meta.sentinel(val_T) == 0)
                    // {
                    //     const len = std.mem.indexOfSentinel(u8, 0, val);
                    //     try s.appendValString(val[0..len :0], c);
                    //     return;
                    // }

                    // [Option] Interpret [*:sentinel]T as array
                    // if (opt.ptr_many_with_sentinel_is_array) {
                    //     if (meta.sentinel(val_T)) |sentinel| {
                    //         var i: usize = 0;
                    //         while (val[i] != sentinel) : (i += 1) {
                    //             const len = i + 1;
                    //             // [Option] Stop if the length of a slice exceeds
                    //             if (opt.array_max_len > 0 and len > opt.array_max_len)
                    //                 break;

                    //             c.index = i;
                    //             // s.last_child = if (len == val.len) true else false;
                    //             try s.traverse(val[i], val_info, c);
                    //         }
                    //         return;
                    //     }
                    // }

                    // Can't follow the pointer
                    // try s.appendValSpecial(.unknown, c);
                },
                .slice => self.printSlice(),
            }
        }

        fn printSlice(self: Self) void {
            // [Option] Interpret []u8 as string
            if (std.meta.Child(ValueType) == u8 and std.meta.sentinel(ValueType) == null) {
                std.debug.print("{s}\n", .{self.value});
                return;
            }

            // // [Option] Interpret [:0]u8 as string
            // if (opt.slice_u8z_is_str and
            //     meta.Child(val_T) == u8 and meta.sentinel(val_T) == 0)
            // {
            //     try s.appendValString(val, c);
            //     return;
            // }

            // Slice is empty
            if (self.value.len == 0) {
                std.debug.print("[]\n", .{});
                return;
            }

            // Slice has multiple elements:
            std.debug.print("[\n", .{});

            // Comptime slice
            if (std.meta.fields(@TypeOf(.{self.value}))[0].is_comptime) {
                inline for (self.value) |item| {
                    // const len = i + 1;
                    // [Option] Stop if the length of a slice exceeds
                    // if (opt.array_max_len > 0 and len > opt.array_max_len)
                    //     break;

                    // c.index = i;
                    // s.last_child = if (len == val.len) true else false;

                    // try s.traverse(item, val_info, c);
                    printIndent(self.indent);
                    debug(item, self.indent + 2);
                }
            } else {
                for (self.value) |item| {
                    // const len = i + 1;
                    // // [Option] Stop if the length of a slice exceeds
                    // if (opt.array_max_len > 0 and len > opt.array_max_len)
                    //     break;

                    // c.index = i;
                    // // s.last_child = if (len == val.len) true else false;
                    // try s.traverse(item, val_info, c);
                    printIndent(self.indent);
                    debug(item, self.indent + 2);
                }
            }
            printIndent(self.indent - 2);
            std.debug.print("]\n", .{});
        }

        fn printIndent(indent: u8) void {
            for (0..indent) |_| std.debug.print(" ", .{});
        }
    };
}

pub fn debug(value: anytype, indent: u8) void {
    if (builtin.mode != .Debug) return;
    debugger(@TypeOf(value)).init(value, indent).print();
}

pub fn debugPrefix(value: anytype, prefix: []const u8) void {
    if (builtin.mode != .Debug) return;
    std.debug.print("{s} - ", .{prefix});
    debug(value, 2);
}

test "debugger" {
    const bar = struct {
        int: u8,
        str: []const u8,
    };
    const b = bar{ .int = 2, .str = "bar" };
    debug(b, 2);
}
