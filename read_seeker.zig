const std = @import("std");
const Allocator = std.mem.Allocator;

// Error types similar to Go's io package
const ReadSeekerError = error{
    EOF,
    UnexpectedEOF,
    InvalidSeekWhence,
    SeekFailed,
    ReadFailed,
} || Allocator.Error;

// Seek whence constants (similar to Go's io.SeekStart, io.SeekCurrent, io.SeekEnd)
const SeekWhence = enum(i32) {
    start = 0,
    current = 1,
    end = 2,
};

// ReadSeeker interface vtable
const ReadSeekerVTable = struct {
    read_fn: *const fn (ptr: *anyopaque, buf: []u8) ReadSeekerError!usize,
    seek_fn: *const fn (ptr: *anyopaque, offset: i64, whence: SeekWhence) ReadSeekerError!i64,
};

// ReadSeeker interface
const ReadSeeker = struct {
    ptr: *anyopaque,
    vtable: *const ReadSeekerVTable,

    pub fn read(self: ReadSeeker, buf: []u8) ReadSeekerError!usize {
        return self.vtable.read_fn(self.ptr, buf);
    }

    pub fn seek(self: ReadSeeker, offset: i64, whence: SeekWhence) ReadSeekerError!i64 {
        return self.vtable.seek_fn(self.ptr, offset, whence);
    }

    // Helper methods similar to Go's io utilities
    pub fn readAll(self: ReadSeeker, allocator: Allocator) ReadSeekerError![]u8 {
        var result = std.ArrayList(u8).init(allocator);
        defer result.deinit();

        var buf: [4096]u8 = undefined;
        while (true) {
            const n = self.read(buf[0..]) catch |err| switch (err) {
                ReadSeekerError.EOF => break,
                else => return err,
            };
            if (n == 0) break;
            try result.appendSlice(buf[0..n]);
        }

        return result.toOwnedSlice();
    }

    pub fn readAtLeast(self: ReadSeeker, buf: []u8, min: usize) ReadSeekerError!usize {
        if (min > buf.len) return ReadSeekerError.InvalidSeekWhence;

        var total: usize = 0;
        while (total < min) {
            const n = try self.read(buf[total..]);
            if (n == 0) return ReadSeekerError.UnexpectedEOF;
            total += n;
        }
        return total;
    }
};

// Example implementation: BytesReadSeeker (similar to Go's bytes.Reader)
const BytesReadSeeker = struct {
    data: []const u8,
    pos: usize,

    const vtable = ReadSeekerVTable{
        .read_fn = read,
        .seek_fn = seek,
    };

    pub fn init(data: []const u8) BytesReadSeeker {
        return BytesReadSeeker{
            .data = data,
            .pos = 0,
        };
    }

    pub fn asReadSeeker(self: *BytesReadSeeker) ReadSeeker {
        return ReadSeeker{
            .ptr = self,
            .vtable = &vtable,
        };
    }

    fn read(ptr: *anyopaque, buf: []u8) ReadSeekerError!usize {
        const self: *BytesReadSeeker = @ptrCast(@alignCast(ptr));

        if (self.pos >= self.data.len) {
            return ReadSeekerError.EOF;
        }

        const available = self.data.len - self.pos;
        const to_read = @min(buf.len, available);

        @memcpy(buf[0..to_read], self.data[self.pos .. self.pos + to_read]);
        self.pos += to_read;

        return to_read;
    }

    fn seek(ptr: *anyopaque, offset: i64, whence: SeekWhence) ReadSeekerError!i64 {
        const self: *BytesReadSeeker = @ptrCast(@alignCast(ptr));

        const new_pos: i64 = switch (whence) {
            .start => offset,
            .current => @as(i64, @intCast(self.pos)) + offset,
            .end => @as(i64, @intCast(self.data.len)) + offset,
        };

        if (new_pos < 0) {
            return ReadSeekerError.SeekFailed;
        }

        self.pos = @intCast(new_pos);
        return new_pos;
    }

    pub fn size(self: *const BytesReadSeeker) usize {
        return self.data.len;
    }
};

// Example implementation: FileReadSeeker (wrapper around std.fs.File)
const FileReadSeeker = struct {
    file: std.fs.File,

    const vtable = ReadSeekerVTable{
        .read_fn = read,
        .seek_fn = seek,
    };

    pub fn init(file: std.fs.File) FileReadSeeker {
        return FileReadSeeker{ .file = file };
    }

    pub fn asReadSeeker(self: *FileReadSeeker) ReadSeeker {
        return ReadSeeker{
            .ptr = self,
            .vtable = &vtable,
        };
    }

    fn read(ptr: *anyopaque, buf: []u8) ReadSeekerError!usize {
        const self: *FileReadSeeker = @ptrCast(@alignCast(ptr));

        const n = self.file.read(buf) catch |err| switch (err) {
            error.EndOfStream => return ReadSeekerError.EOF,
            else => return ReadSeekerError.ReadFailed,
        };

        if (n == 0) return ReadSeekerError.EOF;
        return n;
    }

    fn seek(ptr: *anyopaque, offset: i64, whence: SeekWhence) ReadSeekerError!i64 {
        const self: *FileReadSeeker = @ptrCast(@alignCast(ptr));

        const seek_from = switch (whence) {
            .start => std.fs.File.SeekableStream.SeekFrom.start,
            .current => std.fs.File.SeekableStream.SeekFrom.current,
            .end => std.fs.File.SeekableStream.SeekFrom.end,
        };

        const new_pos = self.file.seekTo(@intCast(offset)) catch |err| switch (err) {
            else => return ReadSeekerError.SeekFailed,
        };

        return @intCast(new_pos);
    }
};

// Usage example
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Example 1: BytesReadSeeker
    const data = "Hello, World! This is a test string for reading and seeking.";
    var bytes_reader = BytesReadSeeker.init(data);
    var reader = bytes_reader.asReadSeeker();

    // Read first 5 bytes
    var buf: [10]u8 = undefined;
    const n1 = try reader.read(buf[0..5]);
    std.debug.print("Read {d} bytes: '{s}'\n", .{ n1, buf[0..n1] });

    // Seek to position 7
    const pos = try reader.seek(7, .start);
    std.debug.print("Seeked to position: {d}\n", .{pos});

    // Read next 5 bytes
    const n2 = try reader.read(buf[0..5]);
    std.debug.print("Read {d} bytes: '{s}'\n", .{ n2, buf[0..n2] });

    // Seek relative to current position
    _ = try reader.seek(-3, .current);
    const n3 = try reader.read(buf[0..5]);
    std.debug.print("Read {d} bytes after relative seek: '{s}'\n", .{ n3, buf[0..n3] });

    // Example 2: Read all remaining data
    _ = try reader.seek(0, .start); // Reset to beginning
    const all_data = try reader.readAll(allocator);
    defer allocator.free(all_data);
    std.debug.print("Read all data: '{s}'\n", .{all_data});
}

// Generic function that works with any ReadSeeker
fn processReadSeeker(reader: ReadSeeker, allocator: Allocator) !void {
    // Save current position
    const current_pos = try reader.seek(0, .current);

    // Go to beginning and read first 10 bytes
    _ = try reader.seek(0, .start);
    var buf: [10]u8 = undefined;
    const n = reader.read(&buf) catch |err| switch (err) {
        ReadSeekerError.EOF => 0,
        else => return err,
    };

    if (n > 0) {
        std.debug.print("First {d} bytes: '{s}'\n", .{ n, buf[0..n] });
    }

    // Restore position
    _ = try reader.seek(current_pos, .start);
}
