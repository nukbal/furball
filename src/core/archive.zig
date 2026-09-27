const std = @import("std");

const image_batch = @import("image_batch.zig");
const protocol = @import("protocol.zig");
const storage = @import("storage.zig");
const zip = @import("zip.zig");

const Allocator = std.mem.Allocator;

pub const FileEntry = struct {
    source: []const u8,
    relative: []const u8,
    kind: protocol.Kind,
};

pub fn createZipFromResults(
    alloc: Allocator,
    io: std.Io,
    names: []const []const u8,
    results: []const image_batch.Result,
    suffix: []const u8,
    destination: []const u8,
) !void {
    if (names.len == 0 or names.len != results.len) return error.EmptyArchive;

    const owned_names = try alloc.alloc([]u8, names.len);
    var owned_count: usize = 0;
    errdefer {
        for (owned_names[0..owned_count]) |name| alloc.free(name);
        alloc.free(owned_names);
    }
    for (names) |name| {
        owned_names[owned_count] = try outputName(alloc, name, suffix);
        owned_count += 1;
    }

    const entries = try alloc.alloc(zip.ImageEntry, results.len);
    defer alloc.free(entries);
    for (entries, results, owned_names) |*entry, result, name| {
        entry.* = .{ .name = name, .bytes = result.bytes };
    }

    const output = try zip.createMemory(alloc, entries);
    defer alloc.free(output);
    try storage.writeAtomic(io, destination, output);

    for (owned_names) |name| alloc.free(name);
    alloc.free(owned_names);
}

fn outputName(alloc: Allocator, relative: []const u8, suffix: []const u8) ![]u8 {
    const normalized = try zipNormalize(alloc, relative);
    defer alloc.free(normalized);

    const directory = std.fs.path.dirname(normalized);
    const base = std.fs.path.basename(normalized);
    const stem = std.fs.path.stem(base);
    if (stem.len == 0) return error.InvalidSourceName;

    const filename = try std.fmt.allocPrint(alloc, "{s}{s}.jpg", .{ stem, suffix });
    defer alloc.free(filename);

    return if (directory) |dir| std.fs.path.join(alloc, &.{ dir, filename }) else alloc.dupe(u8, filename);
}

fn zipNormalize(alloc: Allocator, path: []const u8) ![]u8 {
    if (!zip.entryPathIsSafe(path)) return error.UnsafeArchivePath;

    var result = std.ArrayList(u8).empty;
    errdefer result.deinit(alloc);

    var start: usize = 0;
    while (start <= path.len) {
        var end = start;
        while (end < path.len and path[end] != '/' and path[end] != '\\') : (end += 1) {}
        const component = path[start..end];

        if (component.len != 0 and !std.mem.eql(u8, component, ".")) {
            if (result.items.len != 0) try result.append(alloc, '/');
            try result.appendSlice(alloc, component);
        }

        if (end == path.len) break;
        start = end + 1;
    }
    return result.toOwnedSlice(alloc);
}

test "archive output names use JPEG" {
    const name = try outputName(std.testing.allocator, "nested/photo.png", "-small");
    defer std.testing.allocator.free(name);
    try std.testing.expectEqualStrings("nested/photo-small.jpg", name);
}
