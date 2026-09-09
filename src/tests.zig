const std = @import("std");

const image = @import("core/image.zig");
const main = @import("main.zig");
const operations = @import("core/operations.zig");
const pdf = @import("core/pdf.zig");
const protocol = @import("core/protocol.zig");
const zip = @import("core/zip.zig");

const png_base64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=";
const flate_pdf_base64 = "JVBERi0xLjcKJeLjz9MKMSAwIG9iago8PCAvVHlwZSAvQ2F0YWxvZyAvUGFnZXMgMiAwIFIgPj4KZW5kb2JqCjIgMCBvYmoKPDwgL1R5cGUgL1BhZ2VzIC9LaWRzIFszIDAgUl0gL0NvdW50IDEgPj4KZW5kb2JqCjMgMCBvYmoKPDwgL1R5cGUgL1BhZ2UgL1BhcmVudCAyIDAgUiAvUmVzb3VyY2VzIDQgMCBSIC9NZWRpYUJveCBbMCAwIDEgMV0gL0NvbnRlbnRzIDYgMCBSID4+CmVuZG9iago0IDAgb2JqCjw8IC9YT2JqZWN0IDw8IC9JbTAgNSAwIFIgPj4gPj4KZW5kb2JqCjUgMCBvYmoKPDwgL1R5cGUgL1hPYmplY3QgL1N1YnR5cGUgL0ltYWdlIC9XaWR0aCAxIC9IZWlnaHQgMSAvQml0c1BlckNvbXBvbmVudCA4IC9Db2xvclNwYWNlIC9EZXZpY2VSR0IgL0ZpbHRlciAvRmxhdGVEZWNvZGUgL0xlbmd0aCAxMSA+PgpzdHJlYW0KeJz7z8AAAAMAAQAKZW5kc3RyZWFtCmVuZG9iago2IDAgb2JqCjw8IC9MZW5ndGggMjcgPj4Kc3RyZWFtCnEKMSAwIDAgMSAwIDAgY20KL0ltMCBEbwpRCmVuZHN0cmVhbQplbmRvYmoKeHJlZgowIDcKMDAwMDAwMDAwMCA2NTUzNSBmIAowMDAwMDAwMDE1IDAwMDAwIG4gCjAwMDAwMDAwNjQgMDAwMDAgbiAKMDAwMDAwMDEyMSAwMDAwMCBuIAowMDAwMDAwMjIxIDAwMDAwIG4gCjAwMDAwMDAyNjggMDAwMDAgbiAKMDAwMDAwMDQ0MyAwMDAwMCBuIAp0cmFpbGVyCjw8IC9TaXplIDcgL1Jvb3QgMSAwIFIgPj4Kc3RhcnR4cmVmCjUxOQolJUVPRgo=";

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
    return image.encodeBytesFromMemory(png, .{ .width = 1, .quality = 80, .ai = false });
}

fn fixtureFlatePdf(allocator: std.mem.Allocator) ![]u8 {
    const size = std.base64.standard.Decoder.calcSizeForSlice(flate_pdf_base64) catch unreachable;
    const result = try allocator.alloc(u8, size);
    errdefer allocator.free(result);
    try std.base64.standard.Decoder.decode(result, flate_pdf_base64);
    return result;
}

