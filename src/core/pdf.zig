const std = @import("std");

const c = @import("pdfio");
const image = @import("image.zig");
const image_batch = @import("image_batch.zig");
const protocol = @import("protocol.zig");
const realesrgan = @import("realesrgan.zig");
const storage = @import("storage.zig");

const Allocator = std.mem.Allocator;

const max_pdf_bytes: usize = 512 * 1024 * 1024;
const max_stream_bytes: usize = max_pdf_bytes;

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

pub const PageInputKind = enum { encoded, rgb };

pub const PageInput = struct {
    kind: PageInputKind,
    bytes: []u8,
    width: u32 = 0,
    height: u32 = 0,

    pub fn source(self: *const PageInput) image_batch.Source {
        return switch (self.kind) {
            .encoded => .{ .encoded = self.bytes },
            .rgb => .{ .rgb = .{ .width = self.width, .height = self.height, .pixels = self.bytes } },
        };
    }

    pub fn deinit(self: *PageInput, allocator: Allocator) void {
        allocator.free(self.bytes);
        self.* = undefined;
    }
};

pub fn pageCount(alloc: Allocator, source: []const u8) !u32 {
    const source_z = try alloc.dupeZ(u8, source);
    defer alloc.free(source_z);

    const pdf = c.pdfioFileOpen(source_z.ptr, null, null, null, null) orelse return error.InvalidPdf;
    defer _ = c.pdfioFileClose(pdf);

    const count = c.pdfioFileGetNumPages(pdf);
    return std.math.cast(u32, count) orelse error.PdfTooManyPages;
}

pub fn imageCount(alloc: Allocator, source: []const u8) !u32 {
    const source_z = try alloc.dupeZ(u8, source);
    defer alloc.free(source_z);

    const pdf = c.pdfioFileOpen(source_z.ptr, null, null, null, null) orelse return error.InvalidPdf;
    defer _ = c.pdfioFileClose(pdf);

    var count: usize = 0;
    const page_count = c.pdfioFileGetNumPages(pdf);
    for (0..page_count) |page_index| {
        const images = try pageImages(alloc, pdf, page_index);
        defer alloc.free(images);
        count = std.math.add(usize, count, images.len) catch return error.PdfTooManyImages;
    }
    return std.math.cast(u32, count) orelse error.PdfTooManyImages;
}

pub fn thumbnailBytes(alloc: Allocator, source: []const u8) !?[]u8 {
    const source_z = try alloc.dupeZ(u8, source);
    defer alloc.free(source_z);

    const pdf = c.pdfioFileOpen(source_z.ptr, null, null, null, null) orelse return error.InvalidPdf;
    defer _ = c.pdfioFileClose(pdf);

    const images = try pageImages(alloc, pdf, 0);
    defer alloc.free(images);
    if (images.len == 0) return null;

    return thumbnailImage(alloc, images[0]);
}

pub fn extractPage(alloc: Allocator, io: std.Io, source: []const u8, page_index: usize) !PageInput {
    try io.checkCancel();
    const source_z = try alloc.dupeZ(u8, source);
    defer alloc.free(source_z);

    const source_pdf = c.pdfioFileOpen(source_z.ptr, null, null, null, null) orelse return error.InvalidPdf;
    defer _ = c.pdfioFileClose(source_pdf);

    const page_count = c.pdfioFileGetNumPages(source_pdf);
    if (page_index >= page_count) return error.InvalidPdfPage;

    const images = try pageImages(alloc, source_pdf, page_index);
    defer alloc.free(images);
    if (images.len == 0) {
        const page = c.pdfioFileGetPage(source_pdf, page_index) orelse return error.EmptyPdfPage;
        var media_box: c.pdfio_rect_t = undefined;
        if (c.pdfioPageGetRect(page, "MediaBox", &media_box) == null) return error.EmptyPdfPage;
        const width: u32 = @intFromFloat(@max(@as(f64, 1), media_box.x2 - media_box.x1));
        const height: u32 = @intFromFloat(@max(@as(f64, 1), media_box.y2 - media_box.y1));
        const pixel_count = std.math.mul(usize, @as(usize, width), @as(usize, height)) catch return error.PdfStreamTooLarge;
        const byte_count = std.math.mul(usize, pixel_count, 3) catch return error.PdfStreamTooLarge;
        const bytes = try alloc.alloc(u8, byte_count);
        @memset(bytes, 255);
        return .{ .kind = .rgb, .bytes = bytes, .width = width, .height = height };
    }

    const pdf_image = images[0];
    switch (pdf_image.encoding) {
        .jpeg => {
            const bytes = try readEncodedImage(alloc, pdf_image) orelse return error.PdfImageReadFailed;
            return .{ .kind = .encoded, .bytes = bytes };
        },
        .flate, .raw => {
            var raw = try readFlateImage(alloc, pdf_image) orelse return error.PdfImageReadFailed;
            const result = PageInput{ .kind = .rgb, .bytes = raw.pixels, .width = raw.width, .height = raw.height };
            raw.pixels = &.{};
            return result;
        },
    }
}

