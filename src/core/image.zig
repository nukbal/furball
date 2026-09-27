const std = @import("std");

const mozjpeg = @import("mozjpeg");
const stb = @import("stb");
const webp = @import("webp");
const protocol = @import("protocol.zig");
const realesrgan = @import("realesrgan.zig");
const storage = @import("storage.zig");

const Allocator = std.mem.Allocator;

pub const max_pixels: u64 = 200 * 1000 * 1000;
pub const max_dimension: u32 = 65_500;

const max_input_bytes: usize = 512 * 1024 * 1024;
const max_thumbnail_bytes: usize = 192 * 1024;
const max_decoded_bytes: u64 = 600 * 1000 * 1000;
const channels: usize = 3;

pub const ImageInfo = struct {
    width: u32,
    height: u32,

    pub fn shortEdge(self: ImageInfo) u32 {
        return @min(self.width, self.height);
    }
};

pub fn dimensions(alloc: Allocator, io: std.Io, source: []const u8) !ImageInfo {
    const stat = std.Io.Dir.cwd().statFile(io, source, .{ .follow_symlinks = false }) catch return error.SourceNotFound;
    if (stat.kind != .file) return error.InvalidImageSource;
    if (stat.size > max_input_bytes) return error.ImageInputTooLarge;
    const header_size: usize = @intCast(@min(stat.size, 256 * 1024));
    const header = try alloc.alloc(u8, header_size);
    defer alloc.free(header);
    var file = std.Io.Dir.cwd().openFile(io, source, .{ .follow_symlinks = false }) catch return error.ImageReadFailed;
    defer file.close(io);
    var length: usize = 0;
    while (length < header.len) {
        const count = file.readPositional(io, &.{header[length..]}, length) catch return error.ImageReadFailed;
        if (count == 0) break;
        length += count;
    }
    if (length == stat.size) return inspectMemory(header[0..length]);
    if (inspectMemory(header[0..length])) |info| return info else |_| {}
    const bytes = try readBytes(alloc, io, source);
    defer alloc.free(bytes);
    return inspectMemory(bytes);
}

pub fn encode(
    alloc: Allocator,
    io: std.Io,
    source: []const u8,
    destination: []const u8,
    config: protocol.Config,
    nonce: u64,
) !void {
    const output = try encodeBytes(alloc, io, source, config, nonce, null);
    defer alloc.free(output);

    try storage.writeAtomic(io, destination, output);
}

pub fn encodeBytes(alloc: Allocator, io: std.Io, source: []const u8, config: protocol.Config, nonce: u64) ![]u8 {
    _ = nonce;
    try io.checkCancel();
    const input = try readBytes(alloc, io, source);
    defer alloc.free(input);

    return encodeBytesFromMemory(alloc, io, input, config);
}

pub fn encodeBytesFromMemory(alloc: Allocator, io: std.Io, input: []const u8, config: protocol.Config) ![]u8 {
    var source = try decode(alloc, input);
    defer source.deinit(alloc);
    try io.checkCancel();

    return encodeDecoded(alloc, io, &source, config);
}

pub fn encodeRgb(
    alloc: Allocator,
    io: std.Io,
    width: u32,
    height: u32,
    pixels: []const u8,
    config: protocol.Config,
) ![]u8 {
    const checked_width = std.math.cast(c_int, width) orelse return error.ImageDimensionsTooLarge;
    const checked_height = std.math.cast(c_int, height) orelse return error.ImageDimensionsTooLarge;
    const info = try checkedInfo(checked_width, checked_height);
    const byte_count = try byteCount(info);
    if (pixels.len < byte_count) return error.ImageDecodeFailed;

    const owned = try alloc.alloc(u8, byte_count);
    @memcpy(owned, pixels[0..byte_count]);
    var source = DecodedImage{ .pixels = owned, .width = info.width, .height = info.height };
    defer source.deinit(alloc);
    try io.checkCancel();

    return encodeDecoded(alloc, io, &source, config);
}

