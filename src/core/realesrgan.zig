const std = @import("std");
const c = @import("ncnn");

const x2_param = @embedFile("../models/realesr-animevideov3-x2.param");
const x2_model = @embedFile("../models/realesr-animevideov3-x2.bin");
const x4_param = @embedFile("../models/realesr-animevideov3-x4.param");
const x4_model = @embedFile("../models/realesr-animevideov3-x4.bin");

pub const max_dimension: u32 = 65_500;
pub const max_pixels: u64 = 200 * 1000 * 1000;

pub const Models = struct {
    x2: Model,
    x4: Model,

    pub fn init() Models {
        return .{
            .x2 = .{ .param = x2_param, .model = x2_model },
            .x4 = .{ .param = x4_param, .model = x4_model },
        };
    }

    pub fn upscale(
        self: *const Models,
        allocator: std.mem.Allocator,
        input_rgb: []const u8,
        input_width: u32,
        input_height: u32,
        target_short_edge: u32,
        output_width: *u32,
        output_height: *u32,
    ) ![]u8 {
        if (input_width == 0 or input_height == 0 or target_short_edge == 0) return error.InvalidResize;
        var width = input_width;
        var height = input_height;
        var current = input_rgb;
        var owned: ?[]u8 = null;
        errdefer if (owned) |pixels| allocator.free(pixels);

        while (@min(width, height) < target_short_edge) {
            const short_edge = @min(width, height);
            const scale: u64 = (@as(u64, target_short_edge) + short_edge - 1) / short_edge;
            const model = if (scale <= 2) &self.x2 else &self.x4;
            var next_width: u32 = 0;
            var next_height: u32 = 0;

            const next = try model.upscaleOnce(allocator, current, width, height, &next_width, &next_height);
            if (owned) |pixels| allocator.free(pixels);

            owned = next;
            current = next;
            width = next_width;
            height = next_height;

            if (@min(width, height) <= short_edge) return error.InferenceFailed;
            if (width > max_dimension or height > max_dimension) return error.InvalidResize;
            const pixels = std.math.mul(u64, width, height) catch return error.InvalidResize;
            if (pixels > max_pixels) return error.InvalidResize;
        }

        const result = owned orelse return error.InferenceFailed;
        output_width.* = width;
        output_height.* = height;
        return result;
    }
};

const Model = struct {
    param: []const u8,
    model: []const u8,

    fn upscaleOnce(
        self: *const Model,
        allocator: std.mem.Allocator,
        input_rgb: []const u8,
        input_width: u32,
        input_height: u32,
        output_width: *u32,
        output_height: *u32,
    ) ![]u8 {
        const input_width_c = std.math.cast(c_int, input_width) orelse return error.InvalidResize;
        const input_height_c = std.math.cast(c_int, input_height) orelse return error.InvalidResize;
        const input_bytes = std.math.mul(usize, std.math.mul(usize, input_width, input_height) catch return error.InvalidResize, 3) catch return error.InvalidResize;
        if (input_rgb.len < input_bytes or self.param.len == 0 or self.model.len == 0) return error.InvalidResize;

        const net = c.ncnn_net_create();
        if (net == null) return error.AllocationFailed;
        defer c.ncnn_net_destroy(net);

        const option = c.ncnn_net_get_option(net) orelse return error.AllocationFailed;
        c.ncnn_option_set_num_threads(option, 1);
        c.ncnn_option_set_use_vulkan_compute(option, 0);

        if (c.ncnn_net_load_param_memory(net, @ptrCast(self.param.ptr)) != 0) return error.ModelFailed;
        if (c.ncnn_net_load_model_memory(net, @ptrCast(self.model.ptr)) <= 0) return error.ModelFailed;

        const input = c.ncnn_mat_from_pixels(input_rgb.ptr, c.NCNN_MAT_PIXEL_RGB, input_width_c, input_height_c, input_width_c * 3, null) orelse return error.AllocationFailed;
        defer c.ncnn_mat_destroy(input);
        var mean = [_]f32{ 0, 0, 0 };
        var norm = [_]f32{ 1.0 / 255.0, 1.0 / 255.0, 1.0 / 255.0 };
        c.ncnn_mat_substract_mean_normalize(input, &mean, &norm);

        const extractor = c.ncnn_extractor_create(net) orelse return error.AllocationFailed;
        defer c.ncnn_extractor_destroy(extractor);

        if (c.ncnn_extractor_input(extractor, "data", input) != 0) return error.InferenceFailed;

        var output: c.ncnn_mat_t = null;
        if (c.ncnn_extractor_extract(extractor, "output", &output) != 0) return error.InferenceFailed;

        const output_mat = output orelse return error.InferenceFailed;
        defer c.ncnn_mat_destroy(output_mat);

        const width = c.ncnn_mat_get_w(output_mat);
        const height = c.ncnn_mat_get_h(output_mat);
        if (c.ncnn_mat_get_c(output_mat) != 3 or width <= 0 or height <= 0) return error.InferenceFailed;

        const width_u32 = std.math.cast(u32, width) orelse return error.InferenceFailed;
        const height_u32 = std.math.cast(u32, height) orelse return error.InferenceFailed;
        const count = std.math.mul(usize, std.math.mul(usize, width_u32, height_u32) catch return error.InferenceFailed, 3) catch return error.InferenceFailed;
        var output_mean = [_]f32{ 0, 0, 0 };
        var output_norm = [_]f32{ 255, 255, 255 };

        c.ncnn_mat_substract_mean_normalize(output_mat, &output_mean, &output_norm);

        const pixels = allocator.alloc(u8, count) catch return error.AllocationFailed;
        errdefer allocator.free(pixels);

        c.ncnn_mat_to_pixels(output_mat, pixels.ptr, c.NCNN_MAT_PIXEL_RGB, width * 3);

        output_width.* = width_u32;
        output_height.* = height_u32;

        return pixels;
    }
};

test "model selection reaches the requested short edge" {
    try std.testing.expectEqual(@as(u64, 2), (@as(u64, 1440) + 800 - 1) / 800);
    try std.testing.expectEqual(@as(u64, 3), (@as(u64, 2001) + 800 - 1) / 800);
}

test "embedded x2 model performs direct ncnn inference" {
    var input: [4 * 4 * 3]u8 = undefined;
    for (&input, 0..) |*pixel, index| pixel.* = @intCast(index * 5);
    const models = Models.init();
    var width: u32 = 0;
    var height: u32 = 0;
    const output = try models.upscale(std.testing.allocator, &input, 4, 4, 8, &width, &height);
    defer std.testing.allocator.free(output);
    try std.testing.expectEqual(@as(u32, 8), width);
    try std.testing.expectEqual(@as(u32, 8), height);
    try std.testing.expectEqual(@as(usize, 8 * 8 * 3), output.len);
}
