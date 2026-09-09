const std = @import("std");

const mozjpeg = @import("mozjpeg");
const stb = @import("stb");
const protocol = @import("protocol.zig");
const realesrgan = @import("realesrgan.zig");
const storage = @import("storage.zig");

pub const max_input_bytes: usize = 512 * 1024 * 1024;
pub const max_thumbnail_bytes: usize = 192 * 1024;
pub const max_pixels: u64 = 200 * 1000 * 1000;
pub const max_dimension: u32 = 65_500;
pub const max_decoded_bytes: u64 = 600 * 1000 * 1000;
const channels: usize = 3;

pub const ImageInfo = struct {
    width: u32,
    height: u32,

    pub fn shortEdge(self: ImageInfo) u32 {
        return @min(self.width, self.height);
    }
};

pub const Processor = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    ai_models: ?*const realesrgan.Models = null,

    pub fn dimensions(self: Processor, source: []const u8) !ImageInfo {
        const bytes = try self.readBytes(source);
        defer self.allocator.free(bytes);
        return inspectMemory(bytes);
    }

    pub fn encode(
        self: Processor,
        source: []const u8,
        destination: []const u8,
        config: protocol.Config,
        nonce: u64,
    ) !void {
        const output = try self.encodeBytes(source, config, nonce);
        defer self.allocator.free(output);
        try storage.writeAtomic(self.io, destination, output);
    }

    pub fn encodeBytes(self: Processor, source: []const u8, config: protocol.Config, nonce: u64) ![]u8 {
        _ = nonce;
        const input = try self.readBytes(source);
        defer self.allocator.free(input);
        return self.encodeBytesFromMemory(input, config);
    }

    pub fn encodeBytesFromMemory(self: Processor, input: []const u8, config: protocol.Config) ![]u8 {
        var source = try self.decode(input);
        defer source.deinit();

        const requested = config.width;
        if (source.shortEdge() < requested) {
            if (config.ai) {
                const models = self.ai_models orelse return error.AiUnavailable;
                var enhanced_width: u32 = 0;
                var enhanced_height: u32 = 0;
                const enhanced_pixels = try models.upscale(
                    self.allocator,
                    source.pixels,
                    source.width,
                    source.height,
                    requested,
                    &enhanced_width,
                    &enhanced_height,
                );
                var enhanced = DecodedImage{
                    .allocator = self.allocator,
                    .pixels = enhanced_pixels,
                    .width = enhanced_width,
                    .height = enhanced_height,
                };
                defer enhanced.deinit();
                if (enhanced.shortEdge() > requested) try enhanced.resizeShortEdge(requested);
                return enhanced.encodeJpeg(self.allocator, config.quality, null);
            }
            return source.encodeJpeg(self.allocator, config.quality, null);
        }

        if (source.shortEdge() > requested) try source.resizeShortEdge(requested);
        return source.encodeJpeg(self.allocator, config.quality, null);
    }

    pub fn thumbnail(self: Processor, source: []const u8, destination: []const u8) !void {
        const input = try self.readBytes(source);
        defer self.allocator.free(input);
        const output = try self.thumbnailBytes(input);
        defer self.allocator.free(output);
        try storage.writeAtomic(self.io, destination, output);
    }

    pub fn thumbnailBytes(self: Processor, input: []const u8) ![]u8 {
        var decoded = try self.decode(input);
        defer decoded.deinit();
        try decoded.resizeShortEdge(250);
        return decoded.encodeJpeg(self.allocator, 65, max_thumbnail_bytes);
    }

    fn decode(self: Processor, bytes: []const u8) !DecodedImage {
        const info = try inspectMemory(bytes);
        var width: c_int = 0;
        var height: c_int = 0;
        var source_channels: c_int = 0;
        const decoded = stb.stbi_load_from_memory(bytes.ptr, @intCast(bytes.len), &width, &height, &source_channels, @intCast(channels)) orelse return error.ImageDecodeFailed;
        defer stb.stbi_image_free(@ptrCast(decoded));
        const decoded_info = try checkedInfo(width, height);
        if (decoded_info.width != info.width or decoded_info.height != info.height) return error.ImageDecodeFailed;
        const byte_count = try byteCount(decoded_info);
        const pixels = try self.allocator.alloc(u8, byte_count);
        @memcpy(pixels, decoded[0..byte_count]);
        return .{
            .allocator = self.allocator,
            .pixels = pixels,
            .width = decoded_info.width,
            .height = decoded_info.height,
        };
    }

    fn readBytes(self: Processor, source: []const u8) ![]u8 {
        const stat = std.Io.Dir.cwd().statFile(self.io, source, .{ .follow_symlinks = false }) catch return error.SourceNotFound;
        if (stat.kind == .sym_link or stat.kind != .file) return error.InvalidImageSource;
        if (stat.size > max_input_bytes) return error.ImageInputTooLarge;
        const bytes = std.Io.Dir.cwd().readFileAlloc(self.io, source, self.allocator, .limited(max_input_bytes + 1)) catch return error.ImageReadFailed;
        if (bytes.len > max_input_bytes) {
            self.allocator.free(bytes);
            return error.ImageInputTooLarge;
        }
        return bytes;
    }
};

