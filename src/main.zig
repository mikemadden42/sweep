const std = @import("std");
const sweep = @import("sweep");

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const io = init.io;

    var buf: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(io, &buf);

    var args = try init.minimal.args.iterateAllocator(allocator);
    _ = args.skip();
    const dir_path = args.next() orelse ".";

    var dir = std.Io.Dir.cwd().openDir(io, dir_path, .{ .iterate = true }) catch |err|
        fatal(io, "cannot open '{s}': {s}", .{ dir_path, describeError(err) });
    defer dir.close(io);

    const groups = sweep.groupByExtension(allocator, io, dir) catch |err|
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

fn fatal(io: std.Io, comptime format: []const u8, args: anytype) noreturn {
    var buf: [1024]u8 = undefined;
    var stderr = std.Io.File.stderr().writer(io, &buf);
    stderr.interface.print("sweep: " ++ format ++ "\n", args) catch {};
    stderr.interface.flush() catch {};
    std.process.exit(1);
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
