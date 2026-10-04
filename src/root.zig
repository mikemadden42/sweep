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

const testing = std.testing;

fn createFiles(dir: std.Io.Dir, names: []const []const u8) !void {
    for (names) |name| {
        try dir.writeFile(testing.io, .{ .sub_path = name, .data = "" });
    }
}

fn expectGroups(expected: []const Group, actual: []const Group) !void {
    try testing.expectEqual(expected.len, actual.len);
    for (expected, actual) |e, a| {
        try testing.expectEqualStrings(e.ext, a.ext);
        try testing.expectEqual(e.files.len, a.files.len);
        for (e.files, a.files) |ef, af| {
            try testing.expectEqualStrings(ef, af);
        }
    }
}

test "empty directory yields no groups" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var tmp = testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    const groups = try groupByExtension(arena.allocator(), testing.io, tmp.dir);
    try testing.expectEqual(0, groups.len);
}

test "groups files by extension, sorting groups and files" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var tmp = testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try createFiles(tmp.dir, &.{ "zeta.md", "b.zig", "Makefile", "alpha.md", "a.zig", "LICENSE" });

    const groups = try groupByExtension(arena.allocator(), testing.io, tmp.dir);
    try expectGroups(&.{
        .{ .ext = "", .files = &.{ "LICENSE", "Makefile" } },
        .{ .ext = ".md", .files = &.{ "alpha.md", "zeta.md" } },
        .{ .ext = ".zig", .files = &.{ "a.zig", "b.zig" } },
    }, groups);
}

test "uses only the last extension" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var tmp = testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try createFiles(tmp.dir, &.{ "archive.tar.gz", "photo.gz" });

    const groups = try groupByExtension(arena.allocator(), testing.io, tmp.dir);
    try expectGroups(&.{
        .{ .ext = ".gz", .files = &.{ "archive.tar.gz", "photo.gz" } },
    }, groups);
}

test "extensions are case-sensitive" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var tmp = testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try createFiles(tmp.dir, &.{ "a.txt", "b.TXT" });

    const groups = try groupByExtension(arena.allocator(), testing.io, tmp.dir);
    try expectGroups(&.{
        .{ .ext = ".TXT", .files = &.{"b.TXT"} },
        .{ .ext = ".txt", .files = &.{"a.txt"} },
    }, groups);
}

test "skips hidden files" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var tmp = testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try createFiles(tmp.dir, &.{ ".gitignore", ".hidden.txt", "shown.txt" });

    const groups = try groupByExtension(arena.allocator(), testing.io, tmp.dir);
    try expectGroups(&.{
        .{ .ext = ".txt", .files = &.{"shown.txt"} },
    }, groups);
}

test "skips directories" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var tmp = testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.createDirPath(testing.io, "subdir");
    try tmp.dir.createDirPath(testing.io, "conf.d");
    try createFiles(tmp.dir, &.{ "subdir/nested.txt", "top.txt" });

    const groups = try groupByExtension(arena.allocator(), testing.io, tmp.dir);
    try expectGroups(&.{
        .{ .ext = ".txt", .files = &.{"top.txt"} },
    }, groups);
}