fn encodeDecoded(alloc: Allocator, io: std.Io, source: *DecodedImage, config: protocol.Config) ![]u8 {
    try io.checkCancel();

    const requested = config.width;
    if (source.shortEdge() < requested) {
        if (config.ai) {
            const short_edge = source.shortEdge();
            if (short_edge < realesrgan.min_model_input_dimension and requested < realesrgan.min_ai_output_dimension) {
                try source.resizeShortEdgeExact(alloc, requested);
                return source.encodeJpeg(alloc, config.quality, null);
            }

            if (short_edge < realesrgan.min_model_input_dimension) {
                try source.resizeShortEdgeExact(alloc, realesrgan.min_model_input_dimension);
            }

            var enhanced_width: u32 = 0;
            var enhanced_height: u32 = 0;
            const enhanced_pixels = try realesrgan.upscale(
                alloc,
                io,
                source.pixels,
                source.width,
                source.height,
                requested,
                &enhanced_width,
                &enhanced_height,
            );
            var enhanced = DecodedImage{
                .pixels = enhanced_pixels,
                .width = enhanced_width,
                .height = enhanced_height,
            };
            defer enhanced.deinit(alloc);

            if (enhanced.shortEdge() != requested) try enhanced.resizeShortEdgeExact(alloc, requested);

            return enhanced.encodeJpeg(alloc, config.quality, null);
        }
        return source.encodeJpeg(alloc, config.quality, null);
    }

    if (source.shortEdge() > requested) try source.resizeShortEdge(alloc, requested);

    return source.encodeJpeg(alloc, config.quality, null);
}

pub fn thumbnail(alloc: Allocator, io: std.Io, source: []const u8, destination: []const u8) !void {
    const input = try readBytes(alloc, io, source);
    defer alloc.free(input);

    const output = try thumbnailBytes(input);
    defer alloc.free(output);

    try storage.writeAtomic(io, destination, output);
}

pub fn thumbnailBytes(alloc: Allocator, input: []const u8) ![]u8 {
    var decoded = try decode(alloc, input);
    defer decoded.deinit(alloc);

    try decoded.resizeShortEdge(alloc, 250);

    return decoded.encodeJpeg(alloc, 65, max_thumbnail_bytes);
}

pub fn thumbnailBytesFromRgb(alloc: Allocator, width: u32, height: u32, pixels: []const u8) ![]u8 {
    const checked_width = std.math.cast(c_int, width) orelse return error.ImageDimensionsTooLarge;
    const checked_height = std.math.cast(c_int, height) orelse return error.ImageDimensionsTooLarge;

    const info = try checkedInfo(checked_width, checked_height);
    const byte_count = try byteCount(info);

    if (pixels.len < byte_count) return error.ImageDecodeFailed;

    const owned = try alloc.alloc(u8, byte_count);
    @memcpy(owned, pixels[0..byte_count]);

    var decoded = DecodedImage{ .pixels = owned, .width = info.width, .height = info.height };
    defer decoded.deinit(alloc);

    try decoded.resizeShortEdge(alloc, 250);

    return decoded.encodeJpeg(alloc, 65, max_thumbnail_bytes);
}

fn decode(alloc: Allocator, bytes: []const u8) !DecodedImage {
    const info = try inspectMemory(bytes);
    if (isWebp(bytes)) {
        const byte_count = try byteCount(info);
        const pixels = try alloc.alloc(u8, byte_count);
        errdefer alloc.free(pixels);

        const decoded = webp.WebPDecodeRGBInto(
            bytes.ptr,
            bytes.len,
            pixels.ptr,
            byte_count,
            @intCast(try stride(info.width)),
        ) orelse return error.ImageDecodeFailed;
        _ = decoded;

        return .{ .pixels = pixels, .width = info.width, .height = info.height };
    }

    var width: c_int = 0;
    var height: c_int = 0;
    var source_channels: c_int = 0;

    const decoded = stb.stbi_load_from_memory(bytes.ptr, @intCast(bytes.len), &width, &height, &source_channels, @intCast(channels)) orelse return error.ImageDecodeFailed;
    defer stb.stbi_image_free(@ptrCast(decoded));

    const decoded_info = try checkedInfo(width, height);
    if (decoded_info.width != info.width or decoded_info.height != info.height) return error.ImageDecodeFailed;

    const byte_count = try byteCount(decoded_info);
    const pixels = try alloc.alloc(u8, byte_count);
    @memcpy(pixels, decoded[0..byte_count]);

    return .{
        .pixels = pixels,
        .width = decoded_info.width,
        .height = decoded_info.height,
    };
}

fn readBytes(alloc: Allocator, io: std.Io, source: []const u8) ![]u8 {
    const stat = std.Io.Dir.cwd().statFile(io, source, .{ .follow_symlinks = false }) catch return error.SourceNotFound;
    if (stat.kind == .sym_link or stat.kind != .file) return error.InvalidImageSource;
    if (stat.size > max_input_bytes) return error.ImageInputTooLarge;

    const bytes = std.Io.Dir.cwd().readFileAlloc(io, source, alloc, .limited(max_input_bytes + 1)) catch return error.ImageReadFailed;
    if (bytes.len > max_input_bytes) {
        alloc.free(bytes);
        return error.ImageInputTooLarge;
    }
    return bytes;
}

