const std = @import("std");

const c = @import("pdfio");
const image = @import("image.zig");
const protocol = @import("protocol.zig");
const realesrgan = @import("realesrgan.zig");
const storage = @import("storage.zig");

const Allocator = std.mem.Allocator;

pub const max_pdf_bytes: usize = 512 * 1024 * 1024;
pub const max_stream_bytes: usize = 64 * 1024 * 1024;

pub const JpegImage = struct {
    allocator: std.mem.Allocator,
    bytes: []u8,
    width: u32,
    height: u32,

    pub fn deinit(self: *JpegImage) void {
        self.allocator.free(self.bytes);
        self.* = undefined;
    }
};

pub const Page = struct {
    bytes: []const u8,
    width: u32,
    height: u32,
};

pub fn pageCount(alloc: Allocator, source: []const u8) !u32 {
    const source_z = try alloc.dupeZ(u8, source);
    defer alloc.free(source_z);

    const pdf = c.pdfioFileOpen(source_z.ptr, null, null, null, null) orelse return error.InvalidPdf;
    defer _ = c.pdfioFileClose(pdf);

    const count = c.pdfioFileGetNumPages(pdf);
    return std.math.cast(u32, count) orelse error.PdfTooManyPages;
}

pub fn thumbnailBytes(alloc: Allocator, source: []const u8) !?[]u8 {
    const source_z = try alloc.dupeZ(u8, source);
    defer alloc.free(source_z);

    const pdf = c.pdfioFileOpen(source_z.ptr, null, null, null, null) orelse return error.InvalidPdf;
    defer _ = c.pdfioFileClose(pdf);

    const pdf_image = getFirstImage(pdf, null) orelse return null;

    switch (pdf_image.encoding) {
        .jpeg => {
            const bytes = try readStream(alloc, pdf_image.object, false, c.pdfioObjGetLength(pdf_image.object)) orelse return null;
            defer alloc.free(bytes);

            return try image.thumbnailBytes(alloc, bytes);
        },
        .flate, .raw => {
            var raw = try readFlateImage(alloc, pdf_image) orelse return null;
            defer raw.deinit(alloc);

            return try image.thumbnailBytesFromRgb(alloc, raw.width, raw.height, raw.pixels);
        },
    }
}

fn readFlateImage(allocator: std.mem.Allocator, pdf_image: ImageObject) !?RawImage {
    const bits_per_component = numberToU32(c.pdfioDictGetNumber(pdf_image.dict, "BitsPerComponent")) orelse return null;
    if (bits_per_component != 8) return null;

    const channels = pdfImageChannels(pdf_image.dict) orelse return null;
    const pixel_count = std.math.mul(usize, pdf_image.width, pdf_image.height) catch return error.PdfStreamTooLarge;
    const sample_count = std.math.mul(usize, pixel_count, channels) catch return error.PdfStreamTooLarge;

    if (sample_count == 0 or sample_count > max_stream_bytes) return null;

    const decoded = try readStream(allocator, pdf_image.object, pdf_image.encoding == .flate, sample_count) orelse return null;

    if (channels == 3) {
        return .{ .pixels = decoded, .width = pdf_image.width, .height = pdf_image.height };
    }

    const rgb_count = std.math.mul(usize, pixel_count, 3) catch {
        allocator.free(decoded);
        return error.PdfStreamTooLarge;
    };

    const rgb = allocator.alloc(u8, rgb_count) catch {
        allocator.free(decoded);
        return error.PdfStreamTooLarge;
    };

    for (decoded, 0..) |value, index| {
        const offset = index * 3;
        rgb[offset] = value;
        rgb[offset + 1] = value;
        rgb[offset + 2] = value;
    }
    allocator.free(decoded);

    return .{ .pixels = rgb, .width = pdf_image.width, .height = pdf_image.height };
}

