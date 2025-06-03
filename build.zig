const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Dependencies build
    const clap = b.dependency("clap", .{});

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

    const bz2_dep = b.dependency("bz2", .{});
    const bz2 = b.addStaticLibrary(.{
        .name = "bz2",
        .target = target,
        .optimize = optimize,
    });
    bz2.addCSourceFiles(.{
        .root = bz2_dep.path(""),
        .files = &.{
            "blocksort.c",  "bzlib.c",   "compress.c",  "crctable.c",
            "decompress.c", "huffman.c", "randtable.c",
        },
        .flags = &.{
            "-fPIC",                         "-Wall",               "-Wextra",
            "-Wmissing-prototypes",          "-Wstrict-prototypes", "-Wmissing-declarations",
            "-Wpointer-arith",               "-Wformat-security",   "-Wredundant-decls",
            "-Wwrite-strings",               "-Wshadow",            "-Winline",
            "-Wnested-externs",              "-Wfloat-equal",       "-Wundef",
            "-Wendif-labels",                "-Wempty-body",        "-Wcast-align",
            "-Wclobbered",                   "-Wvla",               "-Wpragmas",
            "-Wunreachable-code",            "-Waddress",           "-Wattributes",
            "-Wdiv-by-zero",                 "-Wconversion",        "-Wformat-nonliteral",
            "-Wdeclaration-after-statement", "-Wmissing-noreturn",  "-Wno-format-nonliteral",
            "-Wmissing-field-initializers",  "-Wsign-conversion",   "-Wunused-macros",
            "-Wunused-parameter",
        },
    });

    bz2.linkLibC();

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

    mpq.root_module.addImport("clap", clap.module("clap"));
    mpq.addIncludePath(z_dep.path(""));
    mpq.linkLibrary(z);

    mpq.addIncludePath(bz2_dep.path(""));
    mpq.linkLibrary(bz2);

    const blp = b.addExecutable(.{
        .name = "blp",
        .root_source_file = b.path("src/blp/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(blp);

    blp.root_module.addImport("clap", clap.module("clap"));

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

    const run_blp = b.addRunArtifact(blp);
    run_blp.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_blp.addArgs(args);
    }
    const run_blp_step = b.step("run:blp", "Run the blp application");
    run_blp_step.dependOn(&run_blp.step);

    // Unit tests for each component
    const utils_tests = b.addTest(.{
        .root_source_file = b.path("src/utils.zig"),
        .target = target,
        .optimize = optimize,
    });
    utils_tests.addIncludePath(z_dep.path(""));
    utils_tests.linkLibrary(z);

    utils_tests.addIncludePath(bz2_dep.path(""));
    utils_tests.linkLibrary(bz2);
    // Run all tests
    const run_utils_tests = b.addRunArtifact(utils_tests);

    const test_step = b.step("test", "Run all unit tests");
    test_step.dependOn(&run_utils_tests.step);

    // Individual test steps
    const test_utils_step = b.step("test:utils", "Run utils tests");
    test_utils_step.dependOn(&run_utils_tests.step);
}
