const std = @import("std");
const clap = @import("clap");
const mpq = @import("mpq.zig");
const builtin = @import("builtin");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();

    const params = comptime clap.parseParamsComptime(
        \\-h, --help  Display this help and exit.
        \\-u, --unfold Extract files without replicating the directory structure.
        \\-f, --file  <output_file>... Files to extract, they will be placed in the current directory.
        \\<mpq_file> The MPQ file to process.
    );
    const parsers = comptime .{
        .mpq_file = clap.parsers.string,
        .output_file = clap.parsers.string,
    };
    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &params, parsers, .{
        .diagnostic = &diag,
        .allocator = allocator,
    }) catch |err| {
        diag.report(std.io.getStdErr().writer(), err) catch {};
        return err;
    };
    defer res.deinit();

    if (res.args.help != 0) {
        try stdout.print("Usage: mpq_list ", .{});
        try clap.usage(stdout, clap.Help, &params);
        try stdout.print("\n\n", .{});
        try clap.help(stdout, clap.Help, &params, .{
            .description_on_new_line = false,
        });
        return;
    }

    // Open MPQ file
    const mpq_path = res.positionals[0] orelse return error.MissingArg;
    const file = std.fs.cwd().openFile(mpq_path, .{}) catch |err| {
        try stderr.print("Failed to open MPQ file: {}\n", .{err});
        return err;
    };
    defer file.close();
    const archive = try mpq.MPQ.init(file, allocator);
    defer archive.deinit();

    // here we just want a listing
    if (res.args.file.len == 0) {
        const content = try archive.fileByName(file, "(listfile)", allocator);
        defer allocator.free(content);
        try stdout.print("{s}\n", .{content});
        return;
    }
    // here we are handling each file to extract
    for (res.args.file) |asset| {
        const content = try archive.fileByName(file, asset, allocator);
        defer allocator.free(content);

        const fd = try file_create(res.args.unfold != 0, asset, allocator);
        defer fd.close();
        try fd.writeAll(content);
    }
    return;
}

fn file_create(unfold: bool, asset: []const u8, allocator: std.mem.Allocator) !std.fs.File {
    const path = if (builtin.target.os.tag == .windows)
        asset
    else
        try std.mem.replaceOwned(u8, allocator, asset, "\\", "/");
    defer allocator.free(path);

    if (unfold) {
        return std.fs.cwd().createFile(std.fs.path.basename(path), .{});
    } else {
        try std.fs.cwd().makePath(std.fs.path.dirname(path) orelse ".");
        return std.fs.cwd().createFile(path, .{});
    }
}