pub fn toPdf(
    alloc: Allocator,
    io: std.Io,
    sources: []const []const u8,
    destination: []const u8,
    config: protocol.Config,
    ai_models: ?*const realesrgan.Models,
) !void {
    if (sources.len == 0) return error.EmptyPdf;

    var pages = std.ArrayList(Page).empty;
    defer {
        for (pages.items) |page| alloc.free(page.bytes);
        pages.deinit(alloc);
    }

    for (sources) |source| {
        const bytes = try image.encodeBytes(alloc, io, source, config, 0, ai_models);
        const dimensions = image.inspectMemory(bytes) catch |err| {
            alloc.free(bytes);
            return err;
        };
        pages.append(alloc, .{ .bytes = bytes, .width = dimensions.width, .height = dimensions.height }) catch |err| {
            alloc.free(bytes);
            return err;
        };
    }
    const output = try createPdf(alloc, pages.items);
    defer alloc.free(output);

    try storage.writeAtomic(io, destination, output);
}

pub fn createFromJpegs(alloc: Allocator, io: std.Io, pages: []const Page, destination: []const u8) !void {
    const output = try createPdf(alloc, pages);
    defer alloc.free(output);

    try storage.writeAtomic(io, destination, output);
}

const ImageObject = struct {
    object: *c.pdfio_obj_t,
    dict: *c.pdfio_dict_t,
    width: u32,
    height: u32,
    encoding: ImageEncoding,
};

const ImageEncoding = enum { jpeg, flate, raw };

const RawImage = struct {
    pixels: []u8,
    width: u32,
    height: u32,

    fn deinit(self: *RawImage, alloc: Allocator) void {
        alloc.free(self.pixels);
        self.* = undefined;
    }
};

fn getFirstImage(pdf: *c.pdfio_file_t, filter: ?[]const u8) ?ImageObject {
    if (c.pdfioFileGetNumPages(pdf) == 0) return null;
    const page = c.pdfioFileGetPage(pdf, 0) orelse return null;
    const resources = pageDictValue(page, "Resources") orelse return null;
    const xobjects = dictValue(resources, "XObject") orelse return null;

    for (0..c.pdfioDictGetNumPairs(xobjects)) |pair| {
        const key = c.pdfioDictGetKey(xobjects, pair) orelse continue;
        const object = c.pdfioDictGetObj(xobjects, key) orelse continue;
        const dict = c.pdfioObjGetDict(object) orelse continue;
        const subtype_name = c.pdfioDictGetName(dict, "Subtype") orelse continue;

        if (!std.mem.eql(u8, std.mem.span(subtype_name), "Image")) continue;

        if (c.pdfioDictGetName(dict, "Type")) |type_name| {
            if (!std.mem.eql(u8, std.mem.span(type_name), "XObject")) continue;
        }

        const encoding = imageEncoding(dict) orelse continue;
        if (filter) |name| if (!hasFilter(dict, name)) continue;

        const width = numberToU32(c.pdfioDictGetNumber(dict, "Width")) orelse continue;
        const height = numberToU32(c.pdfioDictGetNumber(dict, "Height")) orelse continue;

        const length = c.pdfioObjGetLength(object);
        if (length == 0 or length > max_stream_bytes) continue;

        return .{ .object = object, .dict = dict, .width = width, .height = height, .encoding = encoding };
    }

    return null;
}

fn imageEncoding(dict: *c.pdfio_dict_t) ?ImageEncoding {
    return switch (c.pdfioDictGetType(dict, "Filter")) {
        c.PDFIO_VALTYPE_NONE => .raw,
        c.PDFIO_VALTYPE_NAME => imageEncodingName(c.pdfioDictGetName(dict, "Filter") orelse return null),
        c.PDFIO_VALTYPE_ARRAY => blk: {
            const filters = c.pdfioDictGetArray(dict, "Filter") orelse break :blk null;
            if (c.pdfioArrayGetSize(filters) != 1) break :blk null;
            break :blk imageEncodingName(c.pdfioArrayGetName(filters, 0) orelse break :blk null);
        },
        else => null,
    };
}

