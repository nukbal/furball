const std = @import("std");
const native_sdk = @import("native_sdk");

const memory = @import("memory.zig");
const operations = @import("operations.zig");
const protocol = @import("protocol.zig");
const realesrgan = @import("realesrgan.zig");

const TestMsg = union(enum) {
    channel: native_sdk.EffectChannelEvent,
};
const TestEffects = native_sdk.Effects(TestMsg);

pub const max_workers: usize = 8;
pub const max_jobs: usize = 128;
pub const max_batch_sources: usize = 2048;
pub const notification_bytes: usize = @sizeOf(u64);

pub const Kind = enum { inspect, process };

pub const Completion = struct {
    id: u64,
    generation: u64,
    root_index: u16,
    kind: Kind,
    outcome: Outcome,

    pub const Outcome = union(enum) {
        inspect: protocol.InspectResponse,
        process: operations.OutputList,
        failed: anyerror,
    };

    pub fn deinit(self: *Completion, allocator: std.mem.Allocator) void {
        switch (self.outcome) {
            .inspect => |*response| operations.freeResponse(allocator, response),
            .process => |*result| result.deinit(),
            .failed => {},
        }
        self.* = undefined;
    }
};

const Job = struct {
    pool: *JobPool,
    id: u64,
    generation: u64,
    root_index: u16,
    kind: Kind,
    source: []u8,
    sources: ?[]protocol.Source = null,
    config: protocol.Config,
    in_use: bool = false,
};

const Batch = struct {
    generation: u64 = 0,
    submitted: usize = 0,
    completed: usize = 0,
    progress_completed: usize = 0,
    active: bool = false,
    wake_armed: bool = false,
    handle: native_sdk.ChannelHandle = .{},
};

