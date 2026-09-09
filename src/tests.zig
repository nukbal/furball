const std = @import("std");

const image = @import("core/image.zig");
const main = @import("main.zig");
const operations = @import("core/operations.zig");
const pdf = @import("core/pdf.zig");
const protocol = @import("core/protocol.zig");
const zip = @import("core/zip.zig");

const png_base64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=";

fn fixturePng(allocator: std.mem.Allocator) ![]u8 {
    const size = std.base64.standard.Decoder.calcSizeForSlice(png_base64) catch unreachable;
    const result = try allocator.alloc(u8, size);
    errdefer allocator.free(result);
    try std.base64.standard.Decoder.decode(result, png_base64);
    return result;
}

fn fixtureJpeg(allocator: std.mem.Allocator) ![]u8 {
    const png = try fixturePng(allocator);
    defer allocator.free(png);
    return (image.Processor{ .allocator = allocator, .io = std.testing.io }).encodeBytesFromMemory(png, .{ .width = 1, .quality = 80, .ai = false });
}

fn testPath(tmp: *std.testing.TmpDir, allocator: std.mem.Allocator, name: []const u8) ![]u8 {
    return std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/{s}", .{ tmp.sub_path, name });
}

test "fixed image pipeline never upscales without AI" {
    const allocator = std.testing.allocator;
    const png = try fixturePng(allocator);
    defer allocator.free(png);
    const output = try (image.Processor{ .allocator = allocator, .io = std.testing.io }).encodeBytesFromMemory(png, .{ .width = 1440, .quality = 80, .ai = false });
    defer allocator.free(output);
    const dimensions = try image.inspectMemory(output);
    try std.testing.expectEqual(@as(u32, 1), dimensions.width);
    try std.testing.expectEqual(@as(u32, 1), dimensions.height);
}

test "AI upscale reports unavailable without a backend" {
    const allocator = std.testing.allocator;
    const png = try fixturePng(allocator);
    defer allocator.free(png);
    try std.testing.expectError(
        error.AiUnavailable,
        (image.Processor{ .allocator = allocator, .io = std.testing.io }).encodeBytesFromMemory(png, .{ .width = 1440, .quality = 80, .ai = true }),
    );
}

test "model config contains only fixed processing controls" {
    var model = main.Model{};
    var effects = main.Effects.init(std.testing.allocator);
    defer effects.deinit();
    effects.executor = .fake;
    main.update(&model, .toggle_ai, &effects);
    main.update(&model, .dir_pdf, &effects);
    try std.testing.expect(model.config.ai);
    try std.testing.expectEqual(protocol.DirMode.pdf, model.config.dir_mode);
    try std.testing.expectEqual(@as(u32, 1440), model.config.width);
}

test "zip memory writer round trips natural first image" {
    const allocator = std.testing.allocator;
    const jpeg = try fixtureJpeg(allocator);
    defer allocator.free(jpeg);
    const entries = [_]zip.ImageEntry{
        .{ .name = "page10.jpg", .bytes = jpeg },
        .{ .name = "notes.txt", .bytes = "ignored" },
        .{ .name = "page2.jpg", .bytes = jpeg },
    };
    const bytes = try zip.createMemory(allocator, &entries);
    defer allocator.free(bytes);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const path = try testPath(&tmp, allocator, "images.zip");
    defer allocator.free(path);
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "images.zip", .data = bytes });

    var archive = try zip.Archive.open(allocator, std.testing.io, path);
    defer archive.deinit();
    const first = archive.firstSupportedImage() orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("page2.jpg", first.name);
    const extracted = try archive.readEntry(first);
    defer allocator.free(extracted);
    try std.testing.expectEqualSlices(u8, jpeg, extracted);
}

test "zip input converts naturally sorted images to a PDF" {
    const allocator = std.testing.allocator;
    const jpeg = try fixtureJpeg(allocator);
    defer allocator.free(jpeg);
    const entries = [_]zip.ImageEntry{
        .{ .name = "page10.jpg", .bytes = jpeg },
        .{ .name = "notes.txt", .bytes = "ignored" },
        .{ .name = "page2.jpg", .bytes = jpeg },
    };
    const archive_bytes = try zip.createMemory(allocator, &entries);
    defer allocator.free(archive_bytes);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const archive_path = try testPath(&tmp, allocator, "images.zip");
    defer allocator.free(archive_path);
    const output_directory = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}", .{tmp.sub_path});
    defer allocator.free(output_directory);
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "images.zip", .data = archive_bytes });

    var outputs = try operations.process(allocator, std.testing.io, .{
        .mode = .path,
        .path = output_directory,
        .width = 1,
        .quality = 80,
        .dir_mode = .pdf,
    }, archive_path);
    defer outputs.deinit();
    try std.testing.expectEqual(@as(usize, 1), outputs.values.items.len);

    const pdf_path = outputs.values.items[0];
    const expected_pdf_path = try std.fs.path.join(allocator, &.{ output_directory, "images.pdf" });
    defer allocator.free(expected_pdf_path);
    try std.testing.expectEqualStrings(expected_pdf_path, pdf_path);
    const processor = pdf.Processor{ .allocator = allocator, .io = std.testing.io };
    try std.testing.expectEqual(@as(u32, 2), try processor.pageCount(pdf_path));
    var extracted = (try processor.firstJpeg(pdf_path)) orelse return error.TestUnexpectedResult;
    defer extracted.deinit();
    try std.testing.expectEqual(@as(u32, 1), extracted.width);
    try std.testing.expectEqual(@as(u32, 1), extracted.height);
    try std.testing.expectEqualSlices(u8, jpeg, extracted.bytes);
}

test "zip writer rejects unsafe names" {
    const allocator = std.testing.allocator;
    const entries = [_]zip.ImageEntry{.{ .name = "../escape.jpg", .bytes = "bytes" }};
    try std.testing.expectError(error.UnsafeArchivePath, zip.createMemory(allocator, &entries));
}

test "zip path limits reject traversal" {
    try std.testing.expect(!zip.entryPathIsSafe("../escape.jpg"));
    try std.testing.expect(!zip.entryPathIsSafe("folder/../../escape.jpg"));
    try std.testing.expect(zip.entryPathIsSafe("folder\\image.jpg"));
}

test "pdf writer creates pages and extracts first JPEG XObject" {
    const allocator = std.testing.allocator;
    const jpeg = try fixtureJpeg(allocator);
    defer allocator.free(jpeg);
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const path = try testPath(&tmp, allocator, "images.pdf");
    defer allocator.free(path);
    var pages = [_]pdf.Page{.{ .bytes = jpeg, .width = 1, .height = 1 }};
    const processor = pdf.Processor{ .allocator = allocator, .io = std.testing.io };
    try processor.createFromJpegs(&pages, path);
    try std.testing.expectEqual(@as(u32, 1), try processor.pageCount(path));
    var extracted = (try processor.firstJpeg(path)) orelse return error.TestUnexpectedResult;
    defer extracted.deinit();
    try std.testing.expectEqual(@as(u32, 1), extracted.width);
    try std.testing.expectEqual(@as(u32, 1), extracted.height);
    try std.testing.expectEqualSlices(u8, jpeg, extracted.bytes);
}