fn imageEncodingName(name: [*:0]const u8) ?ImageEncoding {
    const text = std.mem.span(name);
    if (std.mem.eql(u8, text, "DCTDecode")) return .jpeg;
    if (std.mem.eql(u8, text, "FlateDecode")) return .flate;
    return null;
}

fn pageDictValue(page: *c.pdfio_obj_t, key: [*:0]const u8) ?*c.pdfio_dict_t {
    if (c.pdfioPageGetDict(page, key)) |dict| return dict;
    const object = c.pdfioPageGetObj(page, key) orelse return null;
    return c.pdfioObjGetDict(object);
}

fn dictValue(dict: *c.pdfio_dict_t, key: [*:0]const u8) ?*c.pdfio_dict_t {
    if (c.pdfioDictGetDict(dict, key)) |value| return value;
    const object = c.pdfioDictGetObj(dict, key) orelse return null;
    return c.pdfioObjGetDict(object);
}

fn readStream(allocator: std.mem.Allocator, object: *c.pdfio_obj_t, decode: bool, length: usize) !?[]u8 {
    if (length == 0 or length > max_stream_bytes) return null;
    const stream = c.pdfioObjOpenStream(object, decode) orelse return null;
    defer _ = c.pdfioStreamClose(stream);
    const bytes = allocator.alloc(u8, length) catch return error.PdfStreamTooLarge;
    var keep = false;
    defer if (!keep) allocator.free(bytes);
    var offset: usize = 0;
    while (offset < length) {
        const amount = c.pdfioStreamRead(stream, bytes.ptr + offset, length - offset);
        if (amount <= 0) break;
        offset += @intCast(amount);
    }
    var extra: [1]u8 = undefined;
    const has_extra = c.pdfioStreamRead(stream, &extra, extra.len) > 0;
    if (offset != length or has_extra) return null;
    keep = true;
    return bytes;
}

fn pdfImageChannels(dict: *c.pdfio_dict_t) ?usize {
    const colorspace = c.pdfioDictGetName(dict, "ColorSpace") orelse return null;
    if (std.mem.eql(u8, std.mem.span(colorspace), "DeviceRGB")) return 3;
    if (std.mem.eql(u8, std.mem.span(colorspace), "DeviceGray")) return 1;
    return null;
}

fn hasFilter(dict: *c.pdfio_dict_t, expected: []const u8) bool {
    return switch (c.pdfioDictGetType(dict, "Filter")) {
        c.PDFIO_VALTYPE_NAME => blk: {
            const filter_name = c.pdfioDictGetName(dict, "Filter") orelse break :blk false;
            break :blk std.mem.eql(u8, std.mem.span(filter_name), expected);
        },
        c.PDFIO_VALTYPE_ARRAY => blk: {
            const filters = c.pdfioDictGetArray(dict, "Filter") orelse break :blk false;
            if (c.pdfioArrayGetSize(filters) != 1) break :blk false;
            const filter_name = c.pdfioArrayGetName(filters, 0) orelse break :blk false;
            break :blk std.mem.eql(u8, std.mem.span(filter_name), expected);
        },
        else => false,
    };
}

fn numberToU32(value: f64) ?u32 {
    if (!std.math.isFinite(value) or value <= 0 or value > std.math.maxInt(u32)) return null;
    const result: u32 = @intFromFloat(value);
    if (@as(f64, @floatFromInt(result)) != value) return null;
    return result;
}

const Output = struct {
    allocator: std.mem.Allocator,
    bytes: std.ArrayList(u8) = .empty,
};

fn outputCallback(context: ?*anyopaque, data: ?*const anyopaque, length: usize) callconv(.c) isize {
    const output = context orelse return -1;
    const target: *Output = @ptrCast(@alignCast(output));
    if (length == 0) return 0;
    const source = data orelse return -1;
    if (target.bytes.items.len > max_pdf_bytes or length > max_pdf_bytes - target.bytes.items.len) return -1;
    target.bytes.appendSlice(target.allocator, @as([*]const u8, @ptrCast(source))[0..length]) catch return -1;
    return @intCast(length);
}

