const std = @import("std");

const archive = @import("archive.zig");
const image = @import("image.zig");
const image_batch = @import("image_batch.zig");
const kind = @import("kind.zig");
const sort = @import("sort.zig");
const paths = @import("paths.zig");
const pdf = @import("pdf.zig");
const protocol = @import("protocol.zig");
const realesrgan = @import("realesrgan.zig");
const storage = @import("storage.zig");
const video = @import("video.zig");
const zip = @import("zip.zig");

const max_files: usize = 100_000;
const Allocator = std.mem.Allocator;

pub const OutputList = struct {
    allocator: Allocator,
    values: std.ArrayList([]const u8) = .empty,

    pub fn deinit(self: *OutputList) void {
        for (self.values.items) |value| self.allocator.free(value);
        self.values.deinit(self.allocator);
        self.* = undefined;
    }
};

pub fn inspect(allocator: Allocator, io: std.Io, source: []const u8) !protocol.InspectResponse {
    return inspectNode(allocator, io, source, 0);
}

fn inspectNode(allocator: Allocator, io: std.Io, source: []const u8, depth: usize) anyerror!protocol.InspectResponse {
    if (depth > 64) return error.DirectoryTooDeep;

    const stat = std.Io.Dir.cwd().statFile(io, source, .{ .follow_symlinks = false }) catch return error.SourceNotFound;
    if (stat.kind == .sym_link) return error.UnsupportedSymlink;

    const file_kind = try kind.classifyPath(io, source, stat);
    const owned_path = try allocator.dupe(u8, source);
    const owned_name = allocator.dupe(u8, std.fs.path.basename(source)) catch |err| {
        allocator.free(owned_path);
        return err;
    };

    var result = protocol.InspectResponse{
        .path = owned_path,
        .name = owned_name,
        .kind = file_kind,
        .size = stat.size,
    };
    errdefer freeResponse(allocator, &result);

    switch (file_kind) {
        .directory => {
            result.children = try inspectDirectory(allocator, io, source, depth + 1);
            result.size = 0;
            for (result.children) |child| {
                result.count += imageCount(child);
                result.size += child.size;
            }

            for (result.children) |child| {
                if (child.thumbnail) |thumbnail| {
                    result.thumbnail = try allocator.dupe(u8, thumbnail);
                    break;
                }
                if (child.thumbnail_blob) |blob| {
                    result.thumbnail_blob = try allocator.dupe(u8, blob);
                    break;
                }
            }
        },
        .image => {
            _ = try image.dimensions(allocator, io, source);
            result.thumbnail = try allocator.dupe(u8, source);
        },
        .pdf => {
            result.count = pdf.imageCount(allocator, source) catch return error.InvalidPdf;
            if (try pdf.thumbnailBytes(allocator, source)) |thumbnail| {
                defer allocator.free(thumbnail);
                result.thumbnail_blob = try encodeThumbnail(allocator, thumbnail);
            }
        },
        .zip => {
            var parsed = try zip.Archive.open(allocator, io, source);
            defer parsed.deinit();

            result.count = 0;
            for (parsed.entries) |entry| {
                if (!entry.is_dir and entry.kind == .image) result.count +|= 1;
            }
            result.children = try archiveChildren(allocator, source, &parsed);

            if (parsed.firstSupportedImage()) |entry| {
                const bytes = try parsed.readEntry(entry);
                defer allocator.free(bytes);

                const thumbnail = try image.thumbnailBytes(allocator, bytes);
                defer allocator.free(thumbnail);

                result.thumbnail_blob = try encodeThumbnail(allocator, thumbnail);
            }
        },
        else => {},
    }
    return result;
}

