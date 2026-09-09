const std = @import("std");

const c = @import("pdfio");
const image = @import("image.zig");
const protocol = @import("protocol.zig");
const realesrgan = @import("realesrgan.zig");
const storage = @import("storage.zig");

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

pub const Processor = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    ai_models: ?*const realesrgan.Models = null,

    pub fn pageCount(self: Processor, source: []const u8) !u32 {
        const source_z = try self.allocator.dupeZ(u8, source);
        defer self.allocator.free(source_z);
        const pdf = c.pdfioFileOpen(source_z.ptr, null, null, null, null) orelse return error.InvalidPdf;
        defer _ = c.pdfioFileClose(pdf);
        const count = c.pdfioFileGetNumPages(pdf);
        return std.math.cast(u32, count) orelse error.PdfTooManyPages;
    }

    pub fn firstJpeg(self: Processor, source: []const u8) !?JpegImage {
        const source_z = try self.allocator.dupeZ(u8, source);
        defer self.allocator.free(source_z);
        const pdf = c.pdfioFileOpen(source_z.ptr, null, null, null, null) orelse return error.InvalidPdf;
        defer _ = c.pdfioFileClose(pdf);
        if (c.pdfioFileGetNumPages(pdf) == 0) return null;
        const page = c.pdfioFileGetPage(pdf, 0) orelse return null;
        const resources = c.pdfioPageGetDict(page, "Resources") orelse return null;
        const xobjects = c.pdfioDictGetDict(resources, "XObject") orelse return null;
        const pair_count = c.pdfioDictGetNumPairs(xobjects);
        for (0..pair_count) |pair| {
            const key = c.pdfioDictGetKey(xobjects, pair) orelse continue;
            const object = c.pdfioDictGetObj(xobjects, key) orelse continue;
            const dict = c.pdfioObjGetDict(object) orelse continue;
            const type_name = c.pdfioDictGetName(dict, "Type") orelse continue;
            const subtype_name = c.pdfioDictGetName(dict, "Subtype") orelse continue;
            const filter_name = c.pdfioDictGetName(dict, "Filter") orelse continue;
            if (!std.mem.eql(u8, std.mem.span(type_name), "XObject") or
                !std.mem.eql(u8, std.mem.span(subtype_name), "Image") or
                !std.mem.eql(u8, std.mem.span(filter_name), "DCTDecode")) continue;
            const width = numberToU32(c.pdfioDictGetNumber(dict, "Width")) orelse continue;
            const height = numberToU32(c.pdfioDictGetNumber(dict, "Height")) orelse continue;
            const length = c.pdfioObjGetLength(object);
            if (length == 0 or length > max_stream_bytes) continue;
            const stream = c.pdfioObjOpenStream(object, false) orelse continue;
            const bytes = self.allocator.alloc(u8, length) catch return error.PdfStreamTooLarge;
            var keep = false;
            defer if (!keep) self.allocator.free(bytes);
            var offset: usize = 0;
            while (offset < length) {
                const amount = c.pdfioStreamRead(stream, bytes.ptr + offset, length - offset);
                if (amount <= 0) break;
                offset += @intCast(amount);
            }
            _ = c.pdfioStreamClose(stream);
            if (offset != length) continue;
            keep = true;
            return .{ .allocator = self.allocator, .bytes = bytes, .width = width, .height = height };
        }
        return null;
    }

    pub fn thumbnailBytes(self: Processor, source: []const u8) !?[]u8 {
        var jpeg = try self.firstJpeg(source) orelse return null;
        defer jpeg.deinit();
        const processor = image.Processor{ .allocator = self.allocator, .io = self.io };
        return try processor.thumbnailBytes(jpeg.bytes);
    }

    pub fn toPdf(self: Processor, sources: []const []const u8, destination: []const u8, config: protocol.Config) !void {
        if (sources.len == 0) return error.EmptyPdf;
        const processor = image.Processor{ .allocator = self.allocator, .io = self.io, .ai_models = self.ai_models };
        var pages = std.ArrayList(Page).empty;
        defer {
            for (pages.items) |page| self.allocator.free(page.bytes);
            pages.deinit(self.allocator);
        }
        for (sources) |source| {
            const bytes = try processor.encodeBytes(source, config, 0);
            const dimensions = image.inspectMemory(bytes) catch |err| {
                self.allocator.free(bytes);
                return err;
            };
            pages.append(self.allocator, .{ .bytes = bytes, .width = dimensions.width, .height = dimensions.height }) catch |err| {
                self.allocator.free(bytes);
                return err;
            };
        }
        const output = try createPdf(self.allocator, pages.items);
        defer self.allocator.free(output);
        try storage.writeAtomic(self.io, destination, output);
    }

    pub fn createFromJpegs(self: Processor, pages: []const Page, destination: []const u8) !void {
        const output = try createPdf(self.allocator, pages);
        defer self.allocator.free(output);
        try storage.writeAtomic(self.io, destination, output);
    }
};

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
    var closed = false;
    errdefer {
        if (!closed) _ = c.pdfioFileClose(pdf);
    }
    for (pages, 0..) |page, index| {
        const image_dict = c.pdfioDictCreate(pdf) orelse return error.PdfCreateFailed;
        if (!c.pdfioDictSetName(image_dict, "Type", "XObject") or
            !c.pdfioDictSetName(image_dict, "Subtype", "Image") or
            !c.pdfioDictSetNumber(image_dict, "Width", @floatFromInt(page.width)) or
            !c.pdfioDictSetNumber(image_dict, "Height", @floatFromInt(page.height)) or
            !c.pdfioDictSetNumber(image_dict, "BitsPerComponent", 8) or
            !c.pdfioDictSetName(image_dict, "ColorSpace", "DeviceRGB") or
            !c.pdfioDictSetName(image_dict, "Filter", "DCTDecode")) return error.PdfCreateFailed;
        const image_object = c.pdfioFileCreateObj(pdf, image_dict) orelse return error.PdfCreateFailed;
        const image_stream = c.pdfioObjCreateStream(image_object, c.PDFIO_FILTER_NONE) orelse return error.PdfCreateFailed;
        if (!c.pdfioStreamWrite(image_stream, page.bytes.ptr, page.bytes.len) or !c.pdfioStreamClose(image_stream)) return error.PdfCreateFailed;

        const page_dict = c.pdfioDictCreate(pdf) orelse return error.PdfCreateFailed;
        var page_box = c.pdfio_rect_t{ .x1 = 0, .y1 = 0, .x2 = @floatFromInt(page.width), .y2 = @floatFromInt(page.height) };
        const resources = c.pdfioDictCreate(pdf) orelse return error.PdfCreateFailed;
        const xobjects = c.pdfioDictCreate(pdf) orelse return error.PdfCreateFailed;
        var image_name: [16]u8 = undefined;
        const image_name_z = std.fmt.bufPrintZ(&image_name, "Im{d}", .{index}) catch return error.PdfCreateFailed;
        if (!c.pdfioDictSetObj(xobjects, image_name_z, image_object) or
            !c.pdfioDictSetDict(resources, "XObject", xobjects) or
            !c.pdfioDictSetDict(page_dict, "Resources", resources) or
            !c.pdfioDictSetRect(page_dict, "MediaBox", &page_box)) return error.PdfCreateFailed;
        const page_stream = c.pdfioFileCreatePage(pdf, page_dict) orelse return error.PdfCreateFailed;
        const commands = try std.fmt.allocPrint(allocator, "q\n{d} 0 0 {d} 0 0 cm\n/{s} Do\nQ\n", .{ page.width, page.height, image_name_z });
        defer allocator.free(commands);
        if (!c.pdfioStreamWrite(page_stream, commands.ptr, commands.len) or !c.pdfioStreamClose(page_stream)) return error.PdfCreateFailed;
    }
    if (!c.pdfioFileClose(pdf)) return error.PdfCreateFailed;
    closed = true;
    return output.bytes.toOwnedSlice(allocator);
}
