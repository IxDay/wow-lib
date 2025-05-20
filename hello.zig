const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Method 1: Read entire file at once
    {
        const file_content = try std.fs.cwd().readFileAlloc(allocator, "example.txt", 1024 * 1024);
        defer allocator.free(file_content);
        std.debug.print("File content: {s}\n", .{file_content});
    }
}
