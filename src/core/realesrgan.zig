const std = @import("std");
const builtin = @import("builtin");
const c = @import("ncnn");

const max_pixels = @import("image.zig").max_pixels;
const max_dimension = @import("image.zig").max_dimension;

const x2_param = @embedFile("../models/realesr-animevideov3-x2.param");
const x2_model = @embedFile("../models/realesr-animevideov3-x2.bin");
const x4_param = @embedFile("../models/realesr-animevideov3-x4.param");
const x4_model = @embedFile("../models/realesr-animevideov3-x4.bin");

pub const min_model_input_dimension: u32 = 32;
pub const min_ai_output_dimension: u32 = min_model_input_dimension * 2;
const tile_overlap: u32 = 10;
const tile_size: u32 = 256;

pub fn upscale(
    allocator: std.mem.Allocator,
    io: std.Io,
    input_rgb: []const u8,
    input_width: u32,
    input_height: u32,
    target_short_edge: u32,
    output_width: *u32,
    output_height: *u32,
) ![]u8 {
    if (input_width < min_model_input_dimension or input_height < min_model_input_dimension or target_short_edge == 0) return error.InvalidResize;
    const short_edge = @min(input_width, input_height);

    if (short_edge >= target_short_edge) return error.InvalidResize;
    const required_scale = (std.math.cast(u64, target_short_edge) orelse return error.InvalidResize) + short_edge - 1;

    if ((required_scale / short_edge) > 2) {
        return upscaleOnce(io, allocator, 4, input_rgb, input_width, input_height, output_width, output_height);
    }
    return upscaleOnce(io, allocator, 2, input_rgb, input_width, input_height, output_width, output_height);
}