pub const JobPool = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    group: std.Io.Group = .init,
    semaphore: std.Io.Semaphore = .{},
    mutex: std.Io.Mutex = .init,
    jobs: [max_jobs]Job = undefined,
    completions: [max_jobs]Completion = undefined,
    batches: [2]Batch = .{ .{}, .{} },
    next_id: u64 = 1,
    parallelism: usize = 1,
    completion_count: usize = 0,
    stopped: bool = false,
    initialized: bool = false,

    pub fn init(self: *JobPool, allocator: std.mem.Allocator, io: std.Io) void {
        self.* = .{
            .allocator = allocator,
            .io = io,
            .parallelism = @max(@as(usize, 1), @min(std.Thread.getCpuCount() catch 1, max_workers)),
        };
        for (&self.jobs) |*job| {
            job.* = undefined;
            job.in_use = false;
        }
        self.semaphore.permits = self.parallelism;
        self.initialized = true;
    }

    pub fn deinit(self: *JobPool) void {
        self.shutdown();
    }

    pub fn shutdown(self: *JobPool) void {
        if (!self.initialized or self.stopped) return;
        self.stopped = true;
        self.mutex.lockUncancelable(self.io);
        for (&self.batches) |*batch| {
            batch.active = false;
            batch.wake_armed = false;
        }
        self.mutex.unlock(self.io);
        self.group.cancel(self.io);
        self.mutex.lockUncancelable(self.io);
        self.freeCompletionsLocked();
        self.mutex.unlock(self.io);
        self.initialized = false;
    }

    pub fn submitInspection(self: *JobPool, fx: anytype, paths: []const []const u8, on_event: anytype) !void {
        try self.submit(.inspect, fx, paths, &.{}, on_event, .{}, false);
    }

    pub fn submitProcessingBatch(self: *JobPool, fx: anytype, sources: []const protocol.Source, config: protocol.Config, on_event: anytype) !void {
        try self.submit(.process, fx, &.{}, sources, on_event, config, true);
    }

    pub fn cancelInspection(self: *JobPool, fx: anytype) void {
        self.cancel(.inspect, fx);
    }

    pub fn cancelProcessing(self: *JobPool, fx: anytype) void {
        self.cancel(.process, fx);
    }

    pub fn cancelAll(self: *JobPool, fx: anytype) void {
        self.cancel(.inspect, fx);
        self.cancel(.process, fx);
    }

    pub fn take(self: *JobPool, kind: Kind, notification_id: ?u64, result: *Completion) bool {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        for (self.completions[0..self.completion_count], 0..) |completion, index| {
            if (completion.kind != kind) continue;
            if (notification_id) |id| if (completion.id != id) continue;
            result.* = completion;
            self.completions[index] = self.completions[self.completion_count - 1];
            self.completion_count -= 1;
            return true;
        }
        return false;
    }

    pub fn rearm(self: *JobPool, kind: Kind) void {
        var handle: native_sdk.ChannelHandle = .{};
        var id: ?u64 = null;
        self.mutex.lockUncancelable(self.io);
        const batch = &self.batches[indexOf(kind)];
        if (batch.handle.live()) {
            for (self.completions[0..self.completion_count]) |completion| {
                if (completion.kind == kind) {
                    id = completion.id;
                    handle = batch.handle;
                    batch.wake_armed = true;
                    break;
                }
            }
        }
        if (id == null) batch.wake_armed = false;
        self.mutex.unlock(self.io);
        if (id) |value| postNotification(handle, value);
    }

    pub fn hasActiveBatch(self: *JobPool, kind: Kind) bool {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        return self.batches[indexOf(kind)].active;
    }

    pub fn progress(self: *JobPool, kind: Kind) usize {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        return self.batches[indexOf(kind)].progress_completed;
    }

    fn submit(
        self: *JobPool,
        kind: Kind,
        fx: anytype,
        paths: []const []const u8,
        sources: []const protocol.Source,
        on_event: anytype,
        config: protocol.Config,
        grouped: bool,
    ) !void {
        const count = if (grouped) sources.len else paths.len;
        if (self.stopped or count == 0 or (grouped and count > max_batch_sources) or (!grouped and count > max_jobs / 2)) return error.InvalidBatch;
        const batch_index = indexOf(kind);
        self.mutex.lockUncancelable(self.io);
        const batch = &self.batches[batch_index];
        if (batch.active) {
            self.mutex.unlock(self.io);
            return error.BatchActive;
        }
        batch.generation +%= 1;
        batch.submitted = if (grouped) 1 else count;
        batch.completed = 0;
        batch.progress_completed = 0;
        batch.active = false;
        batch.wake_armed = false;
        const generation = batch.generation;
        self.mutex.unlock(self.io);

        if (!batch.handle.live()) {
            batch.handle = fx.openChannel(.{
                .key = keyFor(kind),
                .max_pending = 32,
                .on_event = on_event,
            });
            if (!batch.handle.live()) return error.ChannelUnavailable;
        }

        var reserved: [max_jobs / 2]*Job = undefined;
        var reserved_count: usize = 0;
        var scheduled_count: usize = 0;
        var batch_started = false;
        errdefer {
            for (reserved[scheduled_count..reserved_count]) |job| self.releaseUnsubmitted(job);
            if (batch_started) self.cancel(kind, fx);
        }
        if (grouped) {
            const job = try self.reserveBatchJob(kind, generation, sources, config);
            reserved[reserved_count] = job;
            reserved_count += 1;
        } else {
            for (paths, 0..) |path, root_index| {
                if (path.len == 0 or path.len > 1024) return error.InvalidSource;
                const job = try self.reserveJob(kind, generation, @intCast(root_index), path, config);
                reserved[reserved_count] = job;
                reserved_count += 1;
            }
        }

        self.mutex.lockUncancelable(self.io);
        if (self.stopped) {
            self.mutex.unlock(self.io);
            return error.ShuttingDown;
        }
        batch.active = true;
        batch_started = true;
        self.mutex.unlock(self.io);

        for (reserved[0..reserved_count]) |job| {
            try self.group.concurrent(self.io, runJob, .{job});
            scheduled_count += 1;
        }
    }

    fn reserveJob(self: *JobPool, kind: Kind, generation: u64, root_index: u16, source: []const u8, config: protocol.Config) !*Job {
        const owned_source = try self.allocator.dupe(u8, source);
        errdefer self.allocator.free(owned_source);
        const owned_config = try self.duplicateConfig(config);
        errdefer self.freeConfig(owned_config);

        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        for (&self.jobs) |*job| {
            if (job.in_use) continue;
            job.* = .{
                .pool = self,
                .id = self.next_id,
                .generation = generation,
                .root_index = root_index,
                .kind = kind,
                .source = owned_source,
                .sources = null,
                .config = owned_config,
                .in_use = true,
            };
            self.next_id +%= 1;
            return job;
        }
        return error.JobCapacityExceeded;
    }

    fn reserveBatchJob(self: *JobPool, kind: Kind, generation: u64, sources: []const protocol.Source, config: protocol.Config) !*Job {
        const owned_sources = try self.allocator.alloc(protocol.Source, sources.len);
        var copied: usize = 0;
        errdefer {
            for (owned_sources[0..copied]) |source| {
                self.allocator.free(source.path);
                self.allocator.free(source.name);
                self.allocator.free(source.root);
            }
            self.allocator.free(owned_sources);
        }
        for (sources) |source| {
            if (source.path.len == 0 or source.path.len > 1024 or source.name.len == 0 or source.name.len > 1024 or source.root.len == 0 or source.root.len > 1024) return error.InvalidSource;
            const path = try self.allocator.dupe(u8, source.path);
            errdefer self.allocator.free(path);
            const name = try self.allocator.dupe(u8, source.name);
            errdefer self.allocator.free(name);
            const root = try self.allocator.dupe(u8, source.root);
            errdefer self.allocator.free(root);
            owned_sources[copied] = .{
                .path = path,
                .name = name,
                .root = root,
                .kind = source.kind,
                .page_index = source.page_index,
            };
            copied += 1;
        }

        const owned_config = try self.duplicateConfig(config);
        errdefer self.freeConfig(owned_config);

        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        for (&self.jobs) |*job| {
            if (job.in_use) continue;
            job.* = .{
                .pool = self,
                .id = self.next_id,
                .generation = generation,
                .root_index = 0,
                .kind = kind,
                .source = &.{},
                .sources = owned_sources,
                .config = owned_config,
                .in_use = true,
            };
            self.next_id +%= 1;
            return job;
        }
        return error.JobCapacityExceeded;
    }

    fn duplicateConfig(self: *JobPool, config: protocol.Config) !protocol.Config {
        var owned = config;
        owned.path = &.{};
        owned.suffix = &.{};
        if (config.path.len != 0) owned.path = try self.allocator.dupe(u8, config.path);
        errdefer if (owned.path.len != 0) self.allocator.free(owned.path);
        if (config.suffix.len != 0) owned.suffix = try self.allocator.dupe(u8, config.suffix);
        return owned;
    }

    fn freeConfig(self: *JobPool, config: protocol.Config) void {
        if (config.path.len != 0) self.allocator.free(config.path);
        if (config.suffix.len != 0) self.allocator.free(config.suffix);
    }

    fn freeSources(self: *JobPool, sources: ?[]protocol.Source) void {
        if (sources) |items| {
            for (items) |source| {
                self.allocator.free(source.path);
                self.allocator.free(source.name);
                self.allocator.free(source.root);
            }
            self.allocator.free(items);
        }
    }

    fn releaseUnsubmitted(self: *JobPool, job: *Job) void {
        self.mutex.lockUncancelable(self.io);
        const source = job.source;
        const sources = job.sources;
        const path = job.config.path;
        const suffix = job.config.suffix;
        job.in_use = false;
        self.mutex.unlock(self.io);
        if (source.len != 0) self.allocator.free(source);
        self.freeSources(sources);
        if (path.len != 0) self.allocator.free(path);
        if (suffix.len != 0) self.allocator.free(suffix);
    }

    fn cancel(self: *JobPool, kind: Kind, fx: anytype) void {
        self.mutex.lockUncancelable(self.io);
        const batch = &self.batches[indexOf(kind)];
        batch.active = false;
        batch.submitted = 0;
        batch.completed = 0;
        batch.progress_completed = 0;
        batch.wake_armed = false;
        batch.handle = .{};
        self.removeCompletionsLocked(kind);
        self.mutex.unlock(self.io);
        fx.closeChannel(keyFor(kind));
    }

    fn complete(self: *JobPool, job: *Job, outcome: Completion.Outcome) void {
        var completion = Completion{
            .id = job.id,
            .generation = job.generation,
            .root_index = job.root_index,
            .kind = job.kind,
            .outcome = outcome,
        };
        var handle: native_sdk.ChannelHandle = .{};
        var notify = false;
        self.mutex.lockUncancelable(self.io);
        const batch = &self.batches[indexOf(job.kind)];
        if (batch.active and batch.generation == job.generation and self.completion_count < self.completions.len) {
            self.completions[self.completion_count] = completion;
            self.completion_count += 1;
            batch.completed += 1;
            if (batch.completed == batch.submitted) batch.active = false;
            if (!batch.wake_armed) {
                batch.wake_armed = true;
                handle = batch.handle;
                notify = true;
            }
        } else {
            completion.deinit(self.allocator);
        }
        self.mutex.unlock(self.io);
        if (notify) postNotification(handle, job.id);
    }

    fn advance(self: *JobPool, job: *Job) void {
        var handle: native_sdk.ChannelHandle = .{};
        var notify = false;
        self.mutex.lockUncancelable(self.io);
        const batch = &self.batches[indexOf(job.kind)];
        if (batch.active and batch.generation == job.generation) {
            batch.progress_completed +|= 1;
            if (!batch.wake_armed and batch.handle.live()) {
                batch.wake_armed = true;
                handle = batch.handle;
                notify = true;
            }
        }
        self.mutex.unlock(self.io);
        if (notify) postNotification(handle, job.id);
    }

    fn finishJob(self: *JobPool, job: *Job) void {
        self.mutex.lockUncancelable(self.io);
        const source = job.source;
        const sources = job.sources;
        const path = job.config.path;
        const suffix = job.config.suffix;
        job.in_use = false;
        self.mutex.unlock(self.io);
        if (source.len != 0) self.allocator.free(source);
        self.freeSources(sources);
        if (path.len != 0) self.allocator.free(path);
        if (suffix.len != 0) self.allocator.free(suffix);
    }

    fn removeCompletionsLocked(self: *JobPool, kind: Kind) void {
        var index: usize = 0;
        while (index < self.completion_count) {
            if (self.completions[index].kind != kind) {
                index += 1;
                continue;
            }
            var completion = self.completions[index];
            self.completions[index] = self.completions[self.completion_count - 1];
            self.completion_count -= 1;
            completion.deinit(self.allocator);
        }
    }

    fn freeCompletionsLocked(self: *JobPool) void {
        for (self.completions[0..self.completion_count]) |*completion| completion.deinit(self.allocator);
        self.completion_count = 0;
    }
};

