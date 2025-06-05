const std = @import("std");
const clap = @import("clap");
const blp = @import("blp.zig");
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
    const input_file = res.positionals[0] orelse return error.MissingArg;
    const file = std.fs.cwd().openFile(input_file, .{}) catch |err| {
        try stderr.print("Failed to open BLP file: {}\n", .{err});
        return err;
    };
    defer file.close();
    const img = try blp.BLP.init(file);
    // std.debug.print("{}", .{img.header});
    var zimg_img = try img.toImg(file, allocator);
    defer zimg_img.deinit();

    const output_file = try outputFile(allocator, input_file);
    defer allocator.free(output_file);
    try zimg_img.writeToFilePath(output_file, .{ .png = .{} });
}

fn outputFile(allocator: std.mem.Allocator, input_file: []const u8) ![]u8 {
    return std.fmt.allocPrint(
        allocator,
        "{s}.png",
        .{std.fs.path.stem(input_file)},
    );
}
