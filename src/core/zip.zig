const std = @import("std");

const c = @import("miniz");
const kind = @import("kind.zig");
const sort = @import("sort.zig");
const protocol = @import("protocol.zig");

pub const max_entries: usize = 100_000;
pub const max_entry_bytes: u64 = 4 * 1024 * 1024 * 1024;
pub const max_total_bytes: u64 = 16 * 1024 * 1024 * 1024;
pub const max_memory_bytes: usize = 64 * 1024 * 1024;
pub const max_depth: usize = 64;

pub const ImageEntry = struct { name: []const u8, bytes: []const u8 };

pub const Entry = struct {
    name: []u8,
    index: u32,
    is_dir: bool,
    kind: protocol.Kind,
    size: u64,
};

pub fn entryPathIsSafe(path: []const u8) bool {
    if (path.len == 0 or path.len > std.Io.Dir.max_path_bytes or path[0] == '/' or path[0] == '\\') return false;
    if (path.len > 1 and std.ascii.isAlphabetic(path[0]) and path[1] == ':') return false;
    var depth: usize = 0;
    var start: usize = 0;
    while (start <= path.len) {
        var end = start;
        while (end < path.len and path[end] != '/' and path[end] != '\\') : (end += 1) {}
        const component = path[start..end];
        for (component) |byte| if (byte == 0 or byte < 0x20 or byte == 0x7f) return false;
        if (std.mem.eql(u8, component, "..")) return false;
        if (component.len != 0 and !std.mem.eql(u8, component, ".")) {
            depth += 1;
            if (depth > max_depth) return false;
        }
        if (end == path.len) break;
        start = end + 1;
    }
    return depth != 0;
}