fn fixtureMixedPdf(allocator: std.mem.Allocator, jpeg: []const u8) ![]u8 {
    const flate = [_]u8{ 0x78, 0x9c, 0xfb, 0xcf, 0xc0, 0xf0, 0x9f, 0x81, 0x01, 0x00, 0x08, 0xfd, 0x01, 0xff };
    var output = std.ArrayList(u8).empty;
    errdefer output.deinit(allocator);
    var offsets: [8]usize = undefined;
    try output.appendSlice(allocator, "%PDF-1.7\n%\xE2\xE3\xCF\xD3\n");
    offsets[1] = output.items.len;
    try output.print(allocator, "1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n", .{});
    offsets[2] = output.items.len;
    try output.print(allocator, "2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n", .{});
    offsets[3] = output.items.len;
    try output.print(allocator, "3 0 obj\n<< /Type /Page /Parent 2 0 R /Resources 4 0 R /MediaBox [0 0 2 1] /Contents 6 0 R >>\nendobj\n", .{});
    offsets[4] = output.items.len;
    try output.print(allocator, "4 0 obj\n<< /XObject << /A 5 0 R /B 7 0 R >> >>\nendobj\n", .{});
    offsets[5] = output.items.len;
    try output.print(allocator, "5 0 obj\n<< /Type /XObject /Subtype /Image /Width 2 /Height 1 /BitsPerComponent 8 /ColorSpace /DeviceRGB /Filter /FlateDecode /Length {d} >>\nstream\n", .{flate.len});
    try output.appendSlice(allocator, &flate);
    try output.appendSlice(allocator, "\nendstream\nendobj\n");
    offsets[6] = output.items.len;
    try output.print(allocator, "6 0 obj\n<< /Length 0 >>\nstream\n\nendstream\nendobj\n", .{});
    offsets[7] = output.items.len;
    try output.print(allocator, "7 0 obj\n<< /Type /XObject /Subtype /Image /Width 1 /Height 1 /BitsPerComponent 8 /ColorSpace /DeviceRGB /Filter /DCTDecode /Length {d} >>\nstream\n", .{jpeg.len});
    try output.appendSlice(allocator, jpeg);
    try output.appendSlice(allocator, "\nendstream\nendobj\n");
    const xref_offset = output.items.len;
    try output.appendSlice(allocator, "xref\n0 8\n0000000000 65535 f \n");
    for (offsets[1..]) |offset| try output.print(allocator, "{d:0>10} 00000 n \n", .{offset});
    try output.print(allocator, "trailer\n<< /Size 8 /Root 1 0 R >>\nstartxref\n{d}\n%%EOF\n", .{xref_offset});
    return output.toOwnedSlice(allocator);
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

    try std.testing.expectEqual(@as(u32, 2), try pdf.pageCount(allocator, pdf_path));
    var extracted = (try pdf.firstJpeg(allocator, pdf_path)) orelse return error.TestUnexpectedResult;
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

    try pdf.createFromJpegs(allocator, std.testing.io, &pages, path);
    try std.testing.expectEqual(@as(u32, 1), try pdf.pageCount(allocator, path));
    var extracted = (try pdf.firstJpeg(path)) orelse return error.TestUnexpectedResult;
    defer extracted.deinit();
    try std.testing.expectEqual(@as(u32, 1), extracted.width);
    try std.testing.expectEqual(@as(u32, 1), extracted.height);
    try std.testing.expectEqualSlices(u8, jpeg, extracted.bytes);
    var inspected = try operations.inspect(allocator, std.testing.io, path);
    defer operations.freeResponse(allocator, &inspected);
    try std.testing.expectEqual(protocol.Kind.pdf, inspected.kind);
    try std.testing.expectEqual(@as(u32, 1), inspected.count);
    try std.testing.expect(inspected.thumbnail_blob != null);
}

test "pdf thumbnail reads a Flate encoded RGB image XObject" {
    const allocator = std.testing.allocator;
    const bytes = try fixtureFlatePdf(allocator);
    defer allocator.free(bytes);
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const path = try testPath(&tmp, allocator, "flate.pdf");
    defer allocator.free(path);
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "flate.pdf", .data = bytes });
    const thumbnail = (try (pdf.Processor{ .allocator = allocator, .io = std.testing.io }).thumbnailBytes(path)) orelse return error.TestUnexpectedResult;
    defer allocator.free(thumbnail);
    try std.testing.expect(thumbnail.len != 0);
    const dimensions = try image.inspectMemory(thumbnail);
    try std.testing.expectEqual(@as(u32, 1), dimensions.width);
    try std.testing.expectEqual(@as(u32, 1), dimensions.height);
}

test "pdf thumbnail uses the first supported image" {
    const allocator = std.testing.allocator;
    const jpeg = try fixtureJpeg(allocator);
    defer allocator.free(jpeg);
    const bytes = try fixtureMixedPdf(allocator, jpeg);
    defer allocator.free(bytes);
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const path = try testPath(&tmp, allocator, "mixed.pdf");
    defer allocator.free(path);
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "mixed.pdf", .data = bytes });
    const processor = pdf.Processor{ .allocator = allocator, .io = std.testing.io };
    const thumbnail = (try processor.thumbnailBytes(path)) orelse return error.TestUnexpectedResult;
    defer allocator.free(thumbnail);
    const dimensions = try image.inspectMemory(thumbnail);
    try std.testing.expectEqual(@as(u32, 2), dimensions.width);
    try std.testing.expectEqual(@as(u32, 1), dimensions.height);
    const pixels = [_]u8{ 255, 0, 0, 255, 0, 0 };
    const expected = try (image.Processor{ .allocator = allocator, .io = std.testing.io }).thumbnailBytesFromRgb(2, 1, &pixels);
    defer allocator.free(expected);
    try std.testing.expectEqualSlices(u8, expected, thumbnail);
}

