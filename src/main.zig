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

    var dir = try std.Io.Dir.cwd().openDir(io, dir_path, .{ .iterate = true });
    defer dir.close(io);

    const groups = try sweep.groupByExtension(allocator, io, dir);

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