fn createPdf(allocator: std.mem.Allocator, pages: []const Page) ![]u8 {
    if (pages.len == 0) return error.EmptyPdf;
    var output = Output{ .allocator = allocator };
    defer output.bytes.deinit(allocator);

    var media_box = c.pdfio_rect_t{ .x1 = 0, .y1 = 0, .x2 = @floatFromInt(pages[0].width), .y2 = @floatFromInt(pages[0].height) };
    const pdf = c.pdfioFileCreateOutput(outputCallback, @ptrCast(&output), "1.7", &media_box, &media_box, null, null) orelse return error.PdfCreateFailed;

    var isFileClosed = false;
    errdefer {
        if (!isFileClosed) _ = c.pdfioFileClose(pdf);
    }

    for (pages, 0..) |page, index| {
        const image_dict = c.pdfioDictCreate(pdf) orelse return error.PdfCreateFailed;
        if (
            !c.pdfioDictSetName(image_dict, "Type", "XObject") or
            !c.pdfioDictSetName(image_dict, "Subtype", "Image") or
            !c.pdfioDictSetNumber(image_dict, "Width", @floatFromInt(page.width)) or
            !c.pdfioDictSetNumber(image_dict, "Height", @floatFromInt(page.height)) or
            !c.pdfioDictSetNumber(image_dict, "BitsPerComponent", 8) or
            !c.pdfioDictSetName(image_dict, "ColorSpace", "DeviceRGB") or
            !c.pdfioDictSetName(image_dict, "Filter", "DCTDecode")
        ) return error.PdfCreateFailed;

        const image_object = c.pdfioFileCreateObj(pdf, image_dict) orelse return error.PdfCreateFailed;
        const image_stream = c.pdfioObjCreateStream(image_object, c.PDFIO_FILTER_NONE) orelse return error.PdfCreateFailed;
        if (!c.pdfioStreamWrite(image_stream, page.bytes.ptr, page.bytes.len) or !c.pdfioStreamClose(image_stream)) return error.PdfCreateFailed;

        const page_dict = c.pdfioDictCreate(pdf) orelse return error.PdfCreateFailed;
        var page_box = c.pdfio_rect_t{ .x1 = 0, .y1 = 0, .x2 = @floatFromInt(page.width), .y2 = @floatFromInt(page.height) };

        const resources = c.pdfioDictCreate(pdf) orelse return error.PdfCreateFailed;
        const xobjects = c.pdfioDictCreate(pdf) orelse return error.PdfCreateFailed;
        var image_name: [16]u8 = undefined;
        const image_name_z = std.fmt.bufPrintZ(&image_name, "Im{d}", .{index}) catch return error.PdfCreateFailed;
        if (
            !c.pdfioDictSetObj(xobjects, image_name_z, image_object) or
            !c.pdfioDictSetDict(resources, "XObject", xobjects) or
            !c.pdfioDictSetDict(page_dict, "Resources", resources) or
            !c.pdfioDictSetRect(page_dict, "MediaBox", &page_box)
        ) return error.PdfCreateFailed;

        const page_stream = c.pdfioFileCreatePage(pdf, page_dict) orelse return error.PdfCreateFailed;
        const commands = try std.fmt.allocPrint(allocator, "q\n{d} 0 0 {d} 0 0 cm\n/{s} Do\nQ\n", .{ page.width, page.height, image_name_z });
        defer allocator.free(commands);

        if (!c.pdfioStreamWrite(page_stream, commands.ptr, commands.len) or !c.pdfioStreamClose(page_stream)) return error.PdfCreateFailed;
    }
    if (!c.pdfioFileClose(pdf)) return error.PdfCreateFailed;
    isFileClosed = true;

    return output.bytes.toOwnedSlice(allocator);
}