fn upscaleOnce(
    io: std.Io,
    allocator: std.mem.Allocator,
    scale: u32,
    input_rgb: []const u8,
    input_width: u32,
    input_height: u32,
    output_width: *u32,
    output_height: *u32,
) ![]u8 {
    if (input_width < min_model_input_dimension or input_height < min_model_input_dimension) return error.InvalidResize;
    const input_width_c = std.math.cast(c_int, input_width) orelse return error.InvalidResize;
    const input_height_c = std.math.cast(c_int, input_height) orelse return error.InvalidResize;
    if (input_width > max_dimension or input_height > max_dimension) return error.InvalidResize;
    const input_pixels = std.math.mul(u64, input_width, input_height) catch return error.InvalidResize;
    if (input_pixels > max_pixels) return error.InvalidResize;
    const input_bytes_u64 = std.math.mul(u64, input_pixels, 3) catch return error.InvalidResize;
    const input_bytes = std.math.cast(usize, input_bytes_u64) orelse return error.InvalidResize;
    if (input_rgb.len < input_bytes) return error.InvalidResize;

    const output_width_u64 = std.math.mul(u64, input_width, scale) catch return error.InvalidResize;
    const output_height_u64 = std.math.mul(u64, input_height, scale) catch return error.InvalidResize;
    const output_width_value = std.math.cast(u32, output_width_u64) orelse return error.InvalidResize;
    const output_height_value = std.math.cast(u32, output_height_u64) orelse return error.InvalidResize;
    if (output_width_value > max_dimension or output_height_value > max_dimension) return error.InvalidResize;
    const output_pixels = std.math.mul(u64, output_width_u64, output_height_u64) catch return error.InvalidResize;
    if (output_pixels > max_pixels) return error.InvalidResize;
    const output_bytes_u64 = std.math.mul(u64, output_pixels, 3) catch return error.InvalidResize;
    const output_bytes = std.math.cast(usize, output_bytes_u64) orelse return error.InvalidResize;

    const tile_span = std.math.add(u32, tile_size, std.math.mul(u32, tile_overlap, 2) catch return error.InvalidResize) catch return error.InvalidResize;
    const tile_span_output = std.math.mul(u64, tile_span, scale) catch return error.InvalidResize;
    const tile_pixels_u64 = std.math.mul(u64, std.math.mul(u64, tile_span_output, tile_span_output) catch return error.InvalidResize, 3) catch return error.InvalidResize;
    const tile_pixels_count = std.math.cast(usize, tile_pixels_u64) orelse return error.InvalidResize;

    const result = try allocator.alloc(u8, output_bytes);
    errdefer allocator.free(result);
    const tile_pixels = try allocator.alloc(u8, tile_pixels_count);
    defer allocator.free(tile_pixels);

    const net = c.ncnn_net_create() orelse return error.AllocationFailed;
    defer c.ncnn_net_destroy(net);

    const option = c.ncnn_net_get_option(net) orelse return error.AllocationFailed;
    c.ncnn_option_set_num_threads(option, 1);
    c.ncnn_option_set_use_local_pool_allocator(option, 0);
    const use_vulkan = builtin.os.tag == .macos and c.furball_ncnn_vulkan_available() != 0;
    c.ncnn_option_set_use_vulkan_compute(option, @intFromBool(use_vulkan));

    const param = if (scale == 2) x2_param else x4_param;
    const model = if (scale == 2) x2_model else x4_model;

    if (c.ncnn_net_load_param_memory(net, @ptrCast(param.ptr)) != 0) return error.ModelFailed;
    if (c.ncnn_net_load_model_memory(net, @ptrCast(model.ptr)) <= 0) return error.ModelFailed;

    var y: u32 = 0;
    while (y < input_height) : (y += tile_size) {
        var x: u32 = 0;
        while (x < input_width) : (x += tile_size) {
            try io.checkCancel();

            const core_width = @min(tile_size, input_width - x);
            const core_height = @min(tile_size, input_height - y);
            const x_bounds = try tileBounds(input_width, x, core_width);
            const y_bounds = try tileBounds(input_height, y, core_height);
            const tile_x = x_bounds.start;
            const tile_y = y_bounds.start;
            const tile_end_x = x_bounds.end;
            const tile_end_y = y_bounds.end;
            const tile_width = std.math.cast(u32, tile_end_x - tile_x) orelse return error.InvalidResize;
            const tile_height = std.math.cast(u32, tile_end_y - tile_y) orelse return error.InvalidResize;
            if (tile_width < min_model_input_dimension or tile_height < min_model_input_dimension) return error.InvalidResize;
            const tile_width_c = std.math.cast(c_int, tile_width) orelse return error.InvalidResize;
            const tile_height_c = std.math.cast(c_int, tile_height) orelse return error.InvalidResize;
            const input_stride = std.math.mul(c_int, input_width_c, 3) catch return error.InvalidResize;
            const input = if (tile_x >= 0 and tile_y >= 0 and tile_end_x <= @as(i64, @intCast(input_width)) and tile_end_y <= @as(i64, @intCast(input_height))) blk: {
                const tile_x_c = std.math.cast(c_int, tile_x) orelse return error.InvalidResize;
                const tile_y_c = std.math.cast(c_int, tile_y) orelse return error.InvalidResize;
                break :blk c.ncnn_mat_from_pixels_roi(
                    input_rgb.ptr,
                    c.NCNN_MAT_PIXEL_RGB,
                    input_width_c,
                    input_height_c,
                    input_stride,
                    tile_x_c,
                    tile_y_c,
                    tile_width_c,
                    tile_height_c,
                    null,
                ) orelse return error.AllocationFailed;
            } else blk: {
                try fillReflectedTile(tile_pixels, input_rgb, input_width, input_height, x_bounds, y_bounds);
                const tile_input_stride = std.math.mul(c_int, tile_width_c, 3) catch return error.InvalidResize;
                break :blk c.ncnn_mat_from_pixels(
                    tile_pixels.ptr,
                    c.NCNN_MAT_PIXEL_RGB,
                    tile_width_c,
                    tile_height_c,
                    tile_input_stride,
                    null,
                ) orelse return error.AllocationFailed;
            };
            defer c.ncnn_mat_destroy(input);

            var mean = [_]f32{ 0, 0, 0 };
            var norm = [_]f32{ 1.0 / 255.0, 1.0 / 255.0, 1.0 / 255.0 };
            c.ncnn_mat_substract_mean_normalize(input, &mean, &norm);

            const extractor = c.ncnn_extractor_create(net) orelse return error.AllocationFailed;
            defer c.ncnn_extractor_destroy(extractor);

            if (c.ncnn_extractor_input(extractor, "data", input) != 0) return error.InferenceFailed;

            var output: c.ncnn_mat_t = null;
            defer if (output) |mat| c.ncnn_mat_destroy(mat);
            if (c.ncnn_extractor_extract(extractor, "output", &output) != 0) return error.InferenceFailed;

            const output_mat = output orelse return error.InferenceFailed;

            const width = c.ncnn_mat_get_w(output_mat);
            const height = c.ncnn_mat_get_h(output_mat);
            if (c.ncnn_mat_get_c(output_mat) != 3 or width <= 0 or height <= 0) return error.InferenceFailed;

            const width_u32 = std.math.cast(u32, width) orelse return error.InferenceFailed;
            const height_u32 = std.math.cast(u32, height) orelse return error.InferenceFailed;
            const expected_tile_width = std.math.mul(u32, tile_width, scale) catch return error.InferenceFailed;
            const expected_tile_height = std.math.mul(u32, tile_height, scale) catch return error.InferenceFailed;
            if (width_u32 != expected_tile_width or height_u32 != expected_tile_height) return error.InferenceFailed;
            const count = std.math.mul(usize, std.math.mul(usize, width_u32, height_u32) catch return error.InferenceFailed, 3) catch return error.InferenceFailed;
            if (count > tile_pixels.len) return error.InferenceFailed;
            var output_mean = [_]f32{ 0, 0, 0 };
            var output_norm = [_]f32{ 255, 255, 255 };
            c.ncnn_mat_substract_mean_normalize(output_mat, &output_mean, &output_norm);
            const output_stride = std.math.mul(c_int, width, 3) catch return error.InferenceFailed;
            c.ncnn_mat_to_pixels(output_mat, tile_pixels.ptr, c.NCNN_MAT_PIXEL_RGB, output_stride);
            try io.checkCancel();

            const core_x_i64: i64 = @intCast(x);
            const core_y_i64: i64 = @intCast(y);
            const crop_left_input = std.math.cast(u32, core_x_i64 - tile_x) orelse return error.InvalidResize;
            const crop_top_input = std.math.cast(u32, core_y_i64 - tile_y) orelse return error.InvalidResize;
            const crop_left = std.math.mul(u32, crop_left_input, scale) catch return error.InvalidResize;
            const crop_top = std.math.mul(u32, crop_top_input, scale) catch return error.InvalidResize;
            const core_width_output = std.math.mul(u32, core_width, scale) catch return error.InvalidResize;
            const core_height_output = std.math.mul(u32, core_height, scale) catch return error.InvalidResize;
            const tile_stride = std.math.mul(usize, width_u32, 3) catch return error.InvalidResize;
            const core_stride = std.math.mul(usize, core_width_output, 3) catch return error.InvalidResize;
            for (0..core_height_output) |row| {
                const source_row = std.math.add(usize, crop_top, row) catch return error.InvalidResize;
                const source_offset = std.math.add(usize, std.math.mul(usize, source_row, tile_stride) catch return error.InvalidResize, std.math.mul(usize, crop_left, 3) catch return error.InvalidResize) catch return error.InvalidResize;
                const destination_offset = try outputOffset(output_width_value, scale, x, y, row);
                const destination_end = std.math.add(usize, destination_offset, core_stride) catch return error.InvalidResize;
                const source_end = std.math.add(usize, source_offset, core_stride) catch return error.InvalidResize;
                if (source_end > count or destination_end > result.len) return error.InvalidResize;
                @memcpy(result[destination_offset..destination_end], tile_pixels[source_offset..source_end]);
            }
        }
    }

    output_width.* = output_width_value;
    output_height.* = output_height_value;
    return result;
}

