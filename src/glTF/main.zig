const std = @import("std");
const utils = @import("utils");
const clap = @import("clap");
const gltf = @import("./glTF.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();

    const params = comptime clap.parseParamsComptime(
        \\-h, --help  Display this help and exit.
        \\<gltf_file> The glTF file to process.
    );
    const parsers = comptime .{
        .gltf_file = clap.parsers.string,
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
        try stdout.print("Usage: gltf_info ", .{});
        try clap.usage(stdout, clap.Help, &params);
        try stdout.print("\n\n", .{});
        try clap.help(stdout, clap.Help, &params, .{
            .description_on_new_line = false,
        });
        return;
    }

    // Open glTF file
    const input_file = res.positionals[0] orelse return error.MissingArg;
    const file = std.fs.cwd().openFile(input_file, .{}) catch |err| {
        try stderr.print("Failed to open glTF file: {}\n", .{err});
        return err;
    };
    defer file.close();
    const header = try gltf.Header.init(file);
    var gltf_json = try header.parseJSON(file, allocator);
    defer gltf_json.deinit(allocator);
    utils.debugPrefix("returned gltf", gltf_json);
}