const DecodedImage = struct {
    pixels: []u8,
    width: u32,
    height: u32,

    fn deinit(self: *DecodedImage, alloc: Allocator) void {
        alloc.free(self.pixels);
        self.* = undefined;
    }

    fn shortEdge(self: *const DecodedImage) u32 {
        return @min(self.width, self.height);
    }

    fn resizeShortEdge(self: *DecodedImage, alloc: Allocator, target: u32) !void {
        const next = try resizeInfo(.{ .width = self.width, .height = self.height }, target);
        try self.resizeTo(alloc, next);
    }

    fn resizeShortEdgeExact(self: *DecodedImage, alloc: Allocator, target: u32) !void {
        const next = try resizeInfoExact(.{ .width = self.width, .height = self.height }, target);
        try self.resizeTo(alloc, next);
    }

    fn resizeTo(self: *DecodedImage, alloc: Allocator, next: ImageInfo) !void {
        if (next.width == self.width and next.height == self.height) return;

        const byte_count = try byteCount(next);
        const resized = try alloc.alloc(u8, byte_count);
        errdefer alloc.free(resized);

        const input_stride = try stride(self.width);
        const output_stride = try stride(next.width);
        const resized_result = stb.stbir_resize_uint8_linear(
            self.pixels.ptr,
            @intCast(self.width),
            @intCast(self.height),
            @intCast(input_stride),
            resized.ptr,
            @intCast(next.width),
            @intCast(next.height),
            @intCast(output_stride),
            @intCast(stb.STBIR_RGB),
        );
        if (resized_result == null) return error.ImageResizeFailed;
        alloc.free(self.pixels);

        self.pixels = resized;
        self.width = next.width;
        self.height = next.height;
    }

    fn encodeJpeg(self: *const DecodedImage, alloc: Allocator, quality: u8, max_output: ?usize) ![]u8 {
        const stride_bytes = try stride(self.width);
        const row_bytes = try std.math.mul(usize, stride_bytes, self.height);
        if (self.pixels.len < row_bytes or self.width > 65_535 or self.height > 65_535) return error.ImageEncodeFailed;

        var error_context = JpegErrorContext{ .cinfo = std.mem.zeroes(mozjpeg.struct_jpeg_compress_struct) };
        error_context.cinfo.err = mozjpeg.jpeg_std_error(&error_context.base);
        error_context.base.error_exit = jpegErrorExit;
        error_context.cinfo.client_data = @ptrCast(&error_context);
        if (mozjpeg.setjmp(@ptrCast(&error_context.jump)) != 0) {
            if (error_context.created) mozjpeg.jpeg_destroy_compress(&error_context.cinfo);
            freeJpegBuffer(&error_context);
            return error.ImageEncodeFailed;
        }

        mozjpeg.jpeg_CreateCompress(&error_context.cinfo, mozjpeg.JPEG_LIB_VERSION, @sizeOf(mozjpeg.struct_jpeg_compress_struct));
        error_context.created = true;
        mozjpeg.jpeg_mem_dest(&error_context.cinfo, &error_context.encoded, &error_context.encoded_size);
        error_context.cinfo.image_width = @intCast(self.width);
        error_context.cinfo.image_height = @intCast(self.height);
        error_context.cinfo.input_components = @intCast(channels);
        error_context.cinfo.in_color_space = mozjpeg.JCS_RGB;
        mozjpeg.jpeg_set_defaults(&error_context.cinfo);
        mozjpeg.jpeg_set_quality(&error_context.cinfo, @intCast(quality), 1);
        mozjpeg.jpeg_start_compress(&error_context.cinfo, 1);
        var row: [1]mozjpeg.JSAMPROW = undefined;
        while (error_context.cinfo.next_scanline < error_context.cinfo.image_height) {
            const offset = std.math.mul(usize, @intCast(error_context.cinfo.next_scanline), stride_bytes) catch {
                mozjpeg.jpeg_destroy_compress(&error_context.cinfo);
                error_context.created = false;
                freeJpegBuffer(&error_context);
                return error.ImageEncodeFailed;
            };
            row[0] = @ptrCast(self.pixels.ptr + offset);
            if (mozjpeg.jpeg_write_scanlines(&error_context.cinfo, @ptrCast(&row), 1) != 1) {
                mozjpeg.jpeg_destroy_compress(&error_context.cinfo);
                error_context.created = false;
                freeJpegBuffer(&error_context);
                return error.ImageEncodeFailed;
            }
        }
        mozjpeg.jpeg_finish_compress(&error_context.cinfo);
        mozjpeg.jpeg_destroy_compress(&error_context.cinfo);
        error_context.created = false;

        const encoded_bytes = error_context.encoded orelse return error.ImageEncodeFailed;
        const encoded_length = std.math.cast(usize, error_context.encoded_size) orelse {
            freeJpegBuffer(&error_context);
            return error.ImageOutputTooLarge;
        };
        if (max_output) |limit| if (encoded_length > limit) {
            freeJpegBuffer(&error_context);
            return error.ImageOutputTooLarge;
        };
        const result = alloc.alloc(u8, encoded_length) catch |err| {
            freeJpegBuffer(&error_context);
            return err;
        };
        @memcpy(result, encoded_bytes[0..encoded_length]);
        freeJpegBuffer(&error_context);
        return result;
    }
};