fn runJob(job: *Job) std.Io.Cancelable!void {
    const pool = job.pool;
    pool.semaphore.wait(pool.io) catch {
        pool.finishJob(job);
        return error.Canceled;
    };
    defer pool.semaphore.post(pool.io);
    defer if (job.kind == .process) memory.releaseIdle();

    switch (job.kind) {
        .inspect => {
            const response = operations.inspect(pool.allocator, pool.io, job.source) catch |err| {
                pool.complete(job, .{ .failed = err });
                pool.finishJob(job);
                return;
            };
            pool.complete(job, .{ .inspect = response });
        },
        .process => {
            const sources = job.sources orelse unreachable;
            const result = operations.processSources(pool.allocator, pool.io, job.config, sources, .{
                .context = job,
                .advance_fn = reportProgress,
            }) catch |err| {
                pool.complete(job, .{ .failed = err });
                pool.finishJob(job);
                return;
            };
            pool.complete(job, .{ .process = result });
        },
    }
    pool.finishJob(job);
}

fn reportProgress(context: *anyopaque) void {
    const job: *Job = @ptrCast(@alignCast(context));
    job.pool.advance(job);
}

fn postNotification(handle: native_sdk.ChannelHandle, id: u64) void {
    var bytes: [notification_bytes]u8 = undefined;
    std.mem.writeInt(u64, &bytes, id, .little);
    _ = handle.post(&bytes);
}

