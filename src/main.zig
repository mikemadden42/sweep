const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const io = init.io;

    var buf: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(io, &buf);

    var args = init.minimal.args.iterate();
    _ = args.skip();
    const dir_path = args.next() orelse ".";

    var extensions = std.StringHashMap(std.ArrayList([]const u8)).init(allocator);

    var dir = try std.Io.Dir.cwd().openDir(io, dir_path, .{ .iterate = true });
    defer dir.close(io);
    var iterator = dir.iterate();

    while (try iterator.next(io)) |entry| {
        if (entry.kind == .file and !std.mem.startsWith(u8, entry.name, ".")) {
            const ext = std.fs.path.extension(entry.name);

            const duped_ext = try allocator.dupe(u8, ext);
            const duped_name = try allocator.dupe(u8, entry.name);

            const gop = try extensions.getOrPut(duped_ext);
            if (!gop.found_existing) {
                gop.value_ptr.* = .empty;
            }
            try gop.value_ptr.append(allocator, duped_name);
        }
    }

    if (extensions.count() == 0) {
        try stdout.interface.print("No files found.\n", .{});
        try stdout.interface.flush();
        return;
    }

    var sorted_keys: std.ArrayList([]const u8) = .empty;
    var key_it = extensions.keyIterator();
    while (key_it.next()) |key| {
        try sorted_keys.append(allocator, key.*);
    }

    std.mem.sort([]const u8, sorted_keys.items, {}, stringLessThan);

    for (sorted_keys.items) |ext| {
        const display_ext = if (ext.len > 0 and ext[0] == '.') ext[1..] else ext;
        try stdout.interface.print("{s}:\n", .{if (display_ext.len == 0) "No Extension" else display_ext});

        const files = extensions.get(ext).?;
        std.mem.sort([]const u8, files.items, {}, stringLessThan);

        for (files.items) |file| {
            try stdout.interface.print("- {s}\n", .{file});
        }
        try stdout.interface.print("\n", .{});
    }

    try stdout.interface.flush();
}

fn stringLessThan(context: void, a: []const u8, b: []const u8) bool {
    _ = context;
    return std.mem.lessThan(u8, a, b);
}