const DecodedImage = struct {
    allocator: std.mem.Allocator,
    pixels: []u8,
    width: u32,
    height: u32,

    fn deinit(self: *DecodedImage) void {
        self.allocator.free(self.pixels);
        self.* = undefined;
    }

    fn shortEdge(self: *const DecodedImage) u32 {
        return @min(self.width, self.height);
    }

    fn resizeShortEdge(self: *DecodedImage, target: u32) !void {
        const next = try resizeInfo(.{ .width = self.width, .height = self.height }, target);
        if (next.width == self.width and next.height == self.height) return;
        const byte_count = try byteCount(next);
        const resized = try self.allocator.alloc(u8, byte_count);
        errdefer self.allocator.free(resized);
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
        self.allocator.free(self.pixels);
        self.pixels = resized;
        self.width = next.width;
        self.height = next.height;
    }

    fn encodeJpeg(self: *const DecodedImage, allocator: std.mem.Allocator, quality: u8, max_output: ?usize) ![]u8 {
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
        const result = allocator.alloc(u8, encoded_length) catch |err| {
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
    var width: c_int = 0;
    var height: c_int = 0;
    var channels_found: c_int = 0;
    if (stb.stbi_info_from_memory(bytes.ptr, @intCast(bytes.len), &width, &height, &channels_found) == 0) return error.ImageDecodeFailed;
    return checkedInfo(width, height);
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
    const encoded = "iVBORw0KGgoAAAANSUhEUgAAACAAAAAYEAYAAADLwyN3AAAAIGNIUk0AAHomAACAhAAA+gAAAIDoAAB1MAAA6mAAADqYAAAXcJy6UTwAAAAGYktHRP///////wlY99wAAAAHdElNRQfqCQkLLzg9WNCtAAAAJXRFWHRkYXRlOmNyZWF0ZQAyMDI2LTA5LTA5VDExOjQ3OjU2KzAwOjAwRPnEJwAAACV0RVh0ZGF0ZTptb2RpZnkAMjAyNi0wOS0wOVQxMTo0Nzo1NiswMDowMDWkfJsAAAAodEVYdGRhdGU6dGltZXN0YW1wADIwMjYtMDktMDlUMTE6NDc6NTYrMDA6MDBisV1EAAAAeElEQVRYw+2YwQ3AMAgDWykRKPlllq5Bf+HXztrROgaPcyZA6OwYn2tdV+Z3UF8bYbs91WMUL6C/1WOULsATTcAM241NgO1OJmCEs01whqUkQCZghLNNcCoI0SVwu0wQTYA8gP4LSAJKgvBbQBJQHwBvhNQJwoPQDwVkG0Y3AfsrAAAAAElFTkSuQmCC";
    const input = try std.testing.allocator.alloc(u8, std.base64.standard.Decoder.calcSizeForSlice(encoded) catch unreachable);
    defer std.testing.allocator.free(input);
    try std.base64.standard.Decoder.decode(input, encoded);
    const output = try (Processor{ .allocator = std.testing.allocator, .io = std.testing.io }).encodeBytesFromMemory(input, .{ .width = 12, .quality = 88, .ai = false });
    defer std.testing.allocator.free(output);
    try std.testing.expect(output.len > 2);
    try std.testing.expectEqualSlices(u8, "\xff\xd8", output[0..2]);
    try std.testing.expectEqual(ImageInfo{ .width = 16, .height = 12 }, try inspectMemory(output));

    var models = realesrgan.Models.init();
    const ai_output = try (Processor{ .allocator = std.testing.allocator, .io = std.testing.io, .ai_models = &models }).encodeBytesFromMemory(input, .{ .width = 48, .quality = 88, .ai = true });
    defer std.testing.allocator.free(ai_output);
    try std.testing.expectEqual(ImageInfo{ .width = 64, .height = 48 }, try inspectMemory(ai_output));
}
