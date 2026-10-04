const std = @import("std");

pub const Group = struct {
    /// Extension including the leading dot (e.g. ".zig"), or "" for files without one.
    ext: []const u8,
    /// File names, sorted.
    files: []const []const u8,
};

/// Groups the regular, non-hidden files in `dir` by extension.
/// Groups are sorted by extension and each group's files are sorted by name.
/// All returned memory is owned by `allocator`; an arena is the intended use.
pub fn groupByExtension(allocator: std.mem.Allocator, io: std.Io, dir: std.Io.Dir) ![]Group {
    var extensions = std.StringHashMap(std.ArrayList([]const u8)).init(allocator);

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

    const groups = try allocator.alloc(Group, extensions.count());
    var it = extensions.iterator();
    var i: usize = 0;
    while (it.next()) |kv| : (i += 1) {
        const files = kv.value_ptr.items;
        std.mem.sort([]const u8, files, {}, stringLessThan);
        groups[i] = .{ .ext = kv.key_ptr.*, .files = files };
    }

    std.mem.sort(Group, groups, {}, groupLessThan);
    return groups;
}

fn stringLessThan(context: void, a: []const u8, b: []const u8) bool {
    _ = context;
    return std.mem.lessThan(u8, a, b);
}

fn groupLessThan(context: void, a: Group, b: Group) bool {
    _ = context;
    return std.mem.lessThan(u8, a.ext, b.ext);
}
