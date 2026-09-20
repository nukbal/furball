const std = @import("std");

const image_batch = @import("image_batch.zig");
const protocol = @import("protocol.zig");
const storage = @import("storage.zig");
const zip = @import("zip.zig");
const realesrgan = @import("realesrgan.zig");

const Allocator = std.mem.Allocator;

pub const FileEntry = struct {
    source: []const u8,
    relative: []const u8,
    kind: protocol.Kind,
};

pub fn createZip(
    alloc: Allocator,
    io: std.Io,
    files: []const FileEntry,
    destination: []const u8,
    config: protocol.Config,
    progress: ?protocol.Progress,
) !void {
    if (files.len == 0) return error.EmptyArchive;
    var inputs = std.ArrayList(image_batch.Source).empty;
    defer inputs.deinit(alloc);
    var names = std.ArrayList([]u8).empty;
    defer {
        for (names.items) |name| alloc.free(name);
        names.deinit(alloc);
    }

    for (files) |entry| {
        if (entry.kind != .image) continue;

        const name = try outputName(alloc, entry.relative, config.suffix);
        names.append(alloc, name) catch |err| {
            alloc.free(name);
            return err;
        };
        inputs.append(alloc, .{ .file = entry.source }) catch |err| return err;
    }

    if (inputs.items.len == 0) return error.EmptyArchive;

    const results = try image_batch.process(alloc, io, inputs.items, config, progress);
    defer image_batch.freeResults(alloc, results);

    const output = try alloc.alloc(zip.ImageEntry, results.len);
    defer alloc.free(output);
    for (output, results, names.items) |*entry, result, name| {
        entry.* = .{ .name = name, .bytes = result.bytes };
    }

    const archive = try zip.createMemory(alloc, output);
    defer alloc.free(archive);

    try storage.writeAtomic(io, destination, archive);
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
