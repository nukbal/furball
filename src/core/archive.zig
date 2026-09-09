const std = @import("std");

const image = @import("image.zig");
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
    ai_models: ?*const realesrgan.Models,
) !void {
    if (files.len == 0) return error.EmptyArchive;
    var output = std.ArrayList(zip.ImageEntry).empty;
    defer {
        for (output.items) |entry| {
            alloc.free(entry.name);
            alloc.free(entry.bytes);
        }
        output.deinit(alloc);
    }

    for (files) |entry| {
        if (entry.kind != .image) continue;

        const encoded = try image.encodeBytes(alloc, io, entry.source, config, 0, ai_models);
        const name = outputName(alloc, entry.relative, config.suffix) catch |err| {
            alloc.free(encoded);
            return err;
        };

        output.append(alloc, .{ .name = name, .bytes = encoded }) catch |err| {
            alloc.free(name);
            alloc.free(encoded);
            return err;
        };
    }

    if (output.items.len == 0) return error.EmptyArchive;

    const archive = try zip.createMemory(alloc, output.items);
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