test "folder inspection keeps images and ignores nonimage files" {
    const allocator = std.testing.allocator;
    const png = try fixturePng(allocator);
    defer allocator.free(png);
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(std.testing.io, "photos");
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "photos/first.png", .data = png });
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "photos/notes.txt", .data = "ignore" });
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "photos/broken.pdf", .data = "not a pdf" });
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "photos/broken.zip", .data = "not a zip" });
    try tmp.dir.createDirPath(std.testing.io, "photos/empty");
    const path = try testPath(&tmp, allocator, "photos");
    defer allocator.free(path);
    var response = try operations.inspect(allocator, std.testing.io, path);
    defer operations.freeResponse(allocator, &response);
    try std.testing.expectEqual(protocol.Kind.directory, response.kind);
    try std.testing.expectEqual(@as(u32, 1), response.count);
    try std.testing.expectEqual(@as(usize, 1), response.children.len);
    try std.testing.expectEqualStrings("first.png", response.children[0].name);
    try std.testing.expect(response.thumbnail != null);
}

test "dialog and drop replace inspected roots and their trees" {
    const allocator = std.testing.allocator;
    const png = try fixturePng(allocator);
    defer allocator.free(png);
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(std.testing.io, "folder");
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "folder/inside.png", .data = png });
    const folder_path = try testPath(&tmp, allocator, "folder");
    defer allocator.free(folder_path);
    const image_path = try testPath(&tmp, allocator, "single.png");
    defer allocator.free(image_path);
    const output_directory = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}", .{tmp.sub_path});
    defer allocator.free(output_directory);
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "single.png", .data = png });

    var pool: main.JobPool = undefined;
    pool.init(allocator, std.testing.io);
    defer pool.deinit();
    var fx = main.Effects.init(allocator);
    defer fx.deinit();
    fx.executor = .fake;
    fx.fake_instant_image_bytes = png;
    var model = main.Model{ .job_pool = &pool };
    model.dialog = .files;
    main.update(&model, .{ .dialog_ready = .{ .paths = folder_path, .count = 1 } }, &fx);

    var steps: usize = 0;
    while ((model.inspecting or model.thumbnail_pending != 0) and steps < 1000) : (steps += 1) {
        if (fx.takeMsg()) |message| {
            main.update(&model, message, &fx);
        } else {
            try std.Io.sleep(std.testing.io, std.Io.Duration.fromMilliseconds(1), .awake);
        }
    }
    try std.testing.expect(steps < 1000);
    try std.testing.expectEqual(@as(usize, 1), model.root_count);
    try std.testing.expectEqual(@as(usize, 2), model.item_count);
    try std.testing.expect(model.items[0].thumbnail().len != 0);
    try std.testing.expect(model.items[1].thumbnail().len != 0);
    try std.testing.expectEqual(@as(u32, 1), model.items[0].count);
    try std.testing.expectEqual(protocol.Kind.image, model.items[1].kind);

    main.update(&model, .{ .dropped = .{ .paths = &.{image_path} } }, &fx);
    steps = 0;
    while ((model.inspecting or model.thumbnail_pending != 0) and steps < 1000) : (steps += 1) {
        if (fx.takeMsg()) |message| {
            main.update(&model, message, &fx);
        } else {
            try std.Io.sleep(std.testing.io, std.Io.Duration.fromMilliseconds(1), .awake);
        }
    }
    try std.testing.expect(steps < 1000);
    try std.testing.expectEqual(@as(usize, 1), model.root_count);
    try std.testing.expectEqual(@as(usize, 1), model.item_count);
    try std.testing.expectEqual(protocol.Kind.image, model.items[0].kind);
    try std.testing.expectEqualStrings(image_path, model.items[0].path());

    main.Model.copyPath(&model.output_storage, &model.output_len, output_directory);
    model.config.mode = .path;
    model.config.width = 1;
    model.config.quality = 80;
    main.update(&model, .process, &fx);
    steps = 0;
    while ((model.processing or model.thumbnail_pending != 0) and steps < 1000) : (steps += 1) {
        if (fx.takeMsg()) |message| {
            main.update(&model, message, &fx);
        } else {
            try std.Io.sleep(std.testing.io, std.Io.Duration.fromMilliseconds(1), .awake);
        }
    }
    try std.testing.expect(steps < 1000);
    try std.testing.expectEqual(@as(usize, 1), model.output_count);
    try std.testing.expect(!model.processing);

    main.update(&model, .clear_files, &fx);
    try std.testing.expectEqual(@as(usize, 0), model.root_count);
    try std.testing.expectEqual(@as(usize, 0), model.item_count);
    try std.testing.expectEqual(@as(usize, 0), model.thumbnail_pending);
}
