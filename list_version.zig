const std = @import("std");
const mpq = @import("src/mpq.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();

    // Get args
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    // Skip program name
    _ = args.next();

    while (args.next()) |arg| {
        const file = std.fs.cwd().openFile(arg, .{}) catch |err| {
            try stderr.print("Failed to open MPQ file: {}\n", .{err});
            return err;
        };
        defer file.close();
        const header = try mpq.Header.init(file);
        try stdout.print("{s}: {}\n", .{ arg, header });
    }
}
