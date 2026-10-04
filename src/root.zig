const std = @import("std");
const builtin = @import("builtin");

pub const Group = struct {
    /// Extension including the leading dot (e.g. ".zig"), or "" for files without one.
    ext: []const u8,
    /// File names, sorted.
    files: []const []const u8,
};

pub const Options = struct {
    /// Include files whose names start with ".".
    include_hidden: bool = false,
    /// Group extensions that differ only in ASCII case (".txt" and ".TXT")
    /// under the lowercase extension, and sort file names ignoring ASCII case.
    case_insensitive: bool = false,
};

/// Groups the regular files in `dir` by extension.
/// Groups are sorted by extension and each group's files are sorted by name.
/// All returned memory is owned by `allocator`; an arena is the intended use.
pub fn groupByExtension(allocator: std.mem.Allocator, io: std.Io, dir: std.Io.Dir, options: Options) ![]Group {
    var extensions = std.StringHashMap(std.ArrayList([]const u8)).init(allocator);

    var lower_buf: [std.Io.Dir.max_name_bytes]u8 = undefined;

    var iterator = dir.iterate();
    while (try iterator.next(io)) |entry| {
        const hidden = std.mem.startsWith(u8, entry.name, ".");
        if ((options.include_hidden or !hidden) and isFile(io, dir, entry)) {
            const duped_name = try allocator.dupe(u8, entry.name);
            // Points into `duped_name`, so it outlives this iteration without a copy.
            const ext = std.fs.path.extension(duped_name);
            const key = if (options.case_insensitive) std.ascii.lowerString(&lower_buf, ext) else ext;

            const gop = try extensions.getOrPut(key);
            if (!gop.found_existing) {
                // `lower_buf` is reused for the next entry, so a new lowercased key needs its own copy.
                if (options.case_insensitive) gop.key_ptr.* = try allocator.dupe(u8, key);
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
        if (options.case_insensitive) {
            std.mem.sort([]const u8, files, {}, stringLessThanIgnoreCase);
        } else {
            std.mem.sort([]const u8, files, {}, stringLessThan);
        }
        groups[i] = .{ .ext = kv.key_ptr.*, .files = files };
    }

    std.mem.sort(Group, groups, {}, groupLessThan);
    return groups;
}

/// Returns true for regular files and for symlinks that resolve to one.
/// Broken, looping or unreadable symlinks are treated as not being files.
fn isFile(io: std.Io, dir: std.Io.Dir, entry: std.Io.Dir.Entry) bool {
    return switch (entry.kind) {
        .file => true,
        .sym_link => {
            const stat = dir.statFile(io, entry.name, .{}) catch return false;
            return stat.kind == .file;
        },
        else => false,
    };
}

fn stringLessThan(context: void, a: []const u8, b: []const u8) bool {
    _ = context;
    return std.mem.lessThan(u8, a, b);
}

/// Orders names ignoring ASCII case, falling back to byte order so that
/// names differing only in case ("a.txt", "A.txt") have a stable order.
fn stringLessThanIgnoreCase(context: void, a: []const u8, b: []const u8) bool {
    return switch (std.ascii.orderIgnoreCase(a, b)) {
        .lt => true,
        .gt => false,
        .eq => stringLessThan(context, a, b),
    };
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

    const groups = try groupByExtension(arena.allocator(), testing.io, tmp.dir, .{});
    try testing.expectEqual(0, groups.len);
}

test "groups files by extension, sorting groups and files" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var tmp = testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try createFiles(tmp.dir, &.{ "zeta.md", "b.zig", "Makefile", "alpha.md", "a.zig", "LICENSE" });

    const groups = try groupByExtension(arena.allocator(), testing.io, tmp.dir, .{});
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

    const groups = try groupByExtension(arena.allocator(), testing.io, tmp.dir, .{});
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

    const groups = try groupByExtension(arena.allocator(), testing.io, tmp.dir, .{});
    try expectGroups(&.{
        .{ .ext = ".TXT", .files = &.{"b.TXT"} },
        .{ .ext = ".txt", .files = &.{"a.txt"} },
    }, groups);
}

test "groups extensions case-insensitively when asked" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var tmp = testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try createFiles(tmp.dir, &.{ "a.txt", "b.TXT", "c.Txt", "d.md" });

    const groups = try groupByExtension(arena.allocator(), testing.io, tmp.dir, .{ .case_insensitive = true });
    try expectGroups(&.{
        .{ .ext = ".md", .files = &.{"d.md"} },
        .{ .ext = ".txt", .files = &.{ "a.txt", "b.TXT", "c.Txt" } },
    }, groups);
}

