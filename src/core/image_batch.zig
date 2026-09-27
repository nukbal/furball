const std = @import("std");
const builtin = @import("builtin");

const image = @import("image.zig");
const ncnn = @import("ncnn");
const protocol = @import("protocol.zig");

const Allocator = std.mem.Allocator;
const max_parallel_images: usize = 8;

pub const Source = union(enum) {
    file: []const u8,
    encoded: []const u8,
    rgb: struct {
        width: u32,
        height: u32,
        pixels: []const u8,
    },
};

pub const Result = struct {
    bytes: []u8,
    width: u32,
    height: u32,
};

pub fn process(
    allocator: Allocator,
    io: std.Io,
    sources: []const Source,
    config: protocol.Config,
    progress: ?protocol.Progress,
) ![]Result {
    if (sources.len == 0) return allocator.alloc(Result, 0);

    const tasks = try allocator.alloc(Task, sources.len);
    defer allocator.free(tasks);
    errdefer freeTaskOutputs(allocator, tasks);

    for (tasks, sources) |*task, source| {
        task.* = .{
            .allocator = allocator,
            .io = io,
            .source = source,
            .config = config,
        };
    }

    const use_vulkan = builtin.os.tag == .macos and config.ai and ncnn.furball_ncnn_vulkan_available() != 0;
    const worker_count = if (use_vulkan)
        max_parallel_images
    else
        @max(@as(usize, 1), @min(std.Thread.getCpuCount() catch 1, max_parallel_images));
    var first: usize = 0;
    while (first < tasks.len) {
        try io.checkCancel();
        const last = @min(tasks.len, first + worker_count);
        var group: std.Io.Group = .init;
        for (tasks[first..last]) |*task| {
            group.concurrent(io, Task.run, .{task}) catch |err| {
                group.cancel(io);
                return err;
            };
        }
        group.await(io) catch |err| {
            group.cancel(io);
            return err;
        };

        for (tasks[first..last]) |task| {
            if (task.failure) |err| return err;
            if (progress) |reporter| reporter.advance();
        }
        first = last;
    }

    const results = try allocator.alloc(Result, tasks.len);
    for (tasks, results) |*task, *result| {
        result.* = .{
            .bytes = task.output.?,
            .width = task.width,
            .height = task.height,
        };
        task.output = null;
    }
    return results;
}

pub fn freeResults(allocator: Allocator, results: []Result) void {
    for (results) |result| allocator.free(result.bytes);
    allocator.free(results);
}

const Task = struct {
    allocator: Allocator,
    io: std.Io,
    source: Source,
    config: protocol.Config,
    output: ?[]u8 = null,
    width: u32 = 0,
    height: u32 = 0,
    failure: ?anyerror = null,

    fn run(task: *Task) std.Io.Cancelable!void {
        const output = switch (task.source) {
            .file => |source| image.encodeBytes(task.allocator, task.io, source, task.config, 0),
            .encoded => |source| image.encodeBytesFromMemory(task.allocator, task.io, source, task.config),
            .rgb => |source| image.encodeRgb(task.allocator, task.io, source.width, source.height, source.pixels, task.config),
        } catch |err| {
            task.failure = err;
            if (err == error.Canceled) return error.Canceled;
            return;
        };

        const dimensions = image.inspectMemory(output) catch |err| {
            task.allocator.free(output);
            task.failure = err;
            if (err == error.Canceled) return error.Canceled;
            return;
        };
        task.output = output;
        task.width = dimensions.width;
        task.height = dimensions.height;
    }
};

fn freeTaskOutputs(allocator: Allocator, tasks: []Task) void {
    for (tasks) |task| {
        if (task.output) |output| allocator.free(output);
    }
}