fn outputOffset(output_width: u32, scale: u32, x: u32, y: u32, row: usize) !usize {
    const destination_row = std.math.add(
        u64,
        std.math.mul(u64, y, scale) catch return error.InvalidResize,
        std.math.cast(u64, row) orelse return error.InvalidResize,
    ) catch return error.InvalidResize;
    const destination_pixel = std.math.add(
        u64,
        std.math.mul(u64, destination_row, output_width) catch return error.InvalidResize,
        std.math.mul(u64, x, scale) catch return error.InvalidResize,
    ) catch return error.InvalidResize;
    return std.math.cast(usize, std.math.mul(u64, destination_pixel, 3) catch return error.InvalidResize) orelse return error.InvalidResize;
}

const TileBounds = struct {
    start: i64,
    end: i64,
};

fn tileBounds(image_extent: u32, core_start: u32, core_size: u32) !TileBounds {
    if (image_extent < min_model_input_dimension or core_size == 0) return error.InvalidResize;
    const core_end = std.math.add(u32, core_start, core_size) catch return error.InvalidResize;
    if (core_end > image_extent) return error.InvalidResize;

    const core_start_i64: i64 = @intCast(core_start);
    const core_end_i64: i64 = @intCast(core_end);
    const start = core_start_i64 - @as(i64, tile_overlap);
    var end = core_end_i64 + @as(i64, tile_overlap);
    const span = end - start;
    if (span < min_model_input_dimension) {
        end += @as(i64, min_model_input_dimension) - span;
    }

    if (end - start < min_model_input_dimension) return error.InvalidResize;
    return .{ .start = start, .end = end };
}

