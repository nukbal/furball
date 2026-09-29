const std = @import("std");
const builtin = @import("builtin");
const coreml = @import("coreml");
const protocol = @import("protocol.zig");

const max_pixels = @import("image.zig").max_pixels;
const max_dimension = @import("image.zig").max_dimension;

pub const min_model_input_dimension: u32 = 32;
pub const min_ai_output_dimension: u32 = min_model_input_dimension * 2;
const pre_pad: u32 = 10;
const tile_overlap: u32 = 32;
pub const max_concurrent_inferences: usize = @intCast(coreml.FURBALL_COREML_MODEL_INSTANCES);
const max_parallel_tiles = max_concurrent_inferences;

const all_model_slots_mask: u8 = blk: {
    var mask: u8 = 0;
    for (0..max_concurrent_inferences) |slot| mask |= @as(u8, 1) << @intCast(slot);
    break :blk mask;
};

var model_slots_mutex: std.Io.Mutex = .init;
var model_slots_condition: std.Io.Condition = .init;
var model_slots_in_use: u8 = 0;

const Model = struct {
    id: u8,
    input_size: u32,
    scale: u32,
};

const TileTask = struct {
    io: std.Io,
    input_rgb: []const u8,
    input_width: u32,
    input_height: u32,
    model: Model,
    model_input: []u8,
    model_output: []u8,
    tile_x: u32 = 0,
    tile_y: u32 = 0,
    core_width: u32 = 0,
    core_height: u32 = 0,
    failure: ?anyerror = null,

    fn run(task: *TileTask) std.Io.Cancelable!void {
        task.failure = null;
        task.execute() catch |err| {
            task.failure = err;
            if (err == error.Canceled) return error.Canceled;
        };
    }

    fn execute(task: *TileTask) !void {
        try task.io.checkCancel();
        try fillModelTile(
            task.model_input,
            task.input_rgb,
            task.input_width,
            task.input_height,
            task.model.input_size,
            task.tile_x,
            task.tile_y,
            task.core_width,
            task.core_height,
        );

        const model_slot = try acquireModelSlot(task.io);
        defer releaseModelSlot(task.io, model_slot);
        const status = coreml.furball_coreml_run(task.model.id, model_slot, task.model_input.ptr, task.model_output.ptr);
        switch (status) {
            coreml.FURBALL_COREML_SUCCESS => {},
            coreml.FURBALL_COREML_UNSUPPORTED_PLATFORM => return error.UnsupportedPlatform,
            coreml.FURBALL_COREML_MODEL_FAILED => return error.ModelFailed,
            else => return error.InferenceFailed,
        }
        try task.io.checkCancel();
    }
};