fn indexOf(kind: Kind) usize {
    return @intFromEnum(kind);
}

fn keyFor(kind: Kind) u64 {
    return switch (kind) {
        .inspect => 11,
        .process => 12,
    };
}

test "job pool initializes bounded slots and joins an empty group" {
    var pool: JobPool = undefined;
    pool.init(std.testing.allocator, std.testing.io);
    defer pool.deinit();

    try std.testing.expect(pool.parallelism >= 1);
    try std.testing.expect(pool.parallelism <= max_workers);
    for (pool.jobs) |job| try std.testing.expect(!job.in_use);
}

test "job completions remain addressable after out of order arrival" {
    var pool: JobPool = undefined;
    pool.init(std.testing.allocator, std.testing.io);
    defer pool.deinit();

    pool.batches[0] = .{ .generation = 1, .submitted = 2, .active = true, .wake_armed = true };
    var first = Job{
        .pool = &pool,
        .id = 1,
        .generation = 1,
        .root_index = 0,
        .kind = .inspect,
        .source = &.{},
        .config = .{},
    };
    var second = first;
    second.id = 2;
    second.root_index = 1;
    pool.complete(&second, .{ .failed = error.InvalidSource });
    pool.complete(&first, .{ .failed = error.SourceNotFound });

    var completion: Completion = undefined;
    try std.testing.expect(pool.take(.inspect, 2, &completion));
    try std.testing.expectEqual(@as(u64, 2), completion.id);
    completion.deinit(std.testing.allocator);
    try std.testing.expect(pool.take(.inspect, 1, &completion));
    try std.testing.expectEqual(@as(u64, 1), completion.id);
    completion.deinit(std.testing.allocator);
}