fn reflectCoordinate(coordinate: i64, extent: u32) !u32 {
    if (extent < 2) return error.InvalidResize;

    const last: i64 = @intCast(extent - 1);
    var value = coordinate;
    while (value < 0 or value > last) {
        value = if (value < 0) -value else 2 * last - value;
    }
    return @intCast(value);
}

fn fillReflectedTile(
    destination: []u8,
    input_rgb: []const u8,
    input_width: u32,
    input_height: u32,
    x_bounds: TileBounds,
    y_bounds: TileBounds,
) !void {
    const tile_width = std.math.cast(u32, x_bounds.end - x_bounds.start) orelse return error.InvalidResize;
    const tile_height = std.math.cast(u32, y_bounds.end - y_bounds.start) orelse return error.InvalidResize;
    const tile_pixels = std.math.mul(usize, std.math.mul(usize, tile_width, tile_height) catch return error.InvalidResize, 3) catch return error.InvalidResize;
    if (destination.len < tile_pixels) return error.InvalidResize;

    for (0..tile_height) |row| {
        const source_y = try reflectCoordinate(y_bounds.start + @as(i64, @intCast(row)), input_height);
        for (0..tile_width) |column| {
            const source_x = try reflectCoordinate(x_bounds.start + @as(i64, @intCast(column)), input_width);
            const source_pixel = std.math.add(
                usize,
                std.math.mul(usize, @intCast(source_y), input_width) catch return error.InvalidResize,
                source_x,
            ) catch return error.InvalidResize;
            const source_offset = std.math.mul(usize, source_pixel, 3) catch return error.InvalidResize;
            const destination_pixel = std.math.add(
                usize,
                std.math.mul(usize, row, tile_width) catch return error.InvalidResize,
                column,
            ) catch return error.InvalidResize;
            const destination_offset = std.math.mul(usize, destination_pixel, 3) catch return error.InvalidResize;
            @memcpy(destination[destination_offset .. destination_offset + 3], input_rgb[source_offset .. source_offset + 3]);
        }
    }
}

test "model selection reaches the requested short edge" {
    try std.testing.expectEqual(@as(u64, 2), (@as(u64, 1440) + 800 - 1) / 800);
    try std.testing.expectEqual(@as(u64, 3), (@as(u64, 2001) + 800 - 1) / 800);
}

test "tiled output rows use scaled offsets" {
    try std.testing.expectEqual(@as(usize, 0), try outputOffset(320, 2, 0, 0, 0));
    try std.testing.expectEqual(@as(usize, 320 * 128 * 2 * 3), try outputOffset(320, 2, 0, 128, 0));
    try std.testing.expectEqual(@as(usize, (320 * 191 * 2 + 319 * 2) * 3), try outputOffset(320, 2, 319, 191, 0));
}

test "edge tile bounds expand to the model minimum" {
    const bounds = try tileBounds(257, 256, 1);
    try std.testing.expectEqual(@as(i64, 32), bounds.end - bounds.start);
    try std.testing.expectEqual(@as(i64, 246), bounds.start);
    try std.testing.expectEqual(@as(i64, 278), bounds.end);
}

test "tile padding reflects both image edges" {
    try std.testing.expectEqual(@as(u32, 1), try reflectCoordinate(-1, 32));
    try std.testing.expectEqual(@as(u32, 2), try reflectCoordinate(-2, 32));
    try std.testing.expectEqual(@as(u32, 30), try reflectCoordinate(32, 32));
    try std.testing.expectEqual(@as(u32, 29), try reflectCoordinate(33, 32));
}

test "tile padding copies reflected RGB pixels" {
    const input = [_]u8{
        1, 2, 3, 4,  5,  6,
        7, 8, 9, 10, 11, 12,
    };
    var output: [4 * 4 * 3]u8 = undefined;
    try fillReflectedTile(&output, &input, 2, 2, .{ .start = -1, .end = 3 }, .{ .start = -1, .end = 3 });
    try std.testing.expectEqualSlices(u8, &[_]u8{
        10, 11, 12, 7, 8, 9, 10, 11, 12, 7, 8, 9,
        4,  5,  6,  1, 2, 3, 4,  5,  6,  1, 2, 3,
        10, 11, 12, 7, 8, 9, 10, 11, 12, 7, 8, 9,
        4,  5,  6,  1, 2, 3, 4,  5,  6,  1, 2, 3,
    }, &output);
}