fn inspectDirectory(allocator: Allocator, io: std.Io, source: []const u8, depth: usize) anyerror![]protocol.InspectNode {
    var directory = try std.Io.Dir.cwd().openDir(io, source, .{ .iterate = true, .follow_symlinks = false });
    defer directory.close(io);

    var iterator = directory.iterate();
    var nodes = std.ArrayList(protocol.InspectNode).empty;
    errdefer {
        for (nodes.items) |node| freeNode(allocator, node);
        nodes.deinit(allocator);
    }

    while (try iterator.next(io)) |entry| {
        if (nodes.items.len >= max_files) return error.TooManyFiles;
        if (entry.kind == .sym_link or (entry.kind != .file and entry.kind != .directory)) continue;

        const child_path = try std.fs.path.join(allocator, &.{ source, entry.name });
        defer allocator.free(child_path);

        const child_stat = std.Io.Dir.cwd().statFile(io, child_path, .{ .follow_symlinks = false }) catch continue;
        const child_kind = kind.classifyPath(io, child_path, child_stat) catch |err| switch (err) {
            error.UnknownType, error.UnsupportedFileKind => continue,
        };

        if (child_kind != .image and child_kind != .directory) continue;

        const child = inspectNode(allocator, io, child_path, depth) catch |err| switch (err) {
            error.UnknownType, error.UnsupportedFileKind, error.SourceNotFound, error.UnsupportedSymlink, error.ImageDecodeFailed, error.InvalidImage, error.ImageDimensionsTooLarge, error.ImagePixelsTooLarge, error.ImageAllocationTooLarge, error.ImageInputTooLarge, error.ImageReadFailed => continue,
            else => return err,
        };
        if (child.kind != .image and child.kind != .directory) {
            freeNode(allocator, child);
            continue;
        }
        if (child.kind == .directory and child.count == 0) {
            freeNode(allocator, child);
            continue;
        }
        nodes.append(allocator, child) catch |err| {
            freeNode(allocator, child);
            return err;
        };
    }
    std.mem.sort(protocol.InspectNode, nodes.items, {}, lessNode);
    return nodes.toOwnedSlice(allocator);
}

fn imageCount(node: protocol.InspectNode) u32 {
    if (node.kind == .image) return 1;
    var count: u32 = 0;
    for (node.children) |child| count +|= imageCount(child);
    return count;
}

fn archiveChildren(allocator: Allocator, source: []const u8, parsed: *const zip.Archive) ![]protocol.InspectNode {
    const indices = try parsed.sortedIndices(allocator);
    defer allocator.free(indices);

    const children = try allocator.alloc(protocol.InspectNode, indices.len);
    var built: usize = 0;
    errdefer {
        for (children[0..built]) |node| freeNode(allocator, node);
        allocator.free(children);
    }

    for (indices) |index| {
        const entry = parsed.entries[index];
        const child_path = try std.fmt.allocPrint(allocator, "zip://{s}!/{s}", .{ source, entry.name });
        const child_name = allocator.dupe(u8, entry.name) catch |err| {
            allocator.free(child_path);
            return err;
        };
        children[built] = .{
            .path = child_path,
            .name = child_name,
            .kind = if (entry.is_dir) .directory else entry.kind,
            .size = entry.size,
            .count = if (entry.is_dir) 0 else 1,
        };
        built += 1;
    }

    return children;
}

fn encodeThumbnail(allocator: Allocator, bytes: []const u8) ![]u8 {
    if (bytes.len > protocol.max_thumbnail_blob_bytes) return error.ThumbnailTooLarge;

    const length = std.base64.standard.Encoder.calcSize(bytes.len);
    if (length > protocol.max_thumbnail_blob_base64_bytes) return error.ThumbnailTooLarge;

    const encoded = try allocator.alloc(u8, length);
    _ = std.base64.standard.Encoder.encode(encoded, bytes);

    return encoded;
}

fn lessNode(_: void, a: protocol.InspectNode, b: protocol.InspectNode) bool {
    if (a.kind == .directory and b.kind != .directory) return true;
    if (b.kind == .directory and a.kind != .directory) return false;
    return sort.compare(a.name, b.name) == .lt;
}

pub fn freeResponse(allocator: Allocator, response: *protocol.InspectResponse) void {
    freeNode(allocator, response.*);
    response.* = undefined;
}