test "job notifications are bounded ids" {
    try std.testing.expectEqual(notification_bytes, @sizeOf(u64));
    try std.testing.expect(max_workers >= 1);
}

test "job pool completes an image conversion before shutdown" {
    const allocator = std.testing.allocator;
    const png_base64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=";
    const png_size = std.base64.standard.Decoder.calcSizeForSlice(png_base64) catch unreachable;
    const png = try allocator.alloc(u8, png_size);
    defer allocator.free(png);
    try std.base64.standard.Decoder.decode(png, png_base64);
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const source = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/source.png", .{tmp.sub_path});
    defer allocator.free(source);
    const output_directory = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}", .{tmp.sub_path});
    defer allocator.free(output_directory);
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "source.png", .data = png });

    var fx = TestEffects.init(allocator);
    defer fx.deinit();
    fx.executor = .fake;
    var pool: JobPool = undefined;
    pool.init(allocator, std.testing.io);
    defer pool.deinit();

    const sources = [_]protocol.Source{.{
        .path = source,
        .name = "source.png",
        .root = source,
        .kind = .image,
    }};
    try pool.submitProcessingBatch(&fx, &sources, .{
        .mode = .path,
        .path = output_directory,
        .width = 1,
        .quality = 80,
    }, TestEffects.channelMsg(.channel));

    var delivered = false;
    var attempts: usize = 0;
    while (!delivered and attempts < 500) : (attempts += 1) {
        if (fx.takeMsg()) |message| {
            switch (message) {
                .channel => |event| {
                    try std.testing.expectEqual(native_sdk.EffectChannelEventKind.data, event.kind);
                    try std.testing.expectEqual(notification_bytes, event.bytes.len);
                    var bytes: [notification_bytes]u8 = undefined;
                    @memcpy(&bytes, event.bytes);
                    const id = std.mem.readInt(u64, &bytes, .little);
                    var completion: Completion = undefined;
                    if (!pool.take(.process, id, &completion)) {
                        pool.rearm(.process);
                        continue;
                    }
                    switch (completion.outcome) {
                        .process => |*output| {
                            try std.testing.expectEqual(@as(usize, 1), output.values.items.len);
                        },
                        .failed => return error.TestUnexpectedResult,
                        else => return error.TestUnexpectedResult,
                    }
                    completion.deinit(allocator);
                    pool.rearm(.process);
                    delivered = true;
                },
            }
        } else {
            try std.Io.sleep(std.testing.io, std.Io.Duration.fromMilliseconds(1), .awake);
        }
    }
    try std.testing.expect(delivered);
    try std.testing.expectEqual(@as(usize, 1), pool.progress(.process));
    try std.testing.expect(!pool.hasActiveBatch(.process));
    pool.shutdown();
}

