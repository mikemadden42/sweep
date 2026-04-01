const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();
    const allocator = arena.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    _ = args.skip();
    const dir_path = args.next() orelse ".";

    // StringHashMap still uses .init(allocator) in this version
    var extensions = std.StringHashMap(std.ArrayList([]const u8)).init(allocator);

    var dir = try std.fs.cwd().openDir(dir_path, .{ .iterate = true });
    defer dir.close();
    var iterator = dir.iterate();

    while (try iterator.next()) |entry| {
        if (entry.kind == .file and !std.mem.startsWith(u8, entry.name, ".")) {
            const ext = std.fs.path.extension(entry.name);

            const duped_ext = try allocator.dupe(u8, ext);
            const duped_name = try allocator.dupe(u8, entry.name);

            const gop = try extensions.getOrPut(duped_ext);
            if (!gop.found_existing) {
                // FIXED: Initialize as an empty struct literal
                gop.value_ptr.* = std.ArrayList([]const u8){};
            }
            // FIXED: Pass the allocator directly into the append call
            try gop.value_ptr.append(allocator, duped_name);
        }
    }

    if (extensions.count() == 0) {
        std.debug.print("No files found.\n", .{});
        return;
    }

    // FIXED: Initialize as an empty struct literal
    var sorted_keys = std.ArrayList([]const u8){};
    var key_it = extensions.keyIterator();
    while (key_it.next()) |key| {
        // FIXED: Pass the allocator directly into the append call
        try sorted_keys.append(allocator, key.*);
    }

    std.mem.sort([]const u8, sorted_keys.items, {}, stringLessThan);

    for (sorted_keys.items) |ext| {
        const display_ext = if (ext.len > 0 and ext[0] == '.') ext[1..] else ext;
        std.debug.print("{s}:\n", .{if (display_ext.len == 0) "No Extension" else display_ext});

        const files = extensions.get(ext).?;
        std.mem.sort([]const u8, files.items, {}, stringLessThan);

        for (files.items) |file| {
            std.debug.print("- {s}\n", .{file});
        }
        std.debug.print("\n", .{});
    }
}

fn stringLessThan(context: void, a: []const u8, b: []const u8) bool {
    _ = context;
    return std.mem.lessThan(u8, a, b);
}