test "sorts file names case-insensitively when asked" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var tmp = testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    // No two names differ only in case: they would collide on case-insensitive
    // filesystems (macOS, Windows). That tie-break is tested on the comparator below.
    try createFiles(tmp.dir, &.{ "Zebra.md", "apple.md", "Banana.md", "cherry.MD" });

    const groups = try groupByExtension(arena.allocator(), testing.io, tmp.dir, .{ .case_insensitive = true });
    try expectGroups(&.{
        .{ .ext = ".md", .files = &.{ "apple.md", "Banana.md", "cherry.MD", "Zebra.md" } },
    }, groups);
}

test "case-insensitive sort orders names differing only in case by byte order" {
    var names = [_][]const u8{ "banana.MD", "apple.md", "Banana.md", "banana.md" };
    std.mem.sort([]const u8, &names, {}, stringLessThanIgnoreCase);
    const expected = [_][]const u8{ "apple.md", "Banana.md", "banana.MD", "banana.md" };
    for (expected, names) |e, a| {
        try testing.expectEqualStrings(e, a);
    }
}

test "sorts file names by byte order by default" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var tmp = testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try createFiles(tmp.dir, &.{ "Zebra.md", "apple.md", "Banana.md" });

    const groups = try groupByExtension(arena.allocator(), testing.io, tmp.dir, .{});
    try expectGroups(&.{
        .{ .ext = ".md", .files = &.{ "Banana.md", "Zebra.md", "apple.md" } },
    }, groups);
}

test "skips hidden files" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var tmp = testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try createFiles(tmp.dir, &.{ ".gitignore", ".hidden.txt", "shown.txt" });

    const groups = try groupByExtension(arena.allocator(), testing.io, tmp.dir, .{});
    try expectGroups(&.{
        .{ .ext = ".txt", .files = &.{"shown.txt"} },
    }, groups);
}

test "includes hidden files when asked" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var tmp = testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.createDirPath(testing.io, ".git");
    try createFiles(tmp.dir, &.{ ".gitignore", ".hidden.txt", "shown.txt" });

    const groups = try groupByExtension(arena.allocator(), testing.io, tmp.dir, .{ .include_hidden = true });
    try expectGroups(&.{
        .{ .ext = "", .files = &.{".gitignore"} },
        .{ .ext = ".txt", .files = &.{ ".hidden.txt", "shown.txt" } },
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

    const groups = try groupByExtension(arena.allocator(), testing.io, tmp.dir, .{});
    try expectGroups(&.{
        .{ .ext = ".txt", .files = &.{"top.txt"} },
    }, groups);
}

test "includes symlinks to files" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var tmp = testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try createFiles(tmp.dir, &.{"real.txt"});
    try tmp.dir.symLink(testing.io, "real.txt", "link.txt", .{});
    try tmp.dir.symLink(testing.io, "link.txt", "chained.txt", .{});

    const groups = try groupByExtension(arena.allocator(), testing.io, tmp.dir, .{});
    try expectGroups(&.{
        .{ .ext = ".txt", .files = &.{ "chained.txt", "link.txt", "real.txt" } },
    }, groups);
}

test "skips symlinks to directories and broken or looping symlinks" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var tmp = testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.createDirPath(testing.io, "subdir");
    try tmp.dir.symLink(testing.io, "subdir", "dir_link.d", .{ .is_directory = true });
    try tmp.dir.symLink(testing.io, "missing.txt", "broken.txt", .{});
    try tmp.dir.symLink(testing.io, "loop_b.txt", "loop_a.txt", .{});
    try tmp.dir.symLink(testing.io, "loop_a.txt", "loop_b.txt", .{});
    try createFiles(tmp.dir, &.{"real.txt"});

    const groups = try groupByExtension(arena.allocator(), testing.io, tmp.dir, .{});
    try expectGroups(&.{
        .{ .ext = ".txt", .files = &.{"real.txt"} },
    }, groups);
}