pub fn upscale(
    allocator: std.mem.Allocator,
    io: std.Io,
    input_rgb: []const u8,
    input_width: u32,
    input_height: u32,
    target_short_edge: u32,
    upscaler: protocol.Upscaler,
    tile_parallelism: usize,
    output_width: *u32,
    output_height: *u32,
) ![]u8 {
    if (input_width < min_model_input_dimension or input_height < min_model_input_dimension or target_short_edge == 0 or tile_parallelism == 0) return error.InvalidResize;
    if (@min(input_width, input_height) >= target_short_edge) return error.InvalidResize;
    if (input_width > max_dimension or input_height > max_dimension) return error.InvalidResize;
    if (builtin.os.tag != .macos) return error.UnsupportedPlatform;

    const input_pixels = std.math.mul(u64, input_width, input_height) catch return error.InvalidResize;
    if (input_pixels > max_pixels) return error.InvalidResize;
    const input_byte_count = std.math.cast(usize, std.math.mul(u64, input_pixels, 3) catch return error.InvalidResize) orelse return error.InvalidResize;
    if (input_rgb.len < input_byte_count) return error.InvalidResize;

    const model = selectModel(upscaler, input_width, input_height, target_short_edge);
    if (model.input_size <= pre_pad + tile_overlap) return error.InvalidResize;
    const model_input_size = model.input_size;
    const tile_size = model_input_size - pre_pad;
    const tile_stride = tile_size - tile_overlap;
    const scale = model.scale;
    const output_width_value = std.math.cast(u32, std.math.mul(u64, input_width, scale) catch return error.InvalidResize) orelse return error.InvalidResize;
    const output_height_value = std.math.cast(u32, std.math.mul(u64, input_height, scale) catch return error.InvalidResize) orelse return error.InvalidResize;
    if (output_width_value > max_dimension or output_height_value > max_dimension) return error.InvalidResize;
    const output_pixels = std.math.mul(u64, output_width_value, output_height_value) catch return error.InvalidResize;
    if (output_pixels > max_pixels) return error.InvalidResize;
    const output_byte_count = std.math.cast(usize, std.math.mul(u64, output_pixels, 3) catch return error.InvalidResize) orelse return error.InvalidResize;

    const model_input_dimension = std.math.cast(usize, model_input_size) orelse return error.InvalidResize;
    const model_input_bytes = std.math.mul(usize, std.math.mul(usize, model_input_dimension, model_input_dimension) catch return error.InvalidResize, 3) catch return error.InvalidResize;
    const model_output_dimension = std.math.cast(usize, std.math.mul(u32, model_input_size, scale) catch return error.InvalidResize) orelse return error.InvalidResize;
    const model_output_bytes = std.math.mul(usize, std.math.mul(usize, model_output_dimension, model_output_dimension) catch return error.InvalidResize, 3) catch return error.InvalidResize;

    const result = try allocator.alloc(u8, output_byte_count);
    errdefer allocator.free(result);
    const cpu_count = std.Thread.getCpuCount() catch 1;
    const worker_count = if (input_width <= tile_size and input_height <= tile_size)
        1
    else
        @min(max_parallel_tiles, @min(tile_parallelism, @max(@as(usize, 1), cpu_count)));
    const model_input_total = std.math.mul(usize, model_input_bytes, worker_count) catch return error.InvalidResize;
    const model_output_total = std.math.mul(usize, model_output_bytes, worker_count) catch return error.InvalidResize;
    const model_inputs = try allocator.alloc(u8, model_input_total);
    defer allocator.free(model_inputs);
    const model_outputs = try allocator.alloc(u8, model_output_total);
    defer allocator.free(model_outputs);
    const tile_tasks = try allocator.alloc(TileTask, worker_count);
    defer allocator.free(tile_tasks);

    for (tile_tasks, 0..) |*task, index| {
        const input_offset = std.math.mul(usize, index, model_input_bytes) catch return error.InvalidResize;
        const output_offset = std.math.mul(usize, index, model_output_bytes) catch return error.InvalidResize;
        task.* = .{
            .io = io,
            .input_rgb = input_rgb,
            .input_width = input_width,
            .input_height = input_height,
            .model = model,
            .model_input = model_inputs[input_offset .. input_offset + model_input_bytes],
            .model_output = model_outputs[output_offset .. output_offset + model_output_bytes],
        };
    }

    var next_x: u32 = 0;
    var next_y: u32 = 0;
    var finished = false;
    while (!finished) {
        try io.checkCancel();
        var active_count: usize = 0;
        while (active_count < worker_count and !finished) : (active_count += 1) {
            const task = &tile_tasks[active_count];
            task.tile_x = next_x;
            task.tile_y = next_y;
            task.core_width = @min(tile_size, input_width - next_x);
            task.core_height = @min(tile_size, input_height - next_y);

            if (input_width - next_x <= tile_size) {
                next_x = 0;
                if (input_height - next_y <= tile_size) {
                    finished = true;
                } else {
                    next_y += tile_stride;
                }
            } else {
                next_x += tile_stride;
            }
        }

        var group: std.Io.Group = .init;
        for (tile_tasks[0..active_count]) |*task| {
            group.concurrent(io, TileTask.run, .{task}) catch |err| {
                group.cancel(io);
                return err;
            };
        }
        group.await(io) catch |err| {
            group.cancel(io);
            return err;
        };

        for (tile_tasks[0..active_count]) |task| {
            if (task.failure) |err| return err;
        }
        for (tile_tasks[0..active_count]) |task| {
            try mergeModelTile(
                result,
                task.model_output,
                output_width_value,
                model_output_dimension,
                task.tile_x,
                task.tile_y,
                task.core_width,
                task.core_height,
                scale,
            );
        }
    }

    output_width.* = output_width_value;
    output_height.* = output_height_value;
    return result;
}

