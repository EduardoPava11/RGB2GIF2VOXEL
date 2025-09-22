const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Build static library for iOS
    const lib = b.addStaticLibrary(.{
        .name = "yxcbor",
        .root_source_file = b.path("yxcbor.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Export C symbols
    lib.bundle_compiler_rt = true;
    lib.linkLibC();

    // Generate header file
    lib.installHeader(b.path("yxcbor.h"), "yxcbor.h");

    b.installArtifact(lib);

    // Add test step
    const main_tests = b.addTest(.{
        .root_source_file = b.path("yxcbor.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_main_tests = b.addRunArtifact(main_tests);
    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_main_tests.step);
}