pub fn inspectMemory(bytes: []const u8) !ImageInfo {
    if (bytes.len == 0 or bytes.len > max_input_bytes) return error.InvalidImage;

    if (isWebp(bytes)) {
        var width: c_int = 0;
        var height: c_int = 0;
        if (webp.WebPGetInfo(bytes.ptr, bytes.len, &width, &height) == 0) return error.ImageDecodeFailed;
        return checkedInfo(width, height);
    }

    var width: c_int = 0;
    var height: c_int = 0;
    var channels_found: c_int = 0;
    if (stb.stbi_info_from_memory(bytes.ptr, @intCast(bytes.len), &width, &height, &channels_found) == 0) return error.ImageDecodeFailed;
    return checkedInfo(width, height);
}

fn isWebp(bytes: []const u8) bool {
    return bytes.len >= 12 and
        std.mem.eql(u8, bytes[0..4], "RIFF") and
        std.mem.eql(u8, bytes[8..12], "WEBP");
}

fn checkedInfo(width: c_int, height: c_int) !ImageInfo {
    if (width <= 0 or height <= 0) return error.ImageDimensionsTooLarge;

    const checked_width = std.math.cast(u32, width) orelse return error.ImageDimensionsTooLarge;
    const checked_height = std.math.cast(u32, height) orelse return error.ImageDimensionsTooLarge;
    if (checked_width > max_dimension or checked_height > max_dimension) return error.ImageDimensionsTooLarge;

    const pixels = std.math.mul(u64, checked_width, checked_height) catch return error.ImageDimensionsTooLarge;
    if (pixels > max_pixels) return error.ImagePixelsTooLarge;

    const decoded_bytes = std.math.mul(u64, pixels, channels) catch return error.ImageAllocationTooLarge;
    if (decoded_bytes > max_decoded_bytes) return error.ImageAllocationTooLarge;

    return .{ .width = checked_width, .height = checked_height };
}

fn byteCount(info: ImageInfo) !usize {
    const pixels = std.math.mul(u64, info.width, info.height) catch return error.ImageAllocationTooLarge;
    const bytes = std.math.mul(u64, pixels, channels) catch return error.ImageAllocationTooLarge;

    if (bytes > max_decoded_bytes) return error.ImageAllocationTooLarge;

    return std.math.cast(usize, bytes) orelse return error.ImageAllocationTooLarge;
}

fn stride(width: u32) !usize {
    const value = std.math.mul(u64, width, channels) catch return error.ImageDimensionsTooLarge;
    return std.math.cast(usize, value) orelse return error.ImageDimensionsTooLarge;
}

fn resizeInfo(info: ImageInfo, target: u32) !ImageInfo {
    if (target == 0) return error.InvalidResize;
    if (info.shortEdge() <= target) return info;

    const short: u64 = info.shortEdge();
    const long: u64 = @max(info.width, info.height);
    const scaled_long = std.math.mul(u64, long, target) catch return error.ImageDimensionsTooLarge;
    const output_long = scaled_long / short;

    if (output_long == 0 or output_long > max_dimension) return error.ImageDimensionsTooLarge;

    const output_long_u32 = std.math.cast(u32, output_long) orelse return error.ImageDimensionsTooLarge;

    return if (info.width >= info.height)
        .{ .width = output_long_u32, .height = target }
    else
        .{ .width = target, .height = output_long_u32 };
}

fn resizeInfoExact(info: ImageInfo, target: u32) !ImageInfo {
    if (target == 0) return error.InvalidResize;
    if (info.shortEdge() == target) return info;

    const short: u64 = info.shortEdge();
    const long: u64 = @max(info.width, info.height);
    const scaled_long = std.math.mul(u64, long, target) catch return error.ImageDimensionsTooLarge;
    const output_long = scaled_long / short;

    if (output_long == 0 or output_long > max_dimension) return error.ImageDimensionsTooLarge;

    const output_long_u32 = std.math.cast(u32, output_long) orelse return error.ImageDimensionsTooLarge;

    return if (info.width >= info.height)
        .{ .width = output_long_u32, .height = target }
    else
        .{ .width = target, .height = output_long_u32 };
}

