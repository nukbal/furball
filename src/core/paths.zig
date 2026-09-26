const std = @import("std");

const protocol = @import("protocol.zig");

pub fn outputDirectory(allocator: std.mem.Allocator, config: protocol.Config, source: []const u8) ![]u8 {
    const directory = if (config.mode == .overwrite) std.fs.path.dirname(source) orelse "." else config.path;
    if (directory.len == 0) return error.MissingOutputDirectory;
    return allocator.dupe(u8, directory);
}

pub fn outputPath(allocator: std.mem.Allocator, config: protocol.Config, source: []const u8, extension: []const u8, collision: usize, is_directory: bool) ![]u8 {
    const directory = try outputDirectory(allocator, config, source);
    defer allocator.free(directory);

    const stem = if (is_directory) std.fs.path.basename(source) else std.fs.path.stem(source);
    if (stem.len == 0 or std.mem.eql(u8, stem, ".") or std.mem.eql(u8, stem, "..")) return error.InvalidSourceName;

    const suffix = if (collision == 0) "" else try std.fmt.allocPrint(allocator, " ({d})", .{collision});
    defer if (collision != 0) allocator.free(suffix);

    const filename = try std.fmt.allocPrint(allocator, "{s}{s}{s}.{s}", .{ stem, config.suffix, suffix, extension });
    defer allocator.free(filename);

    return std.fs.path.join(allocator, &.{ directory, filename });
}

pub fn exists(io: std.Io, path: []const u8) bool {
    std.Io.Dir.cwd().access(io, path, .{}) catch return false;
    return true;
}

pub fn requireOutputDirectory(io: std.Io, path: []const u8) !void {
    const stat = std.Io.Dir.cwd().statFile(io, path, .{}) catch return error.MissingOutputDirectory;
    if (stat.kind != .directory) return error.OutputDirectoryIsFile;
}