fn acquireModelSlot(io: std.Io) !u8 {
    try model_slots_mutex.lock(io);
    defer model_slots_mutex.unlock(io);

    while (model_slots_in_use == all_model_slots_mask) {
        try model_slots_condition.wait(io, &model_slots_mutex);
    }
    for (0..max_concurrent_inferences) |slot| {
        const bit = @as(u8, 1) << @as(u3, @intCast(slot));
        if (model_slots_in_use & bit == 0) {
            model_slots_in_use |= bit;
            return @intCast(slot);
        }
    }
    unreachable;
}

fn releaseModelSlot(io: std.Io, slot: u8) void {
    model_slots_mutex.lockUncancelable(io);
    model_slots_in_use &= ~(@as(u8, 1) << @as(u3, @intCast(slot)));
    model_slots_condition.signal(io);
    model_slots_mutex.unlock(io);
}

fn fillModelTile(
    destination: []u8,
    input_rgb: []const u8,
    input_width: u32,
    input_height: u32,
    model_input_size: u32,
    tile_x: u32,
    tile_y: u32,
    tile_width: u32,
    tile_height: u32,
) !void {
    if (tile_width < min_model_input_dimension or tile_height < min_model_input_dimension) return error.InvalidResize;
    const stride = std.math.cast(usize, std.math.mul(u32, model_input_size, 3) catch return error.InvalidResize) orelse return error.InvalidResize;
    for (0..model_input_size) |row| {
        const source_y = try reflectCoordinate(@intCast(row), tile_height);
        const image_y = std.math.add(u32, tile_y, source_y) catch return error.InvalidResize;
        if (image_y >= input_height) return error.InvalidResize;
        for (0..model_input_size) |column| {
            const source_x = try reflectCoordinate(@intCast(column), tile_width);
            const image_x = std.math.add(u32, tile_x, source_x) catch return error.InvalidResize;
            if (image_x >= input_width) return error.InvalidResize;
            const source_pixel = std.math.cast(usize, std.math.mul(u64, std.math.add(u64, std.math.mul(u64, image_y, input_width) catch return error.InvalidResize, image_x) catch return error.InvalidResize, 3) catch return error.InvalidResize) orelse return error.InvalidResize;
            const destination_pixel = std.math.add(usize, std.math.mul(usize, row, stride) catch return error.InvalidResize, std.math.mul(usize, column, 3) catch return error.InvalidResize) catch return error.InvalidResize;
            @memcpy(destination[destination_pixel .. destination_pixel + 3], input_rgb[source_pixel .. source_pixel + 3]);
        }
    }
}

fn selectModel(upscaler: protocol.Upscaler, input_width: u32, input_height: u32, target_short_edge: u32) Model {
    return switch (upscaler) {
        .real_esrgan => if (@as(u64, target_short_edge) <= @as(u64, @min(input_width, input_height)) * 2)
            .{ .id = coreml.FURBALL_COREML_REAL_ESRGAN_X2, .input_size = 522, .scale = 2 }
        else
            .{ .id = coreml.FURBALL_COREML_REAL_ESRGAN_X4, .input_size = 522, .scale = 4 },
        .pipersr => .{ .id = coreml.FURBALL_COREML_PIPERSR_X2, .input_size = 256, .scale = 2 },
    };
}

fn reflectCoordinate(coordinate: u32, extent: u32) !u32 {
    if (extent < 2) return error.InvalidResize;
    const last: i64 = @intCast(extent - 1);
    var value: i64 = @intCast(coordinate);
    while (value < 0 or value > last) {
        value = if (value < 0) -value else 2 * last - value;
    }
    return @intCast(value);
}

