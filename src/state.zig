const std = @import("std");
const protocol = @import("core/protocol.zig");
const operations = @import("core/operations.zig");
const Allocator = std.mem.Allocator;

pub const EditOperation = enum { backspace, delete, left, right, home, end };
pub const max_paths = 64;
pub const max_path_bytes = 1024;

pub const Item = struct {
    path_bytes: [max_path_bytes]u8 = undefined,
    path_len: usize = 0,
    name_bytes: [256]u8 = undefined,
    name_len: usize = 0,
    metadata_bytes: [128]u8 = undefined,
    metadata_len: usize = 0,
    kind: protocol.Kind = .image,
    size: u64 = 0,
    count: u32 = 0,
    depth: u16 = 0,
    root_index: u16 = 0,
    selected: bool = false,

    pub fn path(self: *const Item) []const u8 {
        return self.path_bytes[0..self.path_len];
    }
    pub fn name(self: *const Item) []const u8 {
        return self.name_bytes[0..self.name_len];
    }
    pub fn metadata(self: *const Item) []const u8 {
        return self.metadata_bytes[0..self.metadata_len];
    }
};

pub const State = struct {
    items: [max_paths]Item = undefined,
    item_count: usize = 0,
    root_count: usize = 0,
    config: protocol.Config = .{},
    output_bytes: [max_path_bytes]u8 = undefined,
    output_len: usize = 0,
    suffix_bytes: [128]u8 = undefined,
    suffix_len: usize = 0,
    width_bytes: [8]u8 = undefined,
    width_len: usize = 4,
    status_bytes: [256]u8 = undefined,
    status_len: usize = 0,
    error_bytes: [256]u8 = undefined,
    error_len: usize = 0,
    output_last_bytes: [max_path_bytes]u8 = undefined,
    output_last_len: usize = 0,
    processing: bool = false,
    loading: bool = false,
    processed: usize = 0,
    width_caret: usize = 4,
    suffix_caret: usize = 0,
    config_open: bool = true,

    pub fn init() State {
        var self: State = .{};
        @memcpy(self.width_bytes[0..4], "1440");
        self.setStatus("파일을 추가해주세요");
        return self;
    }

    pub fn outputPath(self: *const State) []const u8 {
        return self.output_bytes[0..self.output_len];
    }
    pub fn suffix(self: *const State) []const u8 {
        return self.suffix_bytes[0..self.suffix_len];
    }
    pub fn width(self: *const State) []const u8 {
        return self.width_bytes[0..self.width_len];
    }
    pub fn status(self: *const State) []const u8 {
        return self.status_bytes[0..self.status_len];
    }
    pub fn errorText(self: *const State) []const u8 {
        return self.error_bytes[0..self.error_len];
    }
    pub fn outputRevealPath(self: *const State) []const u8 {
        return if (self.output_len != 0) self.outputPath() else self.output_last_bytes[0..self.output_last_len];
    }
    pub fn hasError(self: *const State) bool {
        return self.error_len != 0;
    }
    pub fn hasOutput(self: *const State) bool {
        return self.output_last_len != 0;
    }
    pub fn controlsDisabled(self: *const State) bool {
        return self.processing or self.loading;
    }
    pub fn canProcess(self: *const State) bool {
        return !self.controlsDisabled() and self.root_count > 0 and (self.config.mode == .overwrite or self.output_len > 0) and !self.hasError();
    }
    pub fn isPathMode(self: *const State) bool {
        return self.config.mode == .path;
    }
    pub fn isOverwriteMode(self: *const State) bool {
        return self.config.mode == .overwrite;
    }
    pub fn isDirNone(self: *const State) bool {
        return self.config.dir_mode == .none;
    }
    pub fn isDirPdf(self: *const State) bool {
        return self.config.dir_mode == .pdf;
    }
    pub fn isDirZip(self: *const State) bool {
        return self.config.dir_mode == .zip;
    }
    pub fn aiEnabled(self: *const State) bool {
        return self.config.ai;
    }
    pub fn qualityFraction(self: *const State) f32 {
        return @as(f32, @floatFromInt(self.config.quality)) / 100;
    }
    pub fn processLabel(self: *const State, _: Allocator) []const u8 {
        return if (self.processing) "변환 중..." else if (self.hasOutput()) "다시 변환" else "변환 시작";
    }
    pub fn fileSummary(self: *const State, alloc: Allocator) []const u8 {
        var count: u64 = 0;
        for (self.items[0..self.item_count]) |item| if (item.depth == 0) {
            count += @max(1, item.count);
        };
        return std.fmt.allocPrint(alloc, "{d}개 항목", .{count}) catch "항목 정보";
    }
    pub fn setStatus(self: *State, value: []const u8) void {
        copy(&self.status_bytes, &self.status_len, value);
    }
    pub fn setError(self: *State, value: []const u8) void {
        copy(&self.error_bytes, &self.error_len, value);
    }
    pub fn clearError(self: *State) void {
        self.error_len = 0;
    }
    pub fn loadConfig(self: *State, alloc: Allocator, io: std.Io, home: []const u8) void {
        if (home.len == 0) return;
        const path = std.fs.path.join(alloc, &.{ home, "Library/Application Support/furball/config.json" }) catch return;
        defer alloc.free(path);
        const bytes = std.Io.Dir.cwd().readFileAlloc(io, path, alloc, .limited(8192)) catch return;
        defer alloc.free(bytes);
        var parsed = protocol.parseConfig(alloc, bytes) catch return;
        defer parsed.deinit();
        self.config = parsed.value;
        self.config.path = "";
        self.config.suffix = "";
        copy(&self.output_bytes, &self.output_len, parsed.value.path);
        copy(&self.suffix_bytes, &self.suffix_len, parsed.value.suffix);
        const width_text = std.fmt.bufPrint(&self.width_bytes, "{d}", .{parsed.value.width}) catch "1440";
        self.width_len = width_text.len;
        self.width_caret = width_text.len;
        self.suffix_caret = self.suffix_len;
    }

    pub fn saveConfig(self: *State, alloc: Allocator, io: std.Io, home: []const u8) void {
        if (home.len == 0) return;

        var config = self.config;
        config.path = self.outputPath();
        config.suffix = self.suffix();
        protocol.validateConfig(config) catch return;

        const directory = std.fs.path.join(alloc, &.{ home, "Library/Application Support/furball" }) catch return;
        defer alloc.free(directory);

        std.Io.Dir.cwd().createDirPath(io, directory) catch return;
        const path = std.fs.path.join(alloc, &.{ directory, "config.json" }) catch return;
        defer alloc.free(path);

        const bytes = protocol.stringify(alloc, config) catch return;
        defer alloc.free(bytes);

        std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = bytes }) catch self.setError("설정을 저장할 수 없습니다");
    }

    pub fn setOutput(self: *State, path: []const u8) void {
        if (path.len > self.output_bytes.len) {
            self.setError("저장 경로가 너무 깁니다");
            return;
        }
        copy(&self.output_bytes, &self.output_len, path);
        self.clearError();
    }
    pub fn select(self: *State, index: usize) void {
        if (index >= self.item_count) return;
        const root = self.items[index].root_index;
        for (self.items[0..self.item_count]) |*item| item.selected = item.root_index == root;
    }
    pub fn remove(self: *State, index: usize) void {
        if (index >= self.item_count) return;
        const root = self.items[index].root_index;
        var end = @as(usize, root) + 1;
        while (end < self.item_count and self.items[end].depth != 0) : (end += 1) {}
        const removed = end - root;
        std.mem.copyForwards(Item, self.items[root .. self.item_count - removed], self.items[end..self.item_count]);
        self.item_count -= removed;
        self.root_count -= 1;
        for (self.items[0..self.item_count]) |*item| if (item.root_index > root) {
            item.root_index -= @intCast(removed);
        };
        if (self.item_count > 0) self.select(if (root < self.item_count) root else self.items[self.item_count - 1].root_index);
        self.clearError();
    }

    pub fn addPaths(self: *State, alloc: Allocator, io: std.Io, paths: []const []const u8, first_response: ?*?protocol.InspectResponse) bool {
        if (paths.len == 0) return true;
        if (paths.len > max_paths) {
            self.setError("추가할 수 있는 파일 수를 초과했습니다");
            return false;
        }
        for (paths) |path| if (path.len > max_path_bytes) {
            self.setError("추가할 수 있는 파일 수나 경로 길이를 초과했습니다");
            return false;
        };

        var responses = std.ArrayList(protocol.InspectResponse).empty;
        defer {
            for (responses.items) |*response| operations.freeResponse(alloc, response);
            responses.deinit(alloc);
        }

        for (paths) |path| {
            var response = operations.inspect(alloc, io, path) catch {
                self.setError("파일 정보를 읽을 수 없습니다");
                return false;
            };
            responses.append(alloc, response) catch {
                operations.freeResponse(alloc, &response);
                self.setError("메모리가 부족합니다");
                return false;
            };
        }

        var pdf_count: usize = 0;
        var direct_images = true;
        var incoming_items: usize = 0;
        for (responses.items) |response| {
            if (response.kind == .pdf) pdf_count += 1;
            if (response.kind != .image) direct_images = false;
            incoming_items +|= inspectedNodeCount(response);
        }
        if (pdf_count > 1) {
            self.setError("PDF는 한 번에 하나만 선택할 수 있습니다");
            return false;
        }

        const append = direct_images and self.item_count != 0 and !self.hasOutput();
        const preview_changed = !append;
        const current_items = if (append) self.item_count else 0;
        if (incoming_items > self.items.len - current_items) {
            self.setError("추가할 수 있는 파일 수나 경로 길이를 초과했습니다");
            return false;
        }

        if (!append) self.clearInputSet();
        for (responses.items) |*response| {
            const root = self.item_count;
            self.appendInspected(response, @intCast(root), 0);
            self.root_count += 1;
            self.select(root);
        }
        if (preview_changed and first_response != null) {
            first_response.?.* = responses.orderedRemove(0);
        }
        self.clearError();
        self.setStatus("파일을 준비했습니다");
        return preview_changed;
    }

    fn clearInputSet(self: *State) void {
        self.item_count = 0;
        self.root_count = 0;
        self.output_last_len = 0;
        self.processed = 0;
        self.clearError();
    }

    pub fn process(self: *State, alloc: Allocator, io: std.Io, progress: ?protocol.Progress) void {
        if (!self.canProcess()) return;
        self.processing = true;
        defer self.processing = false;
        self.processed = 0;
        self.output_last_len = 0;
        self.setStatus("변환 중입니다...");
        var config = self.config;
        config.path = self.outputPath();
        config.suffix = self.suffix();
        protocol.validateConfig(config) catch {
            self.setError("설정 값을 확인해주세요");
            return;
        };

        var responses = std.ArrayList(protocol.InspectResponse).empty;
        defer {
            for (responses.items) |*response| operations.freeResponse(alloc, response);
            responses.deinit(alloc);
        }
        var sources = std.ArrayList(protocol.Source).empty;
        defer sources.deinit(alloc);
        var page_names = std.ArrayList([]u8).empty;
        defer {
            for (page_names.items) |name| alloc.free(name);
            page_names.deinit(alloc);
        }
        for (self.items[0..self.item_count]) |*item| {
            if (item.depth != 0) continue;
            const response = operations.inspect(alloc, io, item.path()) catch {
                return self.setError("파일 정보를 읽을 수 없습니다");
            };
            responses.append(alloc, response) catch {
                var owned = response;
                operations.freeResponse(alloc, &owned);
                return self.setError("메모리가 부족합니다");
            };
        }
        for (responses.items) |*response| {
            if (response.kind == .pdf and responses.items.len != 1) {
                return self.setError("PDF는 다른 파일과 함께 처리할 수 없습니다");
            }
            appendSources(alloc, response, response, &sources, &page_names) catch {
                return self.setError("변환할 파일 목록을 만들 수 없습니다");
            };
        }
        if (sources.items.len == 0) {
            return self.setError("변환할 파일이 없습니다");
        }
        var total: usize = 0;
        for (sources.items) |source| {
            if (source.kind == .zip) {
                for (responses.items) |response| {
                    if (std.mem.eql(u8, response.path, source.path)) {
                        total += response.count;
                        break;
                    }
                }
            } else {
                total += 1;
            }
        }
        if (progress) |reporter| reporter.setTotal(total);
        var outputs = operations.processSources(alloc, io, config, sources.items, progress) catch {
            return self.setError("변환에 실패했습니다");
        };
        defer outputs.deinit();
        if (outputs.values.items.len == 0) {
            return self.setError("변환된 파일이 없습니다");
        }
        copy(&self.output_last_bytes, &self.output_last_len, outputs.values.items[outputs.values.items.len - 1]);
        self.processed = total;
        self.setStatus("변환을 완료했습니다");
    }

    fn appendInspected(self: *State, node: *const protocol.InspectNode, root: u16, depth: u16) void {
        if (self.item_count == self.items.len) return;
        var item: Item = .{};
        copy(&item.path_bytes, &item.path_len, node.path);
        copy(&item.name_bytes, &item.name_len, node.name);
        item.kind = node.kind;
        item.size = node.size;
        item.count = node.count;
        item.root_index = root;
        item.depth = depth;
        var size_buffer: [64]u8 = undefined;
        const size = formatSize(node.size, &size_buffer);
        const metadata = if (node.kind == .directory or node.kind == .pdf or node.kind == .zip)
            std.fmt.bufPrint(&item.metadata_bytes, "{d}개 항목 · {s}", .{ node.count, size }) catch ""
        else
            std.fmt.bufPrint(&item.metadata_bytes, "{s}", .{size}) catch "";
        item.metadata_len = metadata.len;
        self.items[self.item_count] = item;
        self.item_count += 1;
        for (node.children) |*child| self.appendInspected(child, root, depth + 1);
    }

    pub fn edit(self: *State, field: enum { suffix, width }, operation: EditOperation, text: ?[]const u8) void {
        const bytes: []u8 = if (field == .suffix) &self.suffix_bytes else &self.width_bytes;
        const len: *usize = if (field == .suffix) &self.suffix_len else &self.width_len;
        const caret: *usize = if (field == .suffix) &self.suffix_caret else &self.width_caret;
        if (text) |input| {
            if (input.len + len.* > bytes.len) return;
            std.mem.copyBackwards(u8, bytes[caret.* + input.len .. len.* + input.len], bytes[caret.*..len.*]);
            @memcpy(bytes[caret.* .. caret.* + input.len], input);
            caret.* += input.len;
            len.* += input.len;
        } else switch (operation) {
            .backspace => if (caret.* > 0) {
                const previous = previousBoundary(bytes[0..len.*], caret.*);
                const removed = caret.* - previous;
                std.mem.copyForwards(u8, bytes[previous .. len.* - removed], bytes[caret.*..len.*]);
                caret.* = previous;
                len.* -= removed;
            },
            .delete => if (caret.* < len.*) {
                const next = nextBoundary(bytes[0..len.*], caret.*);
                std.mem.copyForwards(u8, bytes[caret.* .. len.* - (next - caret.*)], bytes[next..len.*]);
                len.* -= next - caret.*;
            },
            .left => caret.* = previousBoundary(bytes[0..len.*], caret.*),
            .right => caret.* = if (caret.* < len.*) nextBoundary(bytes[0..len.*], caret.*) else len.*,
            .home => caret.* = 0,
            .end => caret.* = len.*,
        }
        if (field == .width) {
            const value = std.fmt.parseInt(u32, self.width(), 10) catch {
                self.setError("긴 변 크기를 숫자로 입력해주세요");
                return;
            };
            if (value == 0 or value > 1_000_000) {
                self.setError("긴 변 크기는 1에서 1,000,000 사이여야 합니다");
                return;
            }
            self.config.width = value;
        }
        self.clearError();
    }
};

