const std = @import("std");
const zon = @import("build.zig.zon");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    // Release builds are stripped by default; `-Dstrip=false` keeps symbols
    // for stack traces and profiling.
    const strip = b.option(
        bool,
        "strip",
        "Strip debug info from the executable (default: true unless optimize is Debug)",
    ) orelse (optimize != .debug);

    // The grouping logic, exposed to package consumers as `@import("sweep")`.
    const mod = b.addModule("sweep", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "sweep",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "sweep", .module = mod },
            },
            .strip = strip,
        }),
    });

    // Expose the package version to the executable as `@import("build_options").version`.
    const options = b.addOptions();
    options.addOption([]const u8, "version", zon.version);
    exe.root_module.addOptions("build_options", options);

    b.installArtifact(exe);

    // `zig build run -- <args>` runs the installed executable.
    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    run_cmd.addPassthruArgs();

    const mod_tests = b.addTest(.{
        .root_module = mod,
    });
    const run_mod_tests = b.addRunArtifact(mod_tests);

    // Uses its own module rather than `exe.root_module` so the tests are never
    // stripped and can print stack traces.
    const exe_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "sweep", .module = mod },
            },
        }),
    });
    exe_tests.root_module.addOptions("build_options", options);
    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);
}
