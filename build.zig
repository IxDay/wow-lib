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

    // // Optional: Create a shared library that all executables can use
    // const shared_lib = b.addStaticLibrary(.{
    //     .name = "shared",
    //     .root_source_file = b.path("src/shared/lib.zig"),
    //     .target = target,
    //     .optimize = optimize,
    // });

    // // Link the shared library to all executables
    // main_exe.linkLibrary(shared_lib);
    // cli_exe.linkLibrary(shared_lib);
    // server_exe.linkLibrary(shared_lib);

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

    // // Build all executables step
    // const build_all_step = b.step("build-all", "Build all executables");
    // build_all_step.dependOn(&main_exe.step);
    // build_all_step.dependOn(&cli_exe.step);
    // build_all_step.dependOn(&server_exe.step);

    // // Unit tests for each component
    // const main_tests = b.addTest(.{
    //     .root_source_file = b.path("src/main.zig"),
    //     .target = target,
    //     .optimize = optimize,
    // });
    // main_tests.linkLibrary(shared_lib);

    // const cli_tests = b.addTest(.{
    //     .root_source_file = b.path("src/cli.zig"),
    //     .target = target,
    //     .optimize = optimize,
    // });
    // cli_tests.linkLibrary(shared_lib);

    // const server_tests = b.addTest(.{
    //     .root_source_file = b.path("src/server.zig"),
    //     .target = target,
    //     .optimize = optimize,
    // });
    // server_tests.linkLibrary(shared_lib);

    // const shared_tests = b.addTest(.{
    //     .root_source_file = b.path("src/shared/lib.zig"),
    //     .target = target,
    //     .optimize = optimize,
    // });

    // // Run all tests
    // const run_main_tests = b.addRunArtifact(main_tests);
    // const run_cli_tests = b.addRunArtifact(cli_tests);
    // const run_server_tests = b.addRunArtifact(server_tests);
    // const run_shared_tests = b.addRunArtifact(shared_tests);

    // const test_step = b.step("test", "Run all unit tests");
    // test_step.dependOn(&run_main_tests.step);
    // test_step.dependOn(&run_cli_tests.step);
    // test_step.dependOn(&run_server_tests.step);
    // test_step.dependOn(&run_shared_tests.step);

    // // Individual test steps
    // const test_main_step = b.step("test-main", "Run main app tests");
    // test_main_step.dependOn(&run_main_tests.step);

    // const test_cli_step = b.step("test-cli", "Run CLI tool tests");
    // test_cli_step.dependOn(&run_cli_tests.step);

    // const test_server_step = b.step("test-server", "Run server tests");
    // test_server_step.dependOn(&run_server_tests.step);

    // const test_shared_step = b.step("test-shared", "Run shared library tests");
    // test_shared_step.dependOn(&run_shared_tests.step);
}
