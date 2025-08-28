const std = @import("std");
const fs = std.fs;
const print = std.debug.print;
const ArrayList = std.ArrayList;
const StringHashMap = std.StringHashMap;
const Allocator = std.mem.Allocator;

const Options = struct {
    include_hidden: bool,
    dir_path: []const u8,
    verbose: bool,
};

const FileType = enum {
    regular,
    directory,
    symlink,
    other,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();

    const options = try parseArgs(arena_allocator);

    if (options.verbose) {
        print("Scanning directory: {s}\n", .{options.dir_path});
        print("Including hidden files: {}\n", .{options.include_hidden});
    }

    var extensions = StringHashMap(ArrayList([]u8)).init(allocator);
    defer {
        var it = extensions.iterator();
        while (it.next()) |entry| {
            // Free each duplicated filename string within the ArrayList
            for (entry.value_ptr.items) |item| {
                allocator.free(item);
            }
            // Deinitialize the ArrayList itself
            entry.value_ptr.deinit(allocator);
        }
        // Deinitialize the StringHashMap
        extensions.deinit();
    }

    listFiles(allocator, &extensions, options) catch |err| {
        print("Error: Unable to list files: {s}\n", .{@errorName(err)});
        return err;
    };

    if (extensions.count() == 0) {
        print("No files found in the directory.\n", .{});
        return;
    }

    try printSortedResults(arena_allocator, &extensions, options.verbose);
}

fn parseArgs(allocator: Allocator) !Options {
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
    _ = args.skip(); // skip program name

    var options = Options{
        .include_hidden = false,
        .dir_path = ".",
        .verbose = false,
    };

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--include-hidden")) {
            options.include_hidden = true;
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            printHelp();
            std.process.exit(0);
        } else if (std.mem.eql(u8, arg, "--verbose") or std.mem.eql(u8, arg, "-v")) {
            options.verbose = true;
        } else {
            options.dir_path = arg;
        }
    }

    return options;
}

fn printHelp() void {
    print(
        \\Usage: sweep-dir [OPTIONS] [DIRECTORY]
        \\
        \\Options:
        \\  --include-hidden    Include hidden files in the output
        \\  -v, --verbose       Enable verbose output
        \\  -h, --help          Display this help message
        \\
        \\If no directory is specified, the current directory will be used.
        \\
    , .{});
}

fn listFiles(allocator: Allocator, extensions: *StringHashMap(ArrayList([]u8)), options: Options) !void {
    var dir = fs.cwd().openDir(options.dir_path, .{ .iterate = true }) catch |err| {
        print("Error: Unable to open directory '{s}': {s}\n", .{ options.dir_path, @errorName(err) });
        return err;
    };
    defer dir.close();

    var iterator = dir.iterate();
    while (try iterator.next()) |entry| {
        const file_type = classifyFile(entry);
        if (file_type == .regular and (options.include_hidden or !isDotfile(entry.name))) {
            const ext = std.fs.path.extension(entry.name);
            const duped_name = try allocator.dupe(u8, entry.name);
            errdefer allocator.free(duped_name);

            // Manual get-then-put logic to avoid getOrPut issues
            if (extensions.getPtr(ext)) |file_list| {
                // Extension already exists, just append the new file name.
                try file_list.append(allocator, duped_name);
            } else {
                // Extension does not exist. Create a new ArrayList.
                const duped_ext = try allocator.dupe(u8, ext);
                errdefer allocator.free(duped_ext);

                // In this Zig version, ArrayList is a "dumb" struct.
                // Initialize it empty and pass the allocator to functions that need it.
                var new_list = ArrayList([]u8){};
                errdefer new_list.deinit(allocator); // Clean up if the put fails

                try new_list.append(allocator, duped_name);

                // Put the newly created list into the map.
                try extensions.put(duped_ext, new_list);
            }
        }
    }
}


fn printSortedResults(allocator: Allocator, extensions: *const StringHashMap(ArrayList([]u8)), verbose: bool) !void {
    // Initialize with an empty struct literal.
    var sorted_extensions = ArrayList([]const u8){};
    defer sorted_extensions.deinit(allocator);

    var it = extensions.iterator();
    while (it.next()) |entry| {
        try sorted_extensions.append(allocator, entry.key_ptr.*);
    }

    std.mem.sort([]const u8, sorted_extensions.items, {}, stringLessThan);

    // WORKAROUND: The std I/O APIs in this Zig version are proving impossible to
    // access correctly. We will use `std.debug.print` for all output.
    // This writes to stderr, but for a simple CLI tool, the result is the same.
    for (sorted_extensions.items) |ext| {
        const display_ext = if (std.mem.startsWith(u8, ext, ".")) ext[1..] else ext;
        print("{s}:\n", .{display_ext});
        if (extensions.get(ext)) |files| {
            std.mem.sort([]u8, files.items, {}, stringLessThan);
            for (files.items) |file| {
                print("- {s}\n", .{file});
            }
            if (verbose) {
                print("Total files: {d}\n", .{files.items.len});
            }
        }
        print("\n", .{});
    }
}

fn isDotfile(filename: []const u8) bool {
    return std.mem.startsWith(u8, filename, ".");
}

fn stringLessThan(context: void, a: []const u8, b: []const u8) bool {
    _ = context;
    return std.mem.lessThan(u8, a, b);
}

fn classifyFile(entry: fs.Dir.Entry) FileType {
    return switch (entry.kind) {
        .file => .regular,
        .directory => .directory,
        .sym_link => .symlink,
        else => .other,
    };
}
