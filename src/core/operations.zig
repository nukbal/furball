const std = @import("std");

const archive = @import("archive.zig");
const image = @import("image.zig");
const image_batch = @import("image_batch.zig");
const kind = @import("kind.zig");
const sort = @import("sort.zig");
const paths = @import("paths.zig");
const pdf = @import("pdf.zig");
const protocol = @import("protocol.zig");
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

            if (firstImageNode(result.children)) |first| {
                if (first.thumbnail) |thumbnail| {
                    result.thumbnail = try allocator.dupe(u8, thumbnail);
                } else if (first.thumbnail_blob) |blob| {
                    result.thumbnail_blob = try allocator.dupe(u8, blob);
                }
            }
        },
        .image => {
            _ = try image.dimensions(allocator, io, source);
            result.thumbnail = try allocator.dupe(u8, source);
        },
        .pdf => {
            result.count = pdf.pageCount(allocator, source) catch return error.InvalidPdf;
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

fn firstImageNode(nodes: []const protocol.InspectNode) ?*const protocol.InspectNode {
    var first: ?*const protocol.InspectNode = null;
    for (nodes) |*node| {
        var candidate: ?*const protocol.InspectNode = null;
        if (node.kind == .image) {
            candidate = node;
        } else if (node.kind == .directory) {
            candidate = firstImageNode(node.children);
        }
        if (candidate) |image_node| {
            if (first == null or sort.compare(image_node.path, first.?.path) == .lt) first = image_node;
        }
    }
    return first;
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

    const file_kind = try kind.classifyPath(io, source, stat);
    var sources = std.ArrayList(protocol.Source).empty;
    defer sources.deinit(allocator);
    var page_names = std.ArrayList([]u8).empty;
    defer {
        for (page_names.items) |name| allocator.free(name);
        page_names.deinit(allocator);
    }
    var directory_entries: ?EntryList = null;
    defer if (directory_entries) |*entries| entries.deinit(allocator);

    switch (file_kind) {
        .directory => {
            directory_entries = try collectDirectory(allocator, io, source);
            const entries = &directory_entries.?;
            std.mem.sort(archive.FileEntry, entries.items, {}, lessFileEntry);
            for (entries.items) |entry| {
                try sources.append(allocator, .{
                    .path = entry.source,
                    .name = entry.relative,
                    .root = source,
                    .kind = .image,
                });
            }
            if (sources.items.len == 0) return error.EmptyDirectory;
        },
        .pdf => {
            const page_count = try pdf.pageCount(allocator, source);
            if (page_count == 0) return error.EmptyPdf;
            for (0..page_count) |page_index| {
                const name = try std.fmt.allocPrint(allocator, "{d}", .{page_index + 1});
                page_names.append(allocator, name) catch |err| {
                    allocator.free(name);
                    return err;
                };
                try sources.append(allocator, .{
                    .path = source,
                    .name = name,
                    .root = source,
                    .kind = .pdf,
                    .page_index = @intCast(page_index),
                });
            }
        },
        else => try sources.append(allocator, .{
            .path = source,
            .name = std.fs.path.basename(source),
            .root = source,
            .kind = file_kind,
        }),
    }

    return processSources(allocator, io, config, sources.items, progress);
}

const ImageInput = struct {
    metadata: protocol.Source,
    source: image_batch.Source,
    owned: ?[]u8 = null,

    fn deinit(self: *ImageInput, allocator: Allocator) void {
        if (self.owned) |bytes| allocator.free(bytes);
        self.* = undefined;
    }
};

pub fn processSources(
    allocator: Allocator,
    io: std.Io,
    config: protocol.Config,
    sources: []const protocol.Source,
    progress: ?protocol.Progress,
) !OutputList {
    try protocol.validateConfig(config);
    if (sources.len == 0) return error.InvalidBatch;

    var outputs = OutputList{ .allocator = allocator };
    errdefer outputs.deinit();

    var images = std.ArrayList(ImageInput).empty;
    defer {
        for (images.items) |*input| input.deinit(allocator);
        images.deinit(allocator);
    }
    var other_sources = std.ArrayList(protocol.Source).empty;
    defer other_sources.deinit(allocator);

    var pdf_root: ?[]const u8 = null;
    for (sources) |source| {
        if (source.kind != .pdf) continue;
        if (source.page_index == null) return error.InvalidPdfPage;
        if (pdf_root) |root| {
            if (!std.mem.eql(u8, root, source.root)) return error.PdfBatchNotAllowed;
        } else {
            pdf_root = source.root;
        }
    }
    if (pdf_root != null) {
        for (sources) |source| if (source.kind != .pdf) return error.PdfBatchNotAllowed;
    }

    for (sources) |source| {
        if (source.path.len == 0 or source.name.len == 0 or source.root.len == 0) return error.InvalidSource;
        switch (source.kind) {
            .image, .pdf => try appendImageInput(allocator, io, source, &images),
            else => try other_sources.append(allocator, source),
        }
    }

    const has_pdf_page = pdf_root != null;

    if (images.items.len != 0) {
        const grouped = config.dir_mode != .none and (images.items.len > 1 or has_pdf_page);
        if (grouped) {
            try processImageBatch(allocator, io, config, images.items, &outputs, progress);
        } else {
            for (images.items) |input| try processImageInput(allocator, io, config, input, &outputs, progress);
        }
    }

    for (other_sources.items) |source| {
        switch (source.kind) {
            .video => try processVideo(allocator, io, source.path, config, &outputs, progress),
            .zip => try processZip(allocator, io, source.path, config, &outputs, progress),
            else => return error.UnsupportedSource,
        }
    }

    if (outputs.values.items.len == 0) return error.NoProcessableFiles;
    return outputs;
}

fn appendImageInput(
    allocator: Allocator,
    io: std.Io,
    source: protocol.Source,
    inputs: *std.ArrayList(ImageInput),
) !void {
    if (source.kind == .image) {
        try inputs.append(allocator, .{ .metadata = source, .source = .{ .file = source.path } });
        return;
    }

    const page_index = source.page_index orelse return error.InvalidPdfPage;
    var page = try pdf.extractPage(allocator, io, source.path, page_index);
    const input = ImageInput{ .metadata = source, .source = page.source(), .owned = page.bytes };
    page.bytes = &.{};
    inputs.append(allocator, input) catch |err| {
        allocator.free(input.owned.?);
        return err;
    };
}

fn processImageInput(
    allocator: Allocator,
    io: std.Io,
    config: protocol.Config,
    input: ImageInput,
    outputs: *OutputList,
    progress: ?protocol.Progress,
) !void {
    const sources = [_]image_batch.Source{input.source};
    const results = try image_batch.process(allocator, io, &sources, config, progress);
    defer image_batch.freeResults(allocator, results);

    const destination = try targetForSource(allocator, io, input.metadata, config, "jpg", outputs.values.items);
    defer allocator.free(destination);
    try storage.writeAtomic(io, destination, results[0].bytes);
    try appendOutput(allocator, outputs, destination);
}

fn processImageBatch(
    allocator: Allocator,
    io: std.Io,
    config: protocol.Config,
    inputs: []const ImageInput,
    outputs: *OutputList,
    progress: ?protocol.Progress,
) !void {
    const sources = try allocator.alloc(image_batch.Source, inputs.len);
    defer allocator.free(sources);
    const names = try allocator.alloc([]const u8, inputs.len);
    defer allocator.free(names);
    for (sources, names, inputs) |*source, *name, input| {
        source.* = input.source;
        name.* = input.metadata.name;
    }

    const results = try image_batch.process(allocator, io, sources, config, progress);
    defer image_batch.freeResults(allocator, results);

    const root = inputs[0].metadata.root;
    const extension = if (config.dir_mode == .pdf) "pdf" else "zip";
    const destination = try target(allocator, io, root, config, extension);
    defer allocator.free(destination);

    if (config.dir_mode == .pdf) {
        const pages = try allocator.alloc(pdf.Page, results.len);
        defer allocator.free(pages);
        for (pages, results) |*page, result| {
            page.* = .{ .bytes = result.bytes, .width = result.width, .height = result.height };
        }
        try pdf.createFromJpegs(allocator, io, pages, destination);
    } else {
        try archive.createZipFromResults(allocator, io, names, results, config.suffix, destination);
    }

    try appendOutput(allocator, outputs, destination);
}

fn targetForSource(
    allocator: Allocator,
    io: std.Io,
    source: protocol.Source,
    config: protocol.Config,
    extension: []const u8,
    used: []const []const u8,
) ![]u8 {
    const directory = try paths.outputDirectory(allocator, config, source.root);
    defer allocator.free(directory);
    try paths.requireOutputDirectory(io, directory);

    const stem = std.fs.path.stem(std.fs.path.basename(source.name));
    if (stem.len == 0) return error.InvalidSourceName;

    var collision: usize = 0;
    while (true) : (collision += 1) {
        const suffix = if (collision == 0) "" else try std.fmt.allocPrint(allocator, " ({d})", .{collision});
        defer if (collision != 0) allocator.free(suffix);
        const filename = try std.fmt.allocPrint(allocator, "{s}{s}{s}.{s}", .{ stem, config.suffix, suffix, extension });
        defer allocator.free(filename);
        const candidate = try std.fs.path.join(allocator, &.{ directory, filename });
        if ((config.mode == .overwrite or (!paths.exists(io, candidate) and !containsOutput(used, candidate)))) return candidate;
        allocator.free(candidate);
        if (collision >= 100_000) return error.TooManyCollisions;
    }
}

fn containsOutput(outputs: []const []const u8, candidate: []const u8) bool {
    for (outputs) |output| if (std.mem.eql(u8, output, candidate)) return true;
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
    const stat = try std.Io.Dir.cwd().statFile(io, source, .{});

    var collision: usize = 0;

    while (true) : (collision += 1) {
        const candidate = try paths.outputPath(allocator, config, source, extension, collision, stat.kind == .directory);

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
