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
    \\  -a, --all      Include hidden files (names starting with ".")
    \\  -h, --help     Show this help and exit
    \\  -V, --version  Show the version and exit
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
        .help => {
            try stdout.interface.writeAll(usage);
            try stdout.interface.flush();
            return;
        },
        .version => {
            try stdout.interface.print("sweep {s}\n", .{build_options.version});
            try stdout.interface.flush();
            return;
        },
        .unknown_option => |arg| usageError(io, "unknown option '{s}'", .{arg}),
        .unexpected_argument => |arg| usageError(io, "unexpected argument '{s}'", .{arg}),
    };

    const dir_path = run.dir_path;
    var dir = std.Io.Dir.cwd().openDir(io, dir_path, .{ .iterate = true }) catch |err|
        fatal(io, "cannot open '{s}': {s}", .{ dir_path, describeError(err) });
    defer dir.close(io);

    const groups = sweep.groupByExtension(allocator, io, dir, run.options) catch |err|
        fatal(io, "cannot read '{s}': {s}", .{ dir_path, describeError(err) });

    if (groups.len == 0) {
        try stdout.interface.print("No files found.\n", .{});
        try stdout.interface.flush();
        return;
    }

    for (groups) |group| {
        const ext = group.ext;
        const display_ext = if (ext.len > 0 and ext[0] == '.') ext[1..] else ext;
        try stdout.interface.print("{s}:\n", .{if (display_ext.len == 0) "No Extension" else display_ext});

        for (group.files) |file| {
            try stdout.interface.print("- {s}\n", .{file});
        }
        try stdout.interface.print("\n", .{});
    }

    try stdout.interface.flush();
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
            } else if (std.mem.eql(u8, arg, "-a") or std.mem.eql(u8, arg, "--all")) {
                options.include_hidden = true;
            } else if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
                return .help;
            } else if (std.mem.eql(u8, arg, "-V") or std.mem.eql(u8, arg, "--version")) {
                return .version;
            } else {
                return .{ .unknown_option = arg };
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
        else => @errorName(err),
    };
}

test "describeError gives readable messages" {
    try std.testing.expectEqualStrings("no such file or directory", describeError(error.FileNotFound));
    try std.testing.expectEqualStrings("not a directory", describeError(error.NotDir));
    try std.testing.expectEqualStrings("permission denied", describeError(error.AccessDenied));
    try std.testing.expectEqualStrings("SystemResources", describeError(error.SystemResources));
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
