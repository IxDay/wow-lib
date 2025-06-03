const std = @import("std");
const clap = @import("clap");
const builtin = @import("builtin");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();

    const params = comptime clap.parseParamsComptime(
        \\-h, --help  Display this help and exit.
        \\<blp_file> The BLP file to process.
    );
    const parsers = comptime .{
        .blp_file = clap.parsers.string,
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
        try stdout.print("Usage: blp_info ", .{});
        try clap.usage(stdout, clap.Help, &params);
        try stdout.print("\n\n", .{});
        try clap.help(stdout, clap.Help, &params, .{
            .description_on_new_line = false,
        });
        return;
    }

    // Open BLP file
    const blp_path = res.positionals[0] orelse return error.MissingArg;
    const file = std.fs.cwd().openFile(blp_path, .{}) catch |err| {
        try stderr.print("Failed to open BLP file: {}\n", .{err});
        return err;
    };
    defer file.close();
}
