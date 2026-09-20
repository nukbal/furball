const std = @import("std");

pub const Mode = enum { path, overwrite };
pub const DirMode = enum { none, pdf, zip };
pub const Kind = enum { image, video, pdf, zip, directory, archive_file };

pub const max_thumbnail_blob_bytes: usize = 192 * 1024;
pub const max_thumbnail_blob_base64_bytes: usize = 256 * 1024;

pub const Progress = struct {
    context: *anyopaque,
    advance_fn: *const fn (*anyopaque) void,

    pub fn advance(progress: Progress) void {
        progress.advance_fn(progress.context);
    }
};

pub const Config = struct {
    mode: Mode = .path,
    path: []const u8 = "",
    suffix: []const u8 = "",
    width: u32 = 1440,
    quality: u8 = 85,
    ai: bool = false,
    dir_mode: DirMode = .none,
};

pub const InspectNode = struct {
    path: []const u8,
    name: []const u8,
    kind: Kind,
    size: u64,
    count: u32 = 0,
    thumbnail: ?[]const u8 = null,
    thumbnail_blob: ?[]const u8 = null,
    children: []const InspectNode = &.{},
};

pub const InspectResponse = InspectNode;

pub const ConfigError = error{ InvalidPath, InvalidSuffix, InvalidWidth, InvalidQuality };

pub fn validateConfig(config: Config) ConfigError!void {
    if (config.mode == .path and config.path.len == 0) return error.InvalidPath;
    if (std.mem.indexOfScalar(u8, config.path, 0) != null) return error.InvalidPath;
    if (config.width == 0 or config.width > 1_000_000) return error.InvalidWidth;
    if (config.quality > 100) return error.InvalidQuality;
    if (config.suffix.len > 128) return error.InvalidSuffix;
    for (config.suffix) |byte| if (byte == 0 or byte == '/' or byte == '\\' or byte < 0x20 or byte == 0x7f) return error.InvalidSuffix;
}

pub fn parseConfig(allocator: std.mem.Allocator, source: []const u8) !std.json.Parsed(Config) {
    var parsed = try std.json.parseFromSlice(Config, allocator, source, .{ .ignore_unknown_fields = false });
    errdefer parsed.deinit();

    try validateConfig(parsed.value);

    return parsed;
}

pub fn stringify(allocator: std.mem.Allocator, value: anytype) ![]u8 {
    var output = std.Io.Writer.Allocating.init(allocator);
    errdefer output.deinit();

    try std.json.Stringify.value(value, .{}, &output.writer);

    return output.toOwnedSlice();
}
