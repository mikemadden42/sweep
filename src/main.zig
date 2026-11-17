const std = @import("std");
const sweep = @import("sweep");
const build_options = @import("build_options");

const usage =
    \\Usage: sweep [options] [directory]
    \\
    \\List the files in a directory, grouped by extension.
    \\The directory defaults to the current one.
    \\
    \\Options:
    \\  -a, --all          Include hidden files (names starting with ".")
    \\  -i, --ignore-case  Ignore case when grouping extensions and sorting names
    \\  -h, --help         Show this help and exit
    \\  -V, --version      Show the version and exit
    \\
;

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const io = init.io;

    var buf: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(io, &buf);

    var args: std.ArrayList([]const u8) = .empty;
    var arg_it = try init.minimal.args.iterateAllocator(allocator);
    _ = arg_it.skip();
    while (arg_it.next()) |arg| try args.append(allocator, arg);

    const run = switch (parseArgs(args.items)) {
        .run => |run| run,
        .help => return finishOutput(io, &stdout, stdout.interface.writeAll(usage)),
        .version => return finishOutput(io, &stdout, stdout.interface.print("sweep {s}\n", .{build_options.version})),
        .unknown_option => |arg| usageError(io, "unknown option '{s}'", .{arg}),
        .unexpected_argument => |arg| usageError(io, "unexpected argument '{s}'", .{arg}),
    };

    const dir_path = run.dir_path;
    var dir = std.Io.Dir.cwd().openDir(io, dir_path, .{ .iterate = true }) catch |err|
        fatal(io, "cannot open '{s}': {s}", .{ dir_path, describeError(err) });
    defer dir.close(io);

    const groups = sweep.groupByExtension(allocator, io, dir, run.options) catch |err|
        fatal(io, "cannot read '{s}': {s}", .{ dir_path, describeError(err) });

    finishOutput(io, &stdout, printGroups(&stdout.interface, groups));
}

fn printGroups(w: *std.Io.Writer, groups: []const sweep.Group) std.Io.Writer.Error!void {
    if (groups.len == 0) {
        try w.print("No files found.\n", .{});
        return;
    }

    for (groups) |group| {
        const ext = group.ext;
        const display_ext = if (ext.len > 0 and ext[0] == '.') ext[1..] else ext;
        try w.print("{s}:\n", .{if (display_ext.len == 0) "No Extension" else display_ext});

        for (group.files) |file| {
            try w.print("- {s}\n", .{file});
        }
        try w.print("\n", .{});
    }
}

/// Flushes `stdout` after the writes in `result`, exiting with an error message if
/// any of them failed. The writer only reports `error.WriteFailed`; the cause is in
/// `stdout.err`.
fn finishOutput(io: std.Io, stdout: *std.Io.File.Writer, result: std.Io.Writer.Error!void) void {
    result catch writeFailed(io, stdout.err);
    stdout.interface.flush() catch writeFailed(io, stdout.err);
}

fn writeFailed(io: std.Io, err: ?std.Io.File.Writer.Error) noreturn {
    const cause: anyerror = err orelse error.WriteFailed;
    // The reader went away (e.g. `sweep | head`); there is no one to tell.
    if (cause == error.BrokenPipe) std.process.exit(1);
    fatal(io, "cannot write output: {s}", .{describeError(cause)});
}

const Command = union(enum) {
    run: Run,
    help,
    version,
    unknown_option: []const u8,
    unexpected_argument: []const u8,
};

const Run = struct {
    dir_path: []const u8,
    options: sweep.Options = .{},
};

