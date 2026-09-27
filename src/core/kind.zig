const std = @import("std");

const protocol = @import("protocol.zig");

pub const KindError = error{ UnknownType, UnsupportedFileKind };

pub fn isImageExtension(extension: []const u8) bool {
    return std.ascii.eqlIgnoreCase(extension, ".jpg") or
        std.ascii.eqlIgnoreCase(extension, ".jpeg") or
        std.ascii.eqlIgnoreCase(extension, ".png") or
        std.ascii.eqlIgnoreCase(extension, ".bmp") or
        std.ascii.eqlIgnoreCase(extension, ".tga") or
        std.ascii.eqlIgnoreCase(extension, ".webp");
}

pub fn classifyPath(io: std.Io, path: []const u8, stat: std.Io.File.Stat) !protocol.Kind {
    if (stat.kind == .directory) return .directory;
    if (stat.kind != .file) return error.UnsupportedFileKind;

    var header: [12]u8 = undefined;

    const length = readHeader(io, path, &header);
    if (length >= 5 and std.mem.eql(u8, header[0..5], "%PDF-")) return .pdf;
    if (length >= 4 and std.mem.eql(u8, header[0..4], "PK\x03\x04")) return .zip;
    if (length >= 3 and std.mem.eql(u8, header[0..3], "\xff\xd8\xff")) return .image;
    if (length >= 8 and std.mem.eql(u8, header[0..8], "\x89PNG\r\n\x1a\n")) return .image;
    if (length >= 2 and std.mem.eql(u8, header[0..2], "BM")) return .image;
    if (length >= 12 and std.mem.eql(u8, header[0..4], "RIFF") and std.mem.eql(u8, header[8..12], "WEBP")) return .image;

    const extension = std.fs.path.extension(path);
    if (std.ascii.eqlIgnoreCase(extension, ".mp4")) return .video;
    if (std.ascii.eqlIgnoreCase(extension, ".pdf")) return .pdf;
    if (std.ascii.eqlIgnoreCase(extension, ".zip")) return .zip;

    if (isImageExtension(extension)) return .image;

    return error.UnknownType;
}

fn readHeader(io: std.Io, path: []const u8, buffer: []u8) usize {
    var file = std.Io.Dir.cwd().openFile(io, path, .{ .follow_symlinks = false }) catch return 0;
    defer file.close(io);

    return file.readPositional(io, &.{buffer}, 0) catch 0;
}