fn freeNode(allocator: Allocator, node: protocol.InspectNode) void {
    allocator.free(node.path);
    allocator.free(node.name);
    if (node.thumbnail) |thumbnail| allocator.free(thumbnail);
    if (node.thumbnail_blob) |blob| allocator.free(blob);
    for (node.children) |child| freeNode(allocator, child);
    if (node.children.len != 0) allocator.free(node.children);
}

pub fn process(
    allocator: Allocator,
    io: std.Io,
    config: protocol.Config,
    source: []const u8,
    progress: ?protocol.Progress,
) !OutputList {
    try protocol.validateConfig(config);

    const stat = std.Io.Dir.cwd().statFile(io, source, .{ .follow_symlinks = false }) catch return error.SourceNotFound;

    if (stat.kind == .sym_link) return error.UnsupportedSymlink;

    var outputs = OutputList{ .allocator = allocator };
    errdefer outputs.deinit();

    switch (try kind.classifyPath(io, source, stat)) {
        .image => try processImage(allocator, io, source, config, &outputs, progress),
        .video => try processVideo(allocator, io, source, config, &outputs, progress),
        .directory => try processDirectory(allocator, io, source, config, &outputs, progress),
        .zip => try processZip(allocator, io, source, config, &outputs, progress),
        .pdf => try processPdf(allocator, io, source, config, &outputs, progress),
        .archive_file => return error.UnsupportedSource,
    }

    if (outputs.values.items.len == 0) return error.NoProcessableFiles;

    return outputs;
}

fn processImage(
    allocator: Allocator,
    io: std.Io,
    source: []const u8,
    config: protocol.Config,
    outputs: *OutputList,
    progress: ?protocol.Progress,
) !void {
    const destination = try target(allocator, io, source, config, "jpg");
    defer allocator.free(destination);

    try convertImage(allocator, io, source, destination, config);

    try appendOutput(allocator, outputs, destination);
    if (progress) |reporter| reporter.advance();
}

fn processPdf(
    allocator: Allocator,
    io: std.Io,
    source: []const u8,
    config: protocol.Config,
    outputs: *OutputList,
    progress: ?protocol.Progress,
) !void {
    const destination = try target(allocator, io, source, config, "pdf");
    defer allocator.free(destination);

    try pdf.toPdfFromFile(allocator, io, source, destination, config, progress);
    try appendOutput(allocator, outputs, destination);
}

fn convertImage(alloc: Allocator, io: std.Io, source: []const u8, destination: []const u8, config: protocol.Config) !void {
    const bytes = try image.encodeBytes(alloc, io, source, config, 0);
    defer alloc.free(bytes);

    try storage.writeAtomic(io, destination, bytes);
}

const max_parallel_images: usize = 8;

const ImageTask = struct {
    allocator: Allocator,
    io: std.Io,
    source: []const u8,
    destination: []const u8,
    config: protocol.Config,
    failure: ?anyerror = null,

    fn run(task: *ImageTask) std.Io.Cancelable!void {
        convertImage(task.allocator, task.io, task.source, task.destination, task.config) catch |err| {
            task.failure = err;
            if (err == error.Canceled) return error.Canceled;
            return;
        };
    }
};

fn processImagesInParallel(
    allocator: Allocator,
    io: std.Io,
    entries: []const archive.FileEntry,
    config: protocol.Config,
    outputs: *OutputList,
    progress: ?protocol.Progress,
) !void {
    var tasks = std.ArrayList(ImageTask).empty;
    defer {
        for (tasks.items) |task| allocator.free(task.destination);
        tasks.deinit(allocator);
    }

    for (entries) |entry| {
        if (entry.kind != .image) continue;

        const destination = try targetForBatch(allocator, io, entry.source, config, "jpg", tasks.items);
        tasks.append(allocator, .{
            .allocator = allocator,
            .io = io,
            .source = entry.source,
            .destination = destination,
            .config = config,
        }) catch |err| {
            allocator.free(destination);
            return err;
        };
    }

    if (tasks.items.len == 0) return;

    const worker_count = @max(@as(usize, 1), @min(std.Thread.getCpuCount() catch 1, max_parallel_images));
    var first = @as(usize, 0);
    while (first < tasks.items.len) {
        const last = @min(tasks.items.len, first + worker_count);
        var group: std.Io.Group = .init;
        for (tasks.items[first..last]) |*task| {
            group.concurrent(io, ImageTask.run, .{task}) catch |err| {
                group.cancel(io);
                return err;
            };
        }
        group.await(io) catch |err| {
            group.cancel(io);
            return err;
        };
        for (tasks.items[first..last]) |task| {
            if (task.failure) |err| return err;
            if (progress) |reporter| reporter.advance();
        }
        first = last;
    }

    for (tasks.items) |task| try appendOutput(allocator, outputs, task.destination);
}