fn parseArgs(args: []const []const u8) Command {
    var dir_path: ?[]const u8 = null;
    var options: sweep.Options = .{};
    var options_done = false;
    for (args) |arg| {
        if (!options_done and arg.len > 1 and arg[0] == '-') {
            if (std.mem.eql(u8, arg, "--")) {
                options_done = true;
            } else if (std.mem.startsWith(u8, arg, "--")) {
                if (std.mem.eql(u8, arg, "--all")) {
                    options.include_hidden = true;
                } else if (std.mem.eql(u8, arg, "--ignore-case")) {
                    options.case_insensitive = true;
                } else if (std.mem.eql(u8, arg, "--help")) {
                    return .help;
                } else if (std.mem.eql(u8, arg, "--version")) {
                    return .version;
                } else {
                    return .{ .unknown_option = arg };
                }
            } else {
                // Short flags can be combined: "-ai" is "-a -i".
                for (arg[1..]) |flag| switch (flag) {
                    'a' => options.include_hidden = true,
                    'i' => options.case_insensitive = true,
                    'h' => return .help,
                    'V' => return .version,
                    else => return .{ .unknown_option = arg },
                };
            }
        } else if (dir_path == null) {
            dir_path = arg;
        } else {
            return .{ .unexpected_argument = arg };
        }
    }
    return .{ .run = .{ .dir_path = dir_path orelse ".", .options = options } };
}

fn fatal(io: std.Io, comptime format: []const u8, args: anytype) noreturn {
    exitWithMessage(io, 1, format, args);
}

fn usageError(io: std.Io, comptime format: []const u8, args: anytype) noreturn {
    exitWithMessage(io, 2, format ++ "\nTry 'sweep --help' for more information.", args);
}

fn exitWithMessage(io: std.Io, status: u8, comptime format: []const u8, args: anytype) noreturn {
    var buf: [1024]u8 = undefined;
    var stderr = std.Io.File.stderr().writer(io, &buf);
    stderr.interface.print("sweep: " ++ format ++ "\n", args) catch {};
    stderr.interface.flush() catch {};
    std.process.exit(status);
}

fn describeError(err: anyerror) []const u8 {
    return switch (err) {
        error.FileNotFound => "no such file or directory",
        error.NotDir => "not a directory",
        error.AccessDenied, error.PermissionDenied => "permission denied",
        error.SymLinkLoop => "too many levels of symbolic links",
        error.NameTooLong => "path is too long",
        error.BadPathName => "invalid path name",
        error.NoSpaceLeft => "no space left on device",
        error.NotOpenForWriting => "not open for writing",
        else => @errorName(err),
    };
}

test "describeError gives readable messages" {
    try std.testing.expectEqualStrings("no such file or directory", describeError(error.FileNotFound));
    try std.testing.expectEqualStrings("not a directory", describeError(error.NotDir));
    try std.testing.expectEqualStrings("permission denied", describeError(error.AccessDenied));
    try std.testing.expectEqualStrings("no space left on device", describeError(error.NoSpaceLeft));
    try std.testing.expectEqualStrings("SystemResources", describeError(error.SystemResources));
}

test "printGroups lists each group with its files" {
    var out: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer out.deinit();
    try printGroups(&out.writer, &.{
        .{ .ext = "", .files = &.{"Makefile"} },
        .{ .ext = ".zig", .files = &.{ "a.zig", "b.zig" } },
    });
    try std.testing.expectEqualStrings(
        \\No Extension:
        \\- Makefile
        \\
        \\zig:
        \\- a.zig
        \\- b.zig
        \\
        \\
    , out.written());
}

test "printGroups reports an empty directory" {
    var out: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer out.deinit();
    try printGroups(&out.writer, &.{});
    try std.testing.expectEqualStrings("No files found.\n", out.written());
}

test "printGroups reports a full writer" {
    var buf: [8]u8 = undefined;
    var out: std.Io.Writer = .fixed(&buf);
    try std.testing.expectError(error.WriteFailed, printGroups(&out, &.{
        .{ .ext = ".zig", .files = &.{"a_long_name.zig"} },
    }));
}