fn formatSize(bytes: u64, buffer: *[64]u8) []const u8 {
    const divisor: u64, const unit: []const u8 = if (bytes >= 1_000_000_000)
        .{ 1_000_000_000, "GB" }
    else if (bytes >= 1_000_000)
        .{ 1_000_000, "MB" }
    else if (bytes >= 1_000)
        .{ 1_000, "KB" }
    else
        .{ 1, "B" };
    const whole = bytes / divisor;
    var digits: [20]u8 = undefined;
    const raw = std.fmt.bufPrint(&digits, "{d}", .{whole}) catch unreachable;
    var length: usize = 0;
    for (raw, 0..) |digit, index| {
        if (index != 0 and (raw.len - index) % 3 == 0) {
            buffer[length] = ',';
            length += 1;
        }
        buffer[length] = digit;
        length += 1;
    }
    const fraction = if (divisor == 1) "" else std.fmt.bufPrint(buffer[length..], ".{d:0>2}", .{(bytes % divisor) * 100 / divisor}) catch unreachable;
    length += fraction.len;
    buffer[length] = ' ';
    length += 1;
    @memcpy(buffer[length .. length + unit.len], unit);
    return buffer[0 .. length + unit.len];
}

fn inspectedNodeCount(node: protocol.InspectNode) usize {
    var count: usize = 1;
    for (node.children) |child| count +|= inspectedNodeCount(child);
    return count;
}