test "job pool drains a batch beyond semaphore parallelism" {
    const allocator = std.testing.allocator;
    const png_base64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=";
    const png_size = std.base64.standard.Decoder.calcSizeForSlice(png_base64) catch unreachable;
    const png = try allocator.alloc(u8, png_size);
    defer allocator.free(png);
    try std.base64.standard.Decoder.decode(png, png_base64);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var fx = TestEffects.init(allocator);
    defer fx.deinit();
    fx.executor = .fake;
    var pool: JobPool = undefined;
    pool.init(allocator, std.testing.io);
    defer pool.deinit();

    const count = pool.parallelism + 1;
    var sources: [max_workers + 1]protocol.Source = undefined;
    var owned_paths: [max_workers + 1][]u8 = undefined;
    for (0..count) |index| {
        const file_name = try std.fmt.allocPrint(allocator, "source{d}.png", .{index});
        defer allocator.free(file_name);
        try tmp.dir.writeFile(std.testing.io, .{ .sub_path = file_name, .data = png });
        owned_paths[index] = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/{s}", .{ tmp.sub_path, file_name });
        sources[index] = .{
            .path = owned_paths[index],
            .name = std.fs.path.basename(owned_paths[index]),
            .root = owned_paths[index],
            .kind = .image,
        };
    }
    defer for (owned_paths[0..count]) |path| allocator.free(path);

    const output_directory = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}", .{tmp.sub_path});
    defer allocator.free(output_directory);
    try pool.submitProcessingBatch(&fx, sources[0..count], .{
        .mode = .path,
        .path = output_directory,
        .width = 1,
        .quality = 80,
    }, TestEffects.channelMsg(.channel));
    try std.testing.expectEqual(@as(usize, 1), pool.batches[indexOf(.process)].submitted);
    try std.testing.expect(pool.batches[indexOf(.process)].active);

    var delivered: usize = 0;
    var attempts: usize = 0;
    while (delivered < 1 and attempts < 5000) : (attempts += 1) {
        if (fx.takeMsg()) |message| {
            switch (message) {
                .channel => |event| {
                    try std.testing.expectEqual(native_sdk.EffectChannelEventKind.data, event.kind);
                    try std.testing.expectEqual(notification_bytes, event.bytes.len);
                    var bytes: [notification_bytes]u8 = undefined;
                    @memcpy(&bytes, event.bytes);
                    const id = std.mem.readInt(u64, &bytes, .little);
                    var completion: Completion = undefined;
                    if (!pool.take(.process, id, &completion)) {
                        pool.rearm(.process);
                        continue;
                    }
                    switch (completion.outcome) {
                        .process => |*output| try std.testing.expectEqual(count, output.values.items.len),
                        else => return error.TestUnexpectedResult,
                    }
                    completion.deinit(allocator);
                    delivered += 1;
                    pool.rearm(.process);
                },
            }
        } else {
            try std.Io.sleep(std.testing.io, std.Io.Duration.fromMilliseconds(1), .awake);
        }
    }

    try std.testing.expectEqual(@as(usize, 1), delivered);
    try std.testing.expectEqual(count, pool.progress(.process));
    try std.testing.expectEqual(@as(usize, 1), pool.batches[indexOf(.process)].completed);
    try std.testing.expect(!pool.batches[indexOf(.process)].active);
    try std.testing.expect(!pool.batches[indexOf(.process)].wake_armed);
    try std.testing.expectEqual(@as(usize, 0), pool.completion_count);
    for (pool.jobs) |job| try std.testing.expect(!job.in_use);
}
