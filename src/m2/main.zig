const std = @import("std");
const mpq = @import("mpq");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    const stdout = std.io.getStdOut().writer();

    // Get args
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    // Skip program name
    _ = args.next();

    // Get MPQ file path
    const mpq_path = args.next() orelse {
        std.debug.print("Usage: {s} <mpq_file_path>\n", .{std.os.argv[0]});
        return error.InvalidArgs;
    };

    // Open MPQ file
    const file = std.fs.cwd().openFile(mpq_path, .{}) catch |err| {
        std.debug.print("Failed to open MPQ file: {}\n", .{err});
        return err;
    };
    defer file.close();

    const archive = try mpq.MPQ.init(file, allocator);
    defer archive.deinit();
    const content = try archive.fileByName(file, "(listfile)", allocator);
    defer allocator.free(content);
    try stdout.print("{s}\n", .{content});
}