fn mergeModelTile(
    destination: []u8,
    source: []const u8,
    destination_width: u32,
    source_dimension: usize,
    tile_x: u32,
    tile_y: u32,
    tile_width: u32,
    tile_height: u32,
    scale: u32,
) !void {
    const tile_width_output = std.math.mul(u32, tile_width, scale) catch return error.InvalidResize;
    const tile_height_output = std.math.mul(u32, tile_height, scale) catch return error.InvalidResize;
    const tile_x_output = std.math.mul(u32, tile_x, scale) catch return error.InvalidResize;
    const tile_y_output = std.math.mul(u32, tile_y, scale) catch return error.InvalidResize;
    const overlap_output = std.math.mul(u32, tile_overlap, scale) catch return error.InvalidResize;
    const left_blend_width = if (tile_x == 0) 0 else @min(overlap_output, tile_width_output);
    const top_blend_height = if (tile_y == 0) 0 else @min(overlap_output, tile_height_output);
    const destination_width_usize: usize = @intCast(destination_width);

    for (0..tile_height_output) |row| {
        const destination_y = std.math.add(usize, tile_y_output, row) catch return error.InvalidResize;
        const destination_row = std.math.mul(usize, destination_y, destination_width_usize) catch return error.InvalidResize;
        const source_row = std.math.mul(usize, row, source_dimension) catch return error.InvalidResize;
        const blend_top = row < top_blend_height;

        if (blend_top) {
            for (0..tile_width_output) |column| {
                const x_weight = if (column < left_blend_width) rampWeight(column, left_blend_width) else 1.0;
                const y_weight = rampWeight(row, top_blend_height);
                const weight = x_weight * y_weight;
                try blendPixel(destination, source, destination_row, source_row, tile_x_output, column, weight);
            }
        } else if (left_blend_width > 0) {
            for (0..left_blend_width) |column| {
                try blendPixel(destination, source, destination_row, source_row, tile_x_output, column, rampWeight(column, left_blend_width));
            }
            try copyTileRow(destination, source, destination_row, source_row, tile_x_output, left_blend_width, tile_width_output);
        } else {
            try copyTileRow(destination, source, destination_row, source_row, tile_x_output, 0, tile_width_output);
        }
    }
}

fn rampWeight(offset: usize, extent: usize) f32 {
    return @as(f32, @floatFromInt(offset + 1)) / @as(f32, @floatFromInt(extent + 1));
}

fn blendPixel(destination: []u8, source: []const u8, destination_row: usize, source_row: usize, tile_x: u32, column: usize, weight: f32) !void {
    const destination_pixel = std.math.add(usize, std.math.add(usize, destination_row, @intCast(tile_x)) catch return error.InvalidResize, column) catch return error.InvalidResize;
    const destination_offset = std.math.mul(usize, destination_pixel, 3) catch return error.InvalidResize;
    const source_pixel = std.math.add(usize, source_row, column) catch return error.InvalidResize;
    const source_offset = std.math.mul(usize, source_pixel, 3) catch return error.InvalidResize;
    for (0..3) |channel| {
        const old_value: f32 = @floatFromInt(destination[destination_offset + channel]);
        const new_value: f32 = @floatFromInt(source[source_offset + channel]);
        destination[destination_offset + channel] = @intFromFloat(old_value * (1.0 - weight) + new_value * weight + 0.5);
    }
}

fn copyTileRow(destination: []u8, source: []const u8, destination_row: usize, source_row: usize, tile_x: u32, start_column: usize, end_column: u32) !void {
    const first_pixel = std.math.add(usize, @intCast(tile_x), start_column) catch return error.InvalidResize;
    const destination_pixel = std.math.add(usize, destination_row, first_pixel) catch return error.InvalidResize;
    const source_pixel = std.math.add(usize, source_row, start_column) catch return error.InvalidResize;
    const byte_count = std.math.mul(usize, @as(usize, @intCast(end_column)) - start_column, 3) catch return error.InvalidResize;
    const destination_offset = std.math.mul(usize, destination_pixel, 3) catch return error.InvalidResize;
    const source_offset = std.math.mul(usize, source_pixel, 3) catch return error.InvalidResize;
    const destination_end = std.math.add(usize, destination_offset, byte_count) catch return error.InvalidResize;
    const source_end = std.math.add(usize, source_offset, byte_count) catch return error.InvalidResize;
    if (destination_end > destination.len or source_end > source.len) return error.InvalidResize;
    @memcpy(destination[destination_offset..destination_end], source[source_offset..source_end]);
}
