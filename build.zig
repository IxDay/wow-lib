const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const list_version = b.addExecutable(.{
        .name = "list_version",
        .root_source_file = b.path("list_version.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(list_version);

    const mpq = b.addExecutable(.{
        .name = "mpq",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(mpq);

    // Dependencies build
    const z_dep = b.dependency("z", .{});
    const z = b.addStaticLibrary(.{
        .name = "z",
        .target = target,
        .optimize = optimize,
    });
    z.addCSourceFiles(.{
        .root = z_dep.path(""),
        .files = &.{
            "adler32.c", "compress.c", "crc32.c",    "deflate.c",
            "gzclose.c", "gzlib.c",    "gzread.c",   "gzwrite.c",
            "inflate.c", "infback.c",  "inftrees.c", "inffast.c",
            "trees.c",   "uncompr.c",  "zutil.c",
        },
        .flags = &.{
            "-DHAVE_SYS_TYPES_H", "-DHAVE_STDINT_H", "-DHAVE_STDDEF_H",
            "-DZ_HAVE_UNISTD_H",
        },
    });
    z.linkLibC();

    // Run steps for each executable

    const run_list_version = b.addRunArtifact(list_version);
    run_list_version.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_list_version.addArgs(args);
    }
    const run_list_version_step = b.step("run:list_version", "Run the list version application");
    run_list_version_step.dependOn(&run_list_version.step);

    const run_mpq = b.addRunArtifact(mpq);
    run_mpq.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_mpq.addArgs(args);
    }
    const run_mpq_step = b.step("run:mpq", "Run the mpq application");
    run_mpq_step.dependOn(&run_mpq.step);

    // Unit tests for each component
    const utils_tests = b.addTest(.{
        .root_source_file = b.path("src/utils.zig"),
        .target = target,
        .optimize = optimize,
    });
    utils_tests.addIncludePath(z_dep.path(""));
    utils_tests.linkLibrary(z);

    // Run all tests
    const run_utils_tests = b.addRunArtifact(utils_tests);

    const test_step = b.step("test", "Run all unit tests");
    test_step.dependOn(&run_utils_tests.step);

    // Individual test steps
    const test_utils_step = b.step("test:utils", "Run utils tests");
    test_utils_step.dependOn(&run_utils_tests.step);
}