fn copy(destination: []u8, len: *usize, value: []const u8) void {
    len.* = @min(destination.len, value.len);
    @memcpy(destination[0..len.*], value[0..len.*]);
}

fn appendSources(alloc: Allocator, root: *const protocol.InspectNode, node: *const protocol.InspectNode, sources: *std.ArrayList(protocol.Source), page_names: *std.ArrayList([]u8)) !void {
    if (sources.items.len >= 2048) return error.TooManySources;
    switch (node.kind) {
        .directory => for (node.children) |*child| try appendSources(alloc, root, child, sources, page_names),
        .pdf => {
            for (0..node.count) |page_index| {
                const name = try std.fmt.allocPrint(alloc, "{d}", .{page_index + 1});
                page_names.append(alloc, name) catch |err| {
                    alloc.free(name);
                    return err;
                };
                try sources.append(alloc, .{ .path = node.path, .name = name, .root = root.path, .kind = .pdf, .page_index = @intCast(page_index) });
            }
        },
        else => {
            const relative = if (node.path.len > root.path.len and std.mem.startsWith(u8, node.path, root.path)) node.path[root.path.len + 1 ..] else node.name;
            try sources.append(alloc, .{ .path = node.path, .name = relative, .root = root.path, .kind = node.kind });
        },
    }
}