fn targetForBatch(
    allocator: Allocator,
    io: std.Io,
    source: []const u8,
    config: protocol.Config,
    extension: []const u8,
    tasks: []const ImageTask,
) ![]u8 {
    const directory = try paths.outputDirectory(allocator, config, source);
    defer allocator.free(directory);
    try paths.requireOutputDirectory(io, directory);

    var collision: usize = 0;
    while (true) : (collision += 1) {
        const candidate = try paths.outputPath(allocator, config, source, extension, collision);
        if (!containsDestination(tasks, candidate) and (config.mode == .overwrite or !paths.exists(io, candidate))) return candidate;
        allocator.free(candidate);
        if (collision >= 100_000) return error.TooManyCollisions;
    }
}

fn containsDestination(tasks: []const ImageTask, candidate: []const u8) bool {
    for (tasks) |task| if (std.mem.eql(u8, task.destination, candidate)) return true;
    return false;
}

fn processVideo(allocator: Allocator, io: std.Io, source: []const u8, config: protocol.Config, outputs: *OutputList, progress: ?protocol.Progress) !void {
    const destination = try target(allocator, io, source, config, "gif");
    defer allocator.free(destination);

    try video.convertMp4ToGif(allocator, io, source, destination);

    try appendOutput(allocator, outputs, destination);
    if (progress) |reporter| reporter.advance();
}

fn processZip(
    allocator: Allocator,
    io: std.Io,
    source: []const u8,
    config: protocol.Config,
    outputs: *OutputList,
    progress: ?protocol.Progress,
) !void {
    if (config.dir_mode != .pdf) return error.UnsupportedSource;

    var parsed = try zip.Archive.open(allocator, io, source);
    defer parsed.deinit();

    const indices = try parsed.sortedIndices(allocator);
    defer allocator.free(indices);

    var inputs = std.ArrayList(image_batch.Source).empty;
    defer inputs.deinit(allocator);
    var owned_inputs = std.ArrayList([]u8).empty;
    defer {
        for (owned_inputs.items) |input| allocator.free(input);
        owned_inputs.deinit(allocator);
    }

    for (indices) |index| {
        const entry = &parsed.entries[index];
        if (entry.is_dir or entry.kind != .image) continue;

        const input = try parsed.readEntry(entry);
        owned_inputs.append(allocator, input) catch |err| {
            allocator.free(input);
            return err;
        };
        inputs.append(allocator, .{ .encoded = input }) catch |err| return err;
    }
    if (inputs.items.len == 0) return error.EmptyArchive;

    const results = try image_batch.process(allocator, io, inputs.items, config, progress);
    defer image_batch.freeResults(allocator, results);

    const pages = try allocator.alloc(pdf.Page, results.len);
    defer allocator.free(pages);
    for (pages, results) |*page, result| {
        page.* = .{ .bytes = result.bytes, .width = result.width, .height = result.height };
    }

    const destination = try target(allocator, io, source, config, "pdf");
    defer allocator.free(destination);
    try pdf.createFromJpegs(allocator, io, pages, destination);
    try appendOutput(allocator, outputs, destination);
}