fn expectCommand(expected: Command, args: []const []const u8) !void {
    const actual = parseArgs(args);
    try std.testing.expectEqual(std.meta.activeTag(expected), std.meta.activeTag(actual));
    switch (expected) {
        .run => |run| {
            try std.testing.expectEqualStrings(run.dir_path, actual.run.dir_path);
            try std.testing.expectEqual(run.options, actual.run.options);
        },
        .unknown_option => |arg| try std.testing.expectEqualStrings(arg, actual.unknown_option),
        .unexpected_argument => |arg| try std.testing.expectEqualStrings(arg, actual.unexpected_argument),
        .help, .version => {},
    }
}

test "parseArgs defaults to the current directory" {
    try expectCommand(.{ .run = .{ .dir_path = "." } }, &.{});
}

test "parseArgs takes a directory" {
    try expectCommand(.{ .run = .{ .dir_path = "src" } }, &.{"src"});
    try expectCommand(.{ .run = .{ .dir_path = "-" } }, &.{"-"});
}

test "parseArgs recognizes --all" {
    const all: sweep.Options = .{ .include_hidden = true };
    try expectCommand(.{ .run = .{ .dir_path = ".", .options = all } }, &.{"-a"});
    try expectCommand(.{ .run = .{ .dir_path = "src", .options = all } }, &.{ "--all", "src" });
    try expectCommand(.{ .run = .{ .dir_path = "src", .options = all } }, &.{ "src", "-a" });
    try expectCommand(.{ .run = .{ .dir_path = "-a" } }, &.{ "--", "-a" });
}

test "parseArgs recognizes --ignore-case" {
    const ci: sweep.Options = .{ .case_insensitive = true };
    try expectCommand(.{ .run = .{ .dir_path = ".", .options = ci } }, &.{"-i"});
    try expectCommand(.{ .run = .{ .dir_path = "src", .options = ci } }, &.{ "src", "--ignore-case" });
    try expectCommand(.{ .run = .{ .dir_path = ".", .options = .{ .include_hidden = true, .case_insensitive = true } } }, &.{ "-a", "-i" });
}

test "parseArgs accepts combined short flags" {
    const both: sweep.Options = .{ .include_hidden = true, .case_insensitive = true };
    try expectCommand(.{ .run = .{ .dir_path = ".", .options = both } }, &.{"-ai"});
    try expectCommand(.{ .run = .{ .dir_path = "src", .options = both } }, &.{ "-ia", "src" });
    try expectCommand(.{ .run = .{ .dir_path = ".", .options = .{ .include_hidden = true } } }, &.{"-aa"});
    try expectCommand(.help, &.{"-ah"});
    try expectCommand(.version, &.{"-iV"});
    try expectCommand(.{ .unknown_option = "-ax" }, &.{"-ax"});
    try expectCommand(.{ .run = .{ .dir_path = "-ai" } }, &.{ "--", "-ai" });
}

test "parseArgs requires long options to match exactly" {
    try expectCommand(.{ .unknown_option = "--al" }, &.{"--al"});
    try expectCommand(.{ .unknown_option = "--a" }, &.{"--a"});
    try expectCommand(.{ .unknown_option = "--alli" }, &.{"--alli"});
}

test "parseArgs recognizes help and version" {
    try expectCommand(.help, &.{"-h"});
    try expectCommand(.help, &.{"--help"});
    try expectCommand(.version, &.{"-V"});
    try expectCommand(.version, &.{"--version"});
    try expectCommand(.help, &.{ "src", "--help" });
}

test "parseArgs treats arguments after -- as directories" {
    try expectCommand(.{ .run = .{ .dir_path = "--help" } }, &.{ "--", "--help" });
    try expectCommand(.{ .unexpected_argument = "b" }, &.{ "--", "a", "b" });
}

test "parseArgs rejects unknown options and extra arguments" {
    try expectCommand(.{ .unknown_option = "-x" }, &.{"-x"});
    try expectCommand(.{ .unknown_option = "--bogus" }, &.{ "src", "--bogus" });
    try expectCommand(.{ .unexpected_argument = "b" }, &.{ "a", "b" });
}
