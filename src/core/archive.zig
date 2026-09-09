const std = @import("std");

const image = @import("image.zig");
const protocol = @import("protocol.zig");
const storage = @import("storage.zig");
const zip = @import("zip.zig");

pub const FileEntry = struct {
    source: []const u8,
    relative: []const u8,
    kind: protocol.Kind,
};

pub const Processor = struct {
    allocator: std.mem.Allocator,
    io: std.Io,

    pub fn createZip(
        self: Processor,
        files: []const FileEntry,
        destination: []const u8,
        config: protocol.Config,
        image_processor: image.Processor,
    ) !void {
        if (files.len == 0) return error.EmptyArchive;
        var output = std.ArrayList(zip.ImageEntry).empty;
        defer {
            for (output.items) |entry| {
                self.allocator.free(entry.name);
                self.allocator.free(entry.bytes);
            }
            output.deinit(self.allocator);
        }
        for (files) |entry| {
            if (entry.kind != .image) continue;
            const encoded = try image_processor.encodeBytes(entry.source, config, 0);
            const name = outputName(self.allocator, entry.relative, config.suffix) catch |err| {
                self.allocator.free(encoded);
                return err;
            };
            output.append(self.allocator, .{ .name = name, .bytes = encoded }) catch |err| {
                self.allocator.free(name);
                self.allocator.free(encoded);
                return err;
            };
        }
        if (output.items.len == 0) return error.EmptyArchive;
        const archive = try zip.createMemory(self.allocator, output.items);
        defer self.allocator.free(archive);
        try storage.writeAtomic(self.io, destination, archive);
    }
};

fn outputName(allocator: std.mem.Allocator, relative: []const u8, suffix: []const u8) ![]u8 {
    const normalized = try zipNormalize(allocator, relative);
    defer allocator.free(normalized);
    const directory = std.fs.path.dirname(normalized);
    const base = std.fs.path.basename(normalized);
    const stem = std.fs.path.stem(base);
    if (stem.len == 0) return error.InvalidSourceName;
    const filename = try std.fmt.allocPrint(allocator, "{s}{s}.jpg", .{ stem, suffix });
    defer allocator.free(filename);
    return if (directory) |dir| std.fs.path.join(allocator, &.{ dir, filename }) else allocator.dupe(u8, filename);
}

fn zipNormalize(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    if (!zip.entryPathIsSafe(path)) return error.UnsafeArchivePath;
    var result = std.ArrayList(u8).empty;
    errdefer result.deinit(allocator);
    var start: usize = 0;
    while (start <= path.len) {
        var end = start;
        while (end < path.len and path[end] != '/' and path[end] != '\\') : (end += 1) {}
        const component = path[start..end];
        if (component.len != 0 and !std.mem.eql(u8, component, ".")) {
            if (result.items.len != 0) try result.append(allocator, '/');
            try result.appendSlice(allocator, component);
        }
        if (end == path.len) break;
        start = end + 1;
    }
    return result.toOwnedSlice(allocator);
}

test "archive output names use JPEG" {
    const name = try outputName(std.testing.allocator, "nested/photo.png", "-small");
    defer std.testing.allocator.free(name);
    try std.testing.expectEqualStrings("nested/photo-small.jpg", name);
}