fn processDirectory(
    allocator: Allocator,
    io: std.Io,
    source: []const u8,
    config: protocol.Config,
    outputs: *OutputList,
    progress: ?protocol.Progress,
) !void {
    var entries = try collectDirectory(allocator, io, source);
    defer entries.deinit(allocator);

    std.mem.sort(archive.FileEntry, entries.items, {}, lessFileEntry);

    if (config.dir_mode == .none) {
        try processImagesInParallel(allocator, io, entries.items, config, outputs, progress);
        return;
    }

    const extension = if (config.dir_mode == .pdf) "pdf" else "zip";
    const destination = try target(allocator, io, source, config, extension);
    defer allocator.free(destination);

    if (config.dir_mode == .pdf) {
        var sources = std.ArrayList([]const u8).empty;
        defer sources.deinit(allocator);

        for (entries.items) |entry| if (entry.kind == .image) try sources.append(allocator, entry.source);
        if (sources.items.len == 0) return error.EmptyDirectory;

        try pdf.toPdf(allocator, io, sources.items, destination, config, progress);
    } else {
        try archive.createZip(allocator, io, entries.items, destination, config, progress);
    }

    try appendOutput(allocator, outputs, destination);
}

const EntryList = struct {
    items: []archive.FileEntry,

    fn deinit(self: *EntryList, allocator: Allocator) void {
        for (self.items) |entry| {
            allocator.free(entry.source);
            allocator.free(entry.relative);
        }
        allocator.free(self.items);
        self.* = undefined;
    }
};

fn collectDirectory(allocator: Allocator, io: std.Io, root: []const u8) !EntryList {
    var directory = try std.Io.Dir.cwd().openDir(io, root, .{ .iterate = true, .follow_symlinks = false });
    defer directory.close(io);
    var walker = try directory.walk(allocator);
    defer walker.deinit();
    var list = std.ArrayList(archive.FileEntry).empty;
    errdefer {
        for (list.items) |entry| {
            allocator.free(entry.source);
            allocator.free(entry.relative);
        }
        list.deinit(allocator);
    }

    while (try walker.next(io)) |entry| {
        if (list.items.len >= max_files or entry.kind != .file) continue;
        const source = try std.fs.path.join(allocator, &.{ root, entry.path });
        const stat = std.Io.Dir.cwd().statFile(io, source, .{ .follow_symlinks = false }) catch |err| {
            allocator.free(source);
            return err;
        };
        const file_kind = kind.classifyPath(io, source, stat) catch {
            allocator.free(source);
            continue;
        };
        if (file_kind != .image) {
            allocator.free(source);
            continue;
        }
        _ = image.dimensions(allocator, io, source) catch |err| switch (err) {
            error.ImageDecodeFailed, error.InvalidImage, error.ImageDimensionsTooLarge, error.ImagePixelsTooLarge, error.ImageAllocationTooLarge, error.ImageInputTooLarge, error.SourceNotFound, error.ImageReadFailed => {
                allocator.free(source);
                continue;
            },
            else => return err,
        };
        const relative = allocator.dupe(u8, entry.path) catch |err| {
            allocator.free(source);
            return err;
        };
        list.append(allocator, .{ .source = source, .relative = relative, .kind = file_kind }) catch |err| {
            allocator.free(source);
            allocator.free(relative);
            return err;
        };
    }

    return .{ .items = try list.toOwnedSlice(allocator) };
}

fn lessFileEntry(_: void, a: archive.FileEntry, b: archive.FileEntry) bool {
    return sort.compare(a.relative, b.relative) == .lt;
}

fn target(allocator: Allocator, io: std.Io, source: []const u8, config: protocol.Config, extension: []const u8) ![]u8 {
    const directory = try paths.outputDirectory(allocator, config, source);
    defer allocator.free(directory);

    try paths.requireOutputDirectory(io, directory);

    var collision: usize = 0;

    while (true) : (collision += 1) {
        const candidate = try paths.outputPath(allocator, config, source, extension, collision);

        if (config.mode == .overwrite or !paths.exists(io, candidate)) return candidate;
        allocator.free(candidate);

        if (collision >= 100_000) return error.TooManyCollisions;
    }
}

fn appendOutput(allocator: Allocator, outputs: *OutputList, path: []const u8) !void {
    const owned = try allocator.dupe(u8, path);
    errdefer allocator.free(owned);

    try outputs.values.append(allocator, owned);
}