fn previousBoundary(bytes: []const u8, caret: usize) usize {
    var index = caret -| 1;
    while (index > 0 and (bytes[index] & 0xc0) == 0x80) index -= 1;
    return index;
}

fn nextBoundary(bytes: []const u8, caret: usize) usize {
    var index = @min(bytes.len, caret + 1);
    while (index < bytes.len and (bytes[index] & 0xc0) == 0x80) index += 1;
    return index;
}

test "quality and UTF-8 text edits update state" {
    var state = State.init();
    state.config.quality = 37;
    try std.testing.expectApproxEqAbs(@as(f32, 0.37), state.qualityFraction(), 0.001);
    state.edit(.suffix, .end, "가");
    state.edit(.suffix, .end, "b");
    state.edit(.suffix, .left, null);
    state.edit(.suffix, .backspace, null);
    try std.testing.expectEqualStrings("b", state.suffix());
}

test "file size labels use decimal units and grouped digits" {
    var buffer: [64]u8 = undefined;
    try std.testing.expectEqualStrings("999 B", formatSize(999, &buffer));
    try std.testing.expectEqualStrings("1.00 KB", formatSize(1_000, &buffer));
    try std.testing.expectEqualStrings("1.23 MB", formatSize(1_234_567, &buffer));
    try std.testing.expectEqualStrings("1,234.56 GB", formatSize(1_234_567_890_000, &buffer));
}