fn normalize(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    if (!entryPathIsSafe(path)) return error.UnsafeArchivePath;
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

fn kindFor(name: []const u8) protocol.Kind {
    const extension = std.fs.path.extension(name);
    if (kind.isImageExtension(extension)) return .image;
    return .archive_file;
}

fn zipError(handle: *const c.mz_zip_archive) anyerror {
    return switch (handle.m_last_error) {
        c.MZ_ZIP_UNSUPPORTED_METHOD, c.MZ_ZIP_UNSUPPORTED_FEATURE => error.ZipUnsupportedCompression,
        c.MZ_ZIP_UNSUPPORTED_ENCRYPTION => error.ZipEncrypted,
        c.MZ_ZIP_DECOMPRESSION_FAILED => error.ZipDeflateFailed,
        c.MZ_ZIP_CRC_CHECK_FAILED => error.ZipCrcMismatch,
        c.MZ_ZIP_UNEXPECTED_DECOMPRESSED_SIZE => error.ZipSizeMismatch,
        c.MZ_ZIP_ALLOC_FAILED => error.OutOfMemory,
        c.MZ_ZIP_FILE_OPEN_FAILED, c.MZ_ZIP_FILE_NOT_FOUND => error.SourceNotFound,
        c.MZ_ZIP_FAILED_FINDING_CENTRAL_DIR, c.MZ_ZIP_NOT_AN_ARCHIVE, c.MZ_ZIP_INVALID_HEADER_OR_CORRUPTED => error.InvalidZip,
        else => error.ZipOperationFailed,
    };
}

fn ratioTooLarge(compressed: u64, uncompressed: u64) bool {
    if (uncompressed <= 64 * 1024) return false;
    if (compressed == 0) return true;
    return uncompressed > (std.math.mul(u64, compressed, 1000) catch return true);
}

pub const Archive = struct {
    allocator: std.mem.Allocator,
    handle: *c.mz_zip_archive,
    entries: []Entry,
    file_count: u32,

    pub fn open(allocator: std.mem.Allocator, io: std.Io, path: []const u8) !Archive {
        const stat = std.Io.Dir.cwd().statFile(io, path, .{ .follow_symlinks = false }) catch return error.SourceNotFound;
        if (stat.kind == .sym_link) return error.UnsafeArchive;
        if (stat.kind != .file or stat.size > max_total_bytes or std.mem.indexOfScalar(u8, path, 0) != null) return error.InvalidZip;
        const path_z = try allocator.dupeZ(u8, path);
        defer allocator.free(path_z);
        const handle = try allocator.create(c.mz_zip_archive);
        handle.* = std.mem.zeroes(c.mz_zip_archive);
        errdefer allocator.destroy(handle);
        if (c.mz_zip_reader_init_file(handle, path_z.ptr, 0) == 0) return zipError(handle);
        var ended = false;
        errdefer {
            if (!ended) _ = c.mz_zip_reader_end(handle);
        }

        const count: usize = @intCast(c.mz_zip_reader_get_num_files(handle));
        if (count > max_entries) return error.ArchiveTooManyEntries;
        var entries = std.ArrayList(Entry).empty;
        errdefer {
            for (entries.items) |entry| allocator.free(entry.name);
            entries.deinit(allocator);
        }
        var total: u64 = 0;
        var file_count: u32 = 0;
        for (0..count) |index| {
            var info: c.mz_zip_archive_file_stat = std.mem.zeroes(c.mz_zip_archive_file_stat);
            if (c.mz_zip_reader_file_stat(handle, @intCast(index), &info) == 0) return zipError(handle);
            if (info.m_is_encrypted != 0 or info.m_is_supported == 0) return error.ZipUnsupportedCompression;
            const raw_name = std.mem.span(@as([*:0]const u8, @ptrCast(&info.m_filename)));
            if (raw_name.len == 0 or raw_name.len >= info.m_filename.len) return error.UnsafeArchive;
            const name = try normalize(allocator, raw_name);
            var retained = false;
            defer if (!retained) allocator.free(name);
            if (info.m_uncomp_size > max_entry_bytes) return error.ArchiveEntryTooLarge;
            if (info.m_method == 8 and ratioTooLarge(info.m_comp_size, info.m_uncomp_size)) return error.ArchiveExpansionTooLarge;
            if (total > max_total_bytes -| info.m_uncomp_size) return error.ArchiveTotalTooLarge;
            const is_dir = info.m_is_directory != 0 or raw_name[raw_name.len - 1] == '/';
            try entries.append(allocator, .{ .name = name, .index = @intCast(index), .is_dir = is_dir, .kind = kindFor(name), .size = info.m_uncomp_size });
            retained = true;
            total += info.m_uncomp_size;
            if (!is_dir) file_count += 1;
        }
        const owned_entries = try entries.toOwnedSlice(allocator);
        ended = true;
        return .{ .allocator = allocator, .handle = handle, .entries = owned_entries, .file_count = file_count };
    }

    pub fn deinit(self: *Archive) void {
        for (self.entries) |entry| self.allocator.free(entry.name);
        self.allocator.free(self.entries);
        _ = c.mz_zip_reader_end(self.handle);
        self.allocator.destroy(self.handle);
        self.* = undefined;
    }

    fn less(self: *const Archive, a: usize, b: usize) bool {
        const order = sort.compare(self.entries[a].name, self.entries[b].name);
        return if (order == .eq) a < b else order == .lt;
    }

    pub fn sortedIndices(self: *const Archive, allocator: std.mem.Allocator) ![]usize {
        const indices = try allocator.alloc(usize, self.entries.len);
        for (indices, 0..) |*index, i| index.* = i;
        std.mem.sort(usize, indices, self, less);
        return indices;
    }

    pub fn firstSupportedImage(self: *const Archive) ?*const Entry {
        var first: ?*const Entry = null;
        for (self.entries) |*entry| {
            if (entry.is_dir or entry.kind != .image) continue;
            if (first == null or sort.compare(entry.name, first.?.name) == .lt) first = entry;
        }
        return first;
    }

    pub fn readEntry(self: *const Archive, entry: *const Entry) ![]u8 {
        if (entry.index >= self.entries.len) return error.InvalidZip;
        if (entry.is_dir or entry.size > max_memory_bytes) return error.EntryTooLargeForMemory;
        var size: usize = 0;
        const data = c.mz_zip_reader_extract_to_heap(self.handle, entry.index, &size, 0) orelse return zipError(self.handle);
        defer c.mz_free(data);
        const expected = std.math.cast(usize, entry.size) orelse return error.EntryTooLargeForMemory;
        if (size != expected) return error.ZipSizeMismatch;
        const result = try self.allocator.alloc(u8, size);
        if (size != 0) @memcpy(result, @as([*]const u8, @ptrCast(data))[0..size]);
        return result;
    }
};

pub fn createMemory(allocator: std.mem.Allocator, entries: []const ImageEntry) ![]u8 {
    if (entries.len == 0 or entries.len > max_entries) return error.EmptyArchive;
    var handle: c.mz_zip_archive = std.mem.zeroes(c.mz_zip_archive);
    if (c.mz_zip_writer_init_heap(&handle, 0, 64 * 1024) == 0) return zipError(&handle);
    var active = true;
    errdefer {
        if (active) _ = c.mz_zip_writer_end(&handle);
    }
    var total: u64 = 0;
    for (entries) |entry| {
        const name = try normalize(allocator, entry.name);
        defer allocator.free(name);
        if (entry.bytes.len > max_entry_bytes) return error.ArchiveEntryTooLarge;
        if (total > max_total_bytes -| entry.bytes.len) return error.ArchiveTotalTooLarge;
        const name_z = try allocator.dupeZ(u8, name);
        defer allocator.free(name_z);
        const data: ?*const anyopaque = if (entry.bytes.len == 0) null else @ptrCast(entry.bytes.ptr);
        if (c.mz_zip_writer_add_mem(&handle, name_z.ptr, data, entry.bytes.len, 6) == 0) return zipError(&handle);
        total += entry.bytes.len;
    }
    var output_ptr: ?*anyopaque = null;
    var output_size: usize = 0;
    if (c.mz_zip_writer_finalize_heap_archive(&handle, &output_ptr, &output_size) == 0) return zipError(&handle);
    const output = output_ptr orelse return error.ZipOperationFailed;
    defer c.mz_free(output);
    const result = try allocator.alloc(u8, output_size);
    if (output_size != 0) @memcpy(result, @as([*]const u8, @ptrCast(output))[0..output_size]);
    if (c.mz_zip_writer_end(&handle) == 0) {
        allocator.free(result);
        return zipError(&handle);
    }
    active = false;
    return result;
}