const JpegErrorContext = struct {
    cinfo: mozjpeg.struct_jpeg_compress_struct,
    base: mozjpeg.struct_jpeg_error_mgr = .{},
    jump: mozjpeg.jmp_buf = undefined,
    encoded: ?[*]u8 = null,
    encoded_size: c_ulong = 0,
    created: bool = false,
};

fn jpegErrorExit(cinfo: mozjpeg.j_common_ptr) callconv(.c) void {
    const context = cinfo.*.client_data orelse unreachable;
    const error_context: *JpegErrorContext = @ptrCast(@alignCast(context));
    mozjpeg.longjmp(@ptrCast(&error_context.jump), 1);
}

fn freeJpegBuffer(context: *JpegErrorContext) void {
    if (context.encoded) |encoded| {
        std.c.free(@ptrCast(encoded));
        context.encoded = null;
    }
}

test "image dimensions preserve aspect ratio while shrinking" {
    try std.testing.expectEqual(ImageInfo{ .width = 1600, .height = 800 }, resizeInfo(.{ .width = 3200, .height = 1600 }, 800));
    try std.testing.expectEqual(ImageInfo{ .width = 800, .height = 400 }, resizeInfo(.{ .width = 3200, .height = 1600 }, 400));
}

test "png decode resize and mozjpeg encode complete" {
    const alloc = std.testing.allocator;
    const encoded = "iVBORw0KGgoAAAANSUhEUgAAACAAAAAYEAYAAADLwyN3AAAAIGNIUk0AAHomAACAhAAA+gAAAIDoAAB1MAAA6mAAADqYAAAXcJy6UTwAAAAGYktHRP///////wlY99wAAAAHdElNRQfqCQkLLzg9WNCtAAAAJXRFWHRkYXRlOmNyZWF0ZQAyMDI2LTA5LTA5VDExOjQ3OjU2KzAwOjAwRPnEJwAAACV0RVh0ZGF0ZTptb2RpZnkAMjAyNi0wOS0wOVQxMTo0Nzo1NiswMDowMDWkfJsAAAAodEVYdGRhdGU6dGltZXN0YW1wADIwMjYtMDktMDlUMTE6NDc6NTYrMDA6MDBisV1EAAAAeElEQVRYw+2YwQ3AMAgDWykRKPlllq5Bf+HXztrROgaPcyZA6OwYn2tdV+Z3UF8bYbs91WMUL6C/1WOULsATTcAM241NgO1OJmCEs01whqUkQCZghLNNcCoI0SVwu0wQTYA8gP4LSAJKgvBbQBJQHwBvhNQJwoPQDwVkG0Y3AfsrAAAAAElFTkSuQmCC";

    const input = try alloc.alloc(u8, std.base64.standard.Decoder.calcSizeForSlice(encoded) catch unreachable);
    defer alloc.free(input);

    try std.base64.standard.Decoder.decode(input, encoded);
    const output = try encodeBytesFromMemory(std.testing.allocator, std.testing.io, input, .{ .width = 12, .quality = 88, .ai = false });
    defer alloc.free(output);

    try std.testing.expect(output.len > 2);
    try std.testing.expectEqualSlices(u8, "\xff\xd8", output[0..2]);
    try std.testing.expectEqual(ImageInfo{ .width = 16, .height = 12 }, try inspectMemory(output));
}

test "webp decode and mozjpeg encode complete" {
    const alloc = std.testing.allocator;
    const encoded = "UklGRh4AAABXRUJQVlA4TBEAAAAvAAAAAAfQ//73v/+BiOh/AAA=";

    const input = try alloc.alloc(u8, std.base64.standard.Decoder.calcSizeForSlice(encoded) catch unreachable);
    defer alloc.free(input);
    try std.base64.standard.Decoder.decode(input, encoded);

    try std.testing.expectEqual(ImageInfo{ .width = 1, .height = 1 }, try inspectMemory(input));

    const output = try encodeBytesFromMemory(alloc, std.testing.io, input, .{ .width = 1, .quality = 88, .ai = false });
    defer alloc.free(output);

    try std.testing.expectEqualSlices(u8, "\xff\xd8", output[0..2]);
    try std.testing.expectEqual(ImageInfo{ .width = 1, .height = 1 }, try inspectMemory(output));
}