fn thumbnailImage(allocator: Allocator, pdf_image: ImageObject) !?[]u8 {
    switch (pdf_image.encoding) {
        .jpeg => {
            const bytes = try readEncodedImage(allocator, pdf_image) orelse return null;
            defer allocator.free(bytes);
            return try image.thumbnailBytes(allocator, bytes);
        },
        .flate, .raw => {
            var raw = try readFlateImage(allocator, pdf_image) orelse return null;
            defer raw.deinit(allocator);
            return try image.thumbnailBytesFromRgb(allocator, raw.width, raw.height, raw.pixels);
        },
    }
}

fn readFlateImage(allocator: std.mem.Allocator, pdf_image: ImageObject) !?RawImage {
    const bits_per_component = numberToU32(dictNumber(pdf_image.dict, "BitsPerComponent") orelse return null) orelse return null;
    if (bits_per_component != 8) return null;

    const channels = pdfImageChannels(pdf_image.dict) orelse return null;
    const pixel_count = std.math.mul(usize, pdf_image.width, pdf_image.height) catch return error.PdfStreamTooLarge;
    const sample_count = std.math.mul(usize, pixel_count, channels) catch return error.PdfStreamTooLarge;

    if (sample_count == 0 or sample_count > max_stream_bytes) return null;

    const decoded = try readStream(allocator, pdf_image.object, pdf_image.decode, sample_count) orelse return null;

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

    if (channels == 1) {
        for (decoded, 0..) |value, index| {
            const offset = index * 3;
            rgb[offset] = value;
            rgb[offset + 1] = value;
            rgb[offset + 2] = value;
        }
    } else if (channels == 4) {
        for (0..pixel_count) |index| {
            const source = index * 4;
            const destination = index * 3;
            const cyan = @as(u16, decoded[source]);
            const magenta = @as(u16, decoded[source + 1]);
            const yellow = @as(u16, decoded[source + 2]);
            const black = @as(u16, decoded[source + 3]);
            rgb[destination] = @intCast(255 - @min(@as(u16, 255), cyan + black));
            rgb[destination + 1] = @intCast(255 - @min(@as(u16, 255), magenta + black));
            rgb[destination + 2] = @intCast(255 - @min(@as(u16, 255), yellow + black));
        }
    } else {
        allocator.free(decoded);
        allocator.free(rgb);
        return null;
    }
    allocator.free(decoded);

    return .{ .pixels = rgb, .width = pdf_image.width, .height = pdf_image.height };
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
    decode: bool,
    ascii85: bool,
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

const ResourceChain = struct {
    items: [64]*c.pdfio_dict_t = undefined,
    len: usize = 0,

    fn append(self: *ResourceChain, resources: *c.pdfio_dict_t) void {
        if (self.len == self.items.len) return;
        self.items[self.len] = resources;
        self.len += 1;
    }

    fn prepend(self: ResourceChain, resources: *c.pdfio_dict_t) ResourceChain {
        if (self.len == self.items.len) return self;
        var result = self;
        var index = result.len;
        while (index > 0) : (index -= 1) result.items[index] = result.items[index - 1];
        result.items[0] = resources;
        result.len += 1;
        return result;
    }
};

fn pageImages(allocator: Allocator, pdf: *c.pdfio_file_t, page_index: usize) ![]ImageObject {
    var resources_images = std.ArrayList(ImageObject).empty;
    errdefer resources_images.deinit(allocator);

    const page = c.pdfioFileGetPage(pdf, page_index) orelse return resources_images.toOwnedSlice(allocator);
    const own_resources = objectDictValue(page, "Resources");
    const resources = pageDictValue(page, "Resources") orelse return resources_images.toOwnedSlice(allocator);
    if (c.pdfioPageGetNumStreams(page) == 0) {
        if (own_resources) |value| {
            var forms = std.AutoHashMap(*c.pdfio_obj_t, void).init(allocator);
            defer forms.deinit();
            try collectXObjectImages(allocator, value, &resources_images, &forms);
        }
        return resources_images.toOwnedSlice(allocator);
    }
    var forms = std.AutoHashMap(*c.pdfio_obj_t, void).init(allocator);
    defer forms.deinit();
    try collectXObjectImages(allocator, own_resources orelse resources, &resources_images, &forms);

    var content_images = std.ArrayList(ImageObject).empty;
    errdefer content_images.deinit(allocator);
    var content_forms = std.AutoHashMap(*c.pdfio_obj_t, void).init(allocator);
    defer content_forms.deinit();
    var chain = pageResourceChain(page);
    if (chain.len == 0) chain.append(resources);
    const has_content = try collectPageContentImages(allocator, page, chain, &content_images, &content_forms);
    if (has_content) {
        resources_images.deinit(allocator);
        return content_images.toOwnedSlice(allocator);
    }
    content_images.deinit(allocator);

    return resources_images.toOwnedSlice(allocator);
}

fn pageResourceChain(page: *c.pdfio_obj_t) ResourceChain {
    var chain: ResourceChain = .{};
    var current: ?*c.pdfio_obj_t = page;
    while (current) |object| {
        const dict = c.pdfioObjGetDict(object) orelse break;
        if (dictValue(dict, "Resources")) |resources| chain.append(resources);
        current = c.pdfioDictGetObj(dict, "Parent");
    }
    return chain;
}

fn collectPageContentImages(
    allocator: Allocator,
    page: *c.pdfio_obj_t,
    resources: ResourceChain,
    images: *std.ArrayList(ImageObject),
    forms: *std.AutoHashMap(*c.pdfio_obj_t, void),
) !bool {
    var has_content = false;
    for (0..c.pdfioPageGetNumStreams(page)) |stream_index| {
        var uses = std.ArrayList(*c.pdfio_obj_t).empty;
        defer uses.deinit(allocator);
        {
            const stream = c.pdfioPageOpenStream(page, stream_index, true) orelse continue;
            has_content = true;
            defer _ = c.pdfioStreamClose(stream);
            try collectStreamUses(allocator, stream, resources, &uses);
        }
        for (uses.items) |object| try collectXObjectUse(allocator, object, resources, images, forms);
    }
    return has_content;
}

fn collectStreamImages(
    allocator: Allocator,
    stream: *c.pdfio_stream_t,
    resources: ResourceChain,
    images: *std.ArrayList(ImageObject),
    forms: *std.AutoHashMap(*c.pdfio_obj_t, void),
) anyerror!void {
    var uses = std.ArrayList(*c.pdfio_obj_t).empty;
    defer uses.deinit(allocator);
    try collectStreamUses(allocator, stream, resources, &uses);
    for (uses.items) |object| try collectXObjectUse(allocator, object, resources, images, forms);
}

fn collectStreamUses(
    allocator: Allocator,
    stream: *c.pdfio_stream_t,
    resources: ResourceChain,
    uses: *std.ArrayList(*c.pdfio_obj_t),
) !void {
    var token_buffer: [1024]u8 = undefined;
    var pending_name: [256]u8 = undefined;
    var pending_len: usize = 0;

    while (c.pdfioStreamGetToken(stream, &token_buffer, token_buffer.len)) {
        const token = std.mem.span(@as([*:0]const u8, @ptrCast(&token_buffer)));
        if (token.len > 1 and token[0] == '/') {
            const name = token[1..];
            if (name.len <= pending_name.len) {
                @memcpy(pending_name[0..name.len], name);
                pending_len = name.len;
            } else {
                pending_len = 0;
            }
            continue;
        }

        if (std.mem.eql(u8, token, "Do") and pending_len != 0) {
            const object = xObjectForName(resources, pending_name[0..pending_len]) orelse {
                pending_len = 0;
                continue;
            };
            try uses.append(allocator, object);
        }
        pending_len = 0;
    }
}

fn xObjectForName(resources: ResourceChain, name: []const u8) ?*c.pdfio_obj_t {
    var key: [256]u8 = undefined;
    const key_z = std.fmt.bufPrintZ(&key, "{s}", .{name}) catch return null;
    var index: usize = 0;
    while (index < resources.len) : (index += 1) {
        const xobjects = dictValue(resources.items[index], "XObject") orelse continue;
        if (c.pdfioDictGetObj(xobjects, key_z)) |object| return object;
    }
    return null;
}

fn collectXObjectUse(
    allocator: Allocator,
    object: *c.pdfio_obj_t,
    resources: ResourceChain,
    images: *std.ArrayList(ImageObject),
    forms: *std.AutoHashMap(*c.pdfio_obj_t, void),
) anyerror!void {
    if (imageObject(object)) |image_value| {
        try images.append(allocator, image_value);
        return;
    }

    const dict = c.pdfioObjGetDict(object) orelse return;
    const subtype = dictName(dict, "Subtype") orelse return;
    if (!std.mem.eql(u8, std.mem.span(subtype), "Form")) return;
    if (forms.contains(object)) return;
    try forms.put(object, {});

    const form_resources = dictValue(dict, "Resources");
    const form_chain = if (form_resources) |value| resources.prepend(value) else resources;
    const form_stream = c.pdfioObjOpenStream(object, true) orelse return;
    defer _ = c.pdfioStreamClose(form_stream);
    try collectStreamImages(allocator, form_stream, form_chain, images, forms);
}

fn collectXObjectImages(
    allocator: Allocator,
    resources: *c.pdfio_dict_t,
    images: *std.ArrayList(ImageObject),
    forms: *std.AutoHashMap(*c.pdfio_obj_t, void),
) !void {
    const xobjects = dictValue(resources, "XObject") orelse return;

    for (0..c.pdfioDictGetNumPairs(xobjects)) |pair| {
        const key = c.pdfioDictGetKey(xobjects, pair) orelse continue;
        const object = c.pdfioDictGetObj(xobjects, key) orelse continue;
        if (imageObject(object)) |image_value| {
            try images.append(allocator, image_value);
            continue;
        }

        const dict = c.pdfioObjGetDict(object) orelse continue;
        const subtype = dictName(dict, "Subtype") orelse continue;
        if (!std.mem.eql(u8, std.mem.span(subtype), "Form")) continue;
        if (forms.contains(object)) continue;
        try forms.put(object, {});
        const form_resources = dictValue(dict, "Resources") orelse resources;
        try collectXObjectImages(allocator, form_resources, images, forms);
    }
}

fn imageObject(object: *c.pdfio_obj_t) ?ImageObject {
    const dict = c.pdfioObjGetDict(object) orelse return null;
    const subtype_name = dictName(dict, "Subtype") orelse return null;
    if (!std.mem.eql(u8, std.mem.span(subtype_name), "Image")) return null;

    if (dictName(dict, "Type")) |type_name| {
        if (!std.mem.eql(u8, std.mem.span(type_name), "XObject")) return null;
    }

    const encoding = imageEncoding(dict) orelse return null;
    const width = numberToU32(dictNumber(dict, "Width") orelse return null) orelse return null;
    const height = numberToU32(dictNumber(dict, "Height") orelse return null) orelse return null;
    const length = c.pdfioObjGetLength(object);
    if (length == 0 or length > max_stream_bytes) return null;

    if (encoding != .jpeg) {
        const bits_per_component = numberToU32(dictNumber(dict, "BitsPerComponent") orelse return null) orelse return null;
        if (bits_per_component != 8) return null;
        const channels = pdfImageChannels(dict) orelse return null;
        const pixel_count = std.math.mul(usize, width, height) catch return null;
        const sample_count = std.math.mul(usize, pixel_count, channels) catch return null;
        if (sample_count == 0 or sample_count > max_stream_bytes) return null;
    }

    return .{
        .object = object,
        .dict = dict,
        .width = width,
        .height = height,
        .encoding = encoding,
        .decode = streamNeedsDecoding(dict),
        .ascii85 = hasAscii85Filter(dict),
    };
}

fn streamNeedsDecoding(dict: *c.pdfio_dict_t) bool {
    if (dictName(dict, "Filter")) |name| return std.mem.eql(u8, std.mem.span(name), "FlateDecode");
    const filters = dictArray(dict, "Filter") orelse return false;
    const count = c.pdfioArrayGetSize(filters);
    if (count == 1) {
        const name = arrayName(filters, 0) orelse return false;
        return std.mem.eql(u8, std.mem.span(name), "FlateDecode");
    }
    if (count == 2) {
        const first = arrayName(filters, 0) orelse return false;
        if (!std.mem.eql(u8, std.mem.span(first), "ASCII85Decode")) return false;
        const second = arrayName(filters, 1) orelse return false;
        return std.mem.eql(u8, std.mem.span(second), "FlateDecode");
    }
    return false;
}

fn hasAscii85Filter(dict: *c.pdfio_dict_t) bool {
    const filters = dictArray(dict, "Filter") orelse return false;
    if (c.pdfioArrayGetSize(filters) != 2) return false;
    const first = arrayName(filters, 0) orelse return false;
    return std.mem.eql(u8, std.mem.span(first), "ASCII85Decode");
}

fn imageEncoding(dict: *c.pdfio_dict_t) ?ImageEncoding {
    if (c.pdfioDictGetType(dict, "Filter") == c.PDFIO_VALTYPE_NONE) return .raw;
    if (dictName(dict, "Filter")) |name| return imageEncodingName(name);

    const filters = dictArray(dict, "Filter") orelse return null;
    const filter_count = c.pdfioArrayGetSize(filters);
    if (filter_count == 1) return imageEncodingName(arrayName(filters, 0) orelse return null);
    if (filter_count == 2) {
        const first = arrayName(filters, 0) orelse return null;
        if (!std.mem.eql(u8, std.mem.span(first), "ASCII85Decode")) return null;
        return imageEncodingName(arrayName(filters, 1) orelse return null);
    }
    return null;
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

fn objectDictValue(object: *c.pdfio_obj_t, key: [*:0]const u8) ?*c.pdfio_dict_t {
    const dict = c.pdfioObjGetDict(object) orelse return null;
    return dictValue(dict, key);
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

fn readEncodedImage(allocator: Allocator, pdf_image: ImageObject) !?[]u8 {
    const length = c.pdfioObjGetLength(pdf_image.object);
    const encoded = try readStream(allocator, pdf_image.object, pdf_image.decode, length) orelse return null;
    if (!pdf_image.ascii85 or pdf_image.decode) return encoded;

    defer allocator.free(encoded);
    return @as(?[]u8, try decodeAscii85(allocator, encoded));
}

fn decodeAscii85(allocator: Allocator, encoded: []const u8) ![]u8 {
    var decoded = std.ArrayList(u8).empty;
    errdefer decoded.deinit(allocator);

    var digits: [5]u32 = undefined;
    var digit_count: usize = 0;
    var index: usize = 0;
    while (index < encoded.len) : (index += 1) {
        const value = encoded[index];
        if (std.ascii.isWhitespace(value)) continue;
        if (value == '<' and index + 1 < encoded.len and encoded[index + 1] == '~') {
            index += 1;
            continue;
        }
        if (value == '~') {
            if (index + 1 >= encoded.len or encoded[index + 1] != '>') return error.PdfImageReadFailed;
            index += 1;
            break;
        }
        if (value == 'z') {
            if (digit_count != 0) return error.PdfImageReadFailed;
            try appendAscii85Bytes(allocator, &decoded, 0, 4);
            continue;
        }
        if (value < '!' or value > 'u') return error.PdfImageReadFailed;

        digits[digit_count] = value - '!';
        digit_count += 1;
        if (digit_count == 5) {
            const number = try ascii85Number(digits[0..]);
            try appendAscii85Bytes(allocator, &decoded, number, 4);
            digit_count = 0;
        }
    }

    if (digit_count == 1) return error.PdfImageReadFailed;
    if (digit_count > 1) {
        for (digits[digit_count..5]) |*digit| digit.* = 84;
        const number = try ascii85Number(digits[0..]);
        try appendAscii85Bytes(allocator, &decoded, number, digit_count - 1);
    }

    return decoded.toOwnedSlice(allocator);
}

fn ascii85Number(digits: []const u32) !u32 {
    var number: u64 = 0;
    for (digits) |digit| number = number * 85 + digit;
    if (number > std.math.maxInt(u32)) return error.PdfImageReadFailed;
    return @intCast(number);
}

fn appendAscii85Bytes(
    allocator: Allocator,
    decoded: *std.ArrayList(u8),
    number: u32,
    count: usize,
) !void {
    if (decoded.items.len > max_stream_bytes - count) return error.PdfStreamTooLarge;
    var bytes: [4]u8 = undefined;
    std.mem.writeInt(u32, &bytes, number, .big);
    try decoded.appendSlice(allocator, bytes[0..count]);
}

fn pdfImageChannels(dict: *c.pdfio_dict_t) ?usize {
    if (dictName(dict, "ColorSpace")) |colorspace| {
        if (std.mem.eql(u8, std.mem.span(colorspace), "DeviceRGB")) return 3;
        if (std.mem.eql(u8, std.mem.span(colorspace), "DeviceGray")) return 1;
        if (std.mem.eql(u8, std.mem.span(colorspace), "DeviceCMYK")) return 4;
        return null;
    }

    const colorspace_array = dictArray(dict, "ColorSpace") orelse return null;
    const base = arrayName(colorspace_array, 0) orelse return null;
    if (!std.mem.eql(u8, std.mem.span(base), "ICCBased")) return null;
    const profile = c.pdfioArrayGetObj(colorspace_array, 1) orelse return null;
    const profile_dict = c.pdfioObjGetDict(profile) orelse return null;
    const channels = numberToU32(dictNumber(profile_dict, "N") orelse return null) orelse return null;
    if (channels == 1 or channels == 3 or channels == 4) return channels;
    return null;
}

fn dictName(dict: *c.pdfio_dict_t, key: [*:0]const u8) ?[*:0]const u8 {
    if (c.pdfioDictGetName(dict, key)) |name| return name;
    const object = c.pdfioDictGetObj(dict, key) orelse return null;
    return c.pdfioObjGetName(object);
}

fn dictNumber(dict: *c.pdfio_dict_t, key: [*:0]const u8) ?f64 {
    const number = c.pdfioDictGetNumber(dict, key);
    if (number != 0) return number;
    return null;
}

fn dictArray(dict: *c.pdfio_dict_t, key: [*:0]const u8) ?*c.pdfio_array_t {
    if (c.pdfioDictGetArray(dict, key)) |array| return array;
    const object = c.pdfioDictGetObj(dict, key) orelse return null;
    return c.pdfioObjGetArray(object);
}

fn arrayName(array: *c.pdfio_array_t, index: usize) ?[*:0]const u8 {
    if (c.pdfioArrayGetName(array, index)) |name| return name;
    const object = c.pdfioArrayGetObj(array, index) orelse return null;
    return c.pdfioObjGetName(object);
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
            !c.pdfioDictSetRect(page_dict, "MediaBox", &page_box) or
            !c.pdfioDictSetRect(page_dict, "CropBox", &page_box)) return error.PdfCreateFailed;

        const page_stream = c.pdfioFileCreatePage(pdf, page_dict) orelse return error.PdfCreateFailed;
        const commands = try std.fmt.allocPrint(allocator, "q\n{d} 0 0 {d} 0 0 cm\n/{s} Do\nQ\n", .{ page.width, page.height, image_name_z });
        defer allocator.free(commands);

        if (!c.pdfioStreamWrite(page_stream, commands.ptr, commands.len) or !c.pdfioStreamClose(page_stream)) return error.PdfCreateFailed;
    }
    if (!c.pdfioFileClose(pdf)) return error.PdfCreateFailed;
    isFileClosed = true;

    return output.bytes.toOwnedSlice(allocator);
}
