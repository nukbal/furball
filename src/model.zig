const std = @import("std");
const native_sdk = @import("native_sdk");
const jobs = @import("core/jobs.zig");
const protocol = @import("core/protocol.zig");

const canvas = native_sdk.canvas;

pub const max_paths: usize = 64;
pub const max_path_bytes: usize = 1024;
pub const max_items: usize = 256;
pub const max_name_bytes: usize = 256;
pub const max_metadata_bytes: usize = 160;
pub const max_error_bytes: usize = 512;
pub const max_output_paths: usize = 128;
pub const max_output_bytes: usize = 1024;

pub const Item = struct {
    path_storage: [max_path_bytes]u8 = [_]u8{0} ** max_path_bytes,
    path_len: usize = 0,
    name_storage: [max_name_bytes]u8 = [_]u8{0} ** max_name_bytes,
    name_len: usize = 0,
    kind: protocol.Kind = .image,
    size: u64 = 0,
    count: u32 = 0,
    depth: u16 = 0,
    root_index: u16 = 0,
    level: u16 = 1,
    selected: bool = false,
    inspected: bool = false,
    inspect_ok: bool = false,
    metadata_storage: [max_metadata_bytes]u8 = [_]u8{0} ** max_metadata_bytes,
    metadata_len: usize = 0,
    thumbnail_storage: [max_path_bytes]u8 = [_]u8{0} ** max_path_bytes,
    thumbnail_len: usize = 0,
    thumbnail_id: canvas.ImageId = 0,
    image_id: canvas.ImageId = 0,

    pub fn path(item: *const Item) []const u8 {
        return item.path_storage[0..item.path_len];
    }

    pub fn name(item: *const Item) []const u8 {
        return item.name_storage[0..item.name_len];
    }

    pub fn thumbnail(item: *const Item) []const u8 {
        return item.thumbnail_storage[0..item.thumbnail_len];
    }

    pub fn metadata(item: *const Item) []const u8 {
        return item.metadata_storage[0..item.metadata_len];
    }
};

pub const Dialog = enum { none, files, output };
pub const AppearanceMode = enum { system, light, dark };

pub const DialogSelection = struct {
    paths: []const u8,
    count: usize,
};

pub const Msg = union(enum) {
    choose_files,
    choose_output,
    remove_file: u16,
    select_item: u16,
    process,
    reveal_output,
    dialog_ready: DialogSelection,
    dialog_cancelled,
    dropped: native_sdk.platform.FileDropEvent,
    set_appearance: native_sdk.Appearance,
    set_chrome: native_sdk.platform.WindowChrome,
    appearance_system,
    appearance_light,
    appearance_dark,
    mode_path,
    mode_overwrite,
    dir_none,
    dir_pdf,
    dir_zip,
    toggle_ai,
    edit_suffix: canvas.TextInputEvent,
    edit_width: canvas.TextInputEvent,
    quality_changed,
    job_event: native_sdk.EffectChannelEvent,
    thumbnail_done: native_sdk.EffectImageResult,
    config_loaded: native_sdk.EffectFileResult,
    config_saved: native_sdk.EffectFileResult,
    reveal_done: bool,
};

pub const Effects = native_sdk.Effects(Msg);

pub const inspect_key: u64 = 11;
pub const process_key: u64 = 12;
pub const config_read_key: u64 = 13;
pub const config_write_key: u64 = 14;
pub const thumbnail_key_base: u64 = 1000;
pub const regular_font_id: canvas.FontId = canvas.min_registered_font_id;
pub const medium_font_id: canvas.FontId = canvas.min_registered_font_id + 1;

pub const Model = struct {
    items: [max_items]Item = [_]Item{.{}} ** max_items,
    item_count: usize = 0,
    root_count: usize = 0,

    config: protocol.Config = .{},
    output_storage: [max_path_bytes]u8 = [_]u8{0} ** max_path_bytes,
    output_len: usize = 0,
    suffix_buffer: canvas.TextBuffer(128) = .{},
    width_buffer: canvas.TextBuffer(8) = canvas.TextBuffer(8).init("1440"),

    config_path_storage: [max_path_bytes]u8 = [_]u8{0} ** max_path_bytes,
    config_path_len: usize = 0,
    default_path_storage: [max_path_bytes]u8 = [_]u8{0} ** max_path_bytes,
    default_path_len: usize = 0,

    dialog: Dialog = .none,
    dialog_serial: u64 = 0,
    reveal_serial: u64 = 0,
    dialog_buffer: [native_sdk.platform.max_dialog_paths_bytes]u8 = [_]u8{0} ** native_sdk.platform.max_dialog_paths_bytes,
    dialog_len: usize = 0,
    dialog_count: usize = 0,

    job_pool: ?*jobs.JobPool = null,
    inspect_completed: usize = 0,
    process_completed: usize = 0,
    process_total: usize = 0,
    process_roots_completed: usize = 0,
    process_last_root: usize = 0,
    inspecting: bool = false,
    processing: bool = false,
    inspect_cancel_pending: bool = false,
    process_cancel_pending: bool = false,
    thumbnail_pending: usize = 0,
    config_loading: bool = false,
    config_saving: bool = false,
    config_dirty: bool = false,
    output_count: usize = 0,
    output_last_storage: [max_output_bytes]u8 = [_]u8{0} ** max_output_bytes,
    output_last_len: usize = 0,

    status_storage: [max_error_bytes]u8 = [_]u8{0} ** max_error_bytes,
    status_len: usize = 0,
    error_storage: [max_error_bytes]u8 = [_]u8{0} ** max_error_bytes,
    error_len: usize = 0,
    appearance: native_sdk.Appearance = .{},
    appearance_mode: AppearanceMode = .system,
    chrome_leading: f32 = 0,
    chrome_top: f32 = 0,

    pub fn configPath(model: *const Model) []const u8 {
        return model.config_path_storage[0..model.config_path_len];
    }

    pub fn defaultPath(model: *const Model) []const u8 {
        return model.default_path_storage[0..model.default_path_len];
    }

    pub fn outputPath(model: *const Model) []const u8 {
        return model.output_storage[0..model.output_len];
    }

    pub fn suffix(model: *const Model) []const u8 {
        return model.suffix_buffer.text();
    }

    pub fn width(model: *const Model) []const u8 {
        return model.width_buffer.text();
    }

    pub fn status(model: *const Model) []const u8 {
        return model.status_storage[0..model.status_len];
    }

    pub fn errorText(model: *const Model) []const u8 {
        return model.error_storage[0..model.error_len];
    }

    pub fn outputRevealPath(model: *const Model) []const u8 {
        return if (model.output_len != 0) model.outputPath() else model.output_last_storage[0..model.output_last_len];
    }

    pub fn chromeLeading(model: *const Model) f32 {
        return model.chrome_leading;
    }
    pub fn chromeTop(model: *const Model) f32 {
        return model.chrome_top;
    }
    pub fn outputLabel(model: *const Model, arena: std.mem.Allocator) []const u8 {
        if (model.output_len == 0) return "저장 위치를 선택해주세요";
        return std.fmt.allocPrint(arena, "저장 위치: {s}", .{model.outputPath()}) catch "저장 위치";
    }
    pub fn fileSummary(model: *const Model, arena: std.mem.Allocator) []const u8 {
        var total_count: u64 = 0;
        for (model.items[0..model.item_count]) |item| {
            if (item.depth != 0) continue;
            total_count += if (item.count == 0) 1 else item.count;
        }
        if (model.item_count > 0 and model.items[0].kind == .pdf) {
          return std.fmt.allocPrint(arena, "{d} 페이지", .{total_count}) catch "항목 정보";
        }
        return std.fmt.allocPrint(arena, "{d}개 항목", .{total_count}) catch "항목 정보";
    }
    pub fn progressValue(model: *const Model) f32 {
        if (!model.processing) return if (model.hasOutput()) 1 else 0;
        if (model.process_total == 0) return 0;
        return @as(f32, @floatFromInt(@min(model.process_completed, model.process_total))) / @as(f32, @floatFromInt(model.process_total));
    }
    pub fn processLabel(model: *const Model, arena: std.mem.Allocator) []const u8 {
        if (model.processing) return std.fmt.allocPrint(arena, "변환 중... {d}/{d}", .{ @min(model.process_completed, model.process_total), model.process_total }) catch "변환 중";
        if (model.hasOutput()) return "변환 완료";
        return "변환 시작";
    }
    pub fn qualityFraction(model: *const Model) f32 {
        return @as(f32, @floatFromInt(model.config.quality)) / 100.0;
    }
    pub fn qualityValue(model: *const Model, arena: std.mem.Allocator) []const u8 {
        return std.fmt.allocPrint(arena, "품질 {d}", .{model.config.quality}) catch "품질";
    }
    pub fn qualityAccessibility(model: *const Model) []const u8 {
        return model.qualityLabel();
    }
    pub fn aiEnabled(model: *const Model) bool {
        return model.config.ai;
    }

    pub fn isPathMode(model: *const Model) bool {
        return model.config.mode == .path;
    }
    pub fn isOverwriteMode(model: *const Model) bool {
        return model.config.mode == .overwrite;
    }
    pub fn isDirNone(model: *const Model) bool {
        return model.config.dir_mode == .none;
    }
    pub fn isDirPdf(model: *const Model) bool {
        return model.config.dir_mode == .pdf;
    }
    pub fn isDirZip(model: *const Model) bool {
        return model.config.dir_mode == .zip;
    }
    pub fn hasFiles(model: *const Model) bool {
        return model.root_count != 0;
    }
    pub fn canProcess(model: *const Model) bool {
        if (model.root_count == 0 or model.processing or model.inspecting or model.config_loading or model.config_saving) return false;
        for (model.items[0..model.item_count]) |item| {
            if (item.depth == 0 and !item.inspected) return false;
            if (item.depth == 0 and !item.inspect_ok) return false;
        }
        protocol.validateConfig(model.configValue()) catch return false;
        return true;
    }
    pub fn processDisabled(model: *const Model) bool {
        return !model.canProcess();
    }
    pub fn isProcessing(model: *const Model) bool {
        return model.processing or model.inspecting or model.inspect_cancel_pending or model.process_cancel_pending or model.thumbnail_pending != 0;
    }
    pub fn controlsDisabled(model: *const Model) bool {
        return model.isProcessing() or model.config_loading or model.config_saving;
    }
    pub fn hasOutput(model: *const Model) bool {
        return model.output_count != 0;
    }
    pub fn hasError(model: *const Model) bool {
        return model.error_len != 0 and model.hasFiles();
    }

    pub fn preview(model: *const Model, arena: std.mem.Allocator) []const Item {
      if (model.item_count == 0) return &.{};
      const res = arena.alloc(Item, 1) catch return &.{};
      @memcpy(res, model.items[0..1]);
      return res;
    }

    pub fn visible(model: *const Model, arena: std.mem.Allocator) []const Item {
      if (model.item_count < 2) return &.{};
      const result = arena.alloc(Item, model.item_count - 1) catch return &.{};
      @memcpy(result, model.items[1..model.item_count]);
      return result;
    }

    pub fn initPaths(model: *Model, io: std.Io, environ_map: *std.process.Environ.Map) void {
        _ = io;
        const env = native_sdk.debug.envFromMap(environ_map);
        var data_buffer: [max_path_bytes]u8 = undefined;
        if (native_sdk.app_dirs.resolveOne(.{ .name = "furball" }, native_sdk.app_dirs.currentPlatform(), env, .data, &data_buffer)) |data_dir| {
            var config_buffer: [max_path_bytes]u8 = undefined;
            if (native_sdk.app_dirs.join(native_sdk.app_dirs.currentPlatform(), &config_buffer, &.{ data_dir, "config.json" })) |config_path| {
                copyPath(&model.config_path_storage, &model.config_path_len, config_path);
            } else |_| {}
        } else |_| {}

        if (env.home) |home| {
            var download_buffer: [max_path_bytes]u8 = undefined;
            if (native_sdk.app_dirs.join(native_sdk.app_dirs.currentPlatform(), &download_buffer, &.{ home, "Downloads" })) |download_path| {
                copyPath(&model.default_path_storage, &model.default_path_len, download_path);
                if (model.output_len == 0) copyPath(&model.output_storage, &model.output_len, download_path);
            } else |_| {}
        }
    }

    pub fn copyPath(destination: []u8, length: *usize, source: []const u8) void {
        const amount = @min(destination.len, source.len);
        @memcpy(destination[0..amount], source[0..amount]);
        length.* = amount;
    }

    fn setStatus(model: *Model, text: []const u8) void {
        copyPath(&model.status_storage, &model.status_len, text);
    }

    fn setError(model: *Model, text: []const u8) void {
        copyPath(&model.error_storage, &model.error_len, text);
        setStatus(model, "처리 중 오류가 발생했습니다");
    }

    fn clearError(model: *Model) void {
        model.error_len = 0;
    }

    fn configValue(model: *const Model) protocol.Config {
        return .{
            .mode = model.config.mode,
            .path = model.outputPath(),
            .suffix = model.suffix(),
            .width = model.config.width,
            .quality = model.config.quality,
            .ai = model.config.ai,
            .dir_mode = model.config.dir_mode,
        };
    }

    fn copyItem(item: *Item, path: []const u8, name: []const u8, kind: protocol.Kind, size: u64, count: u32, depth: u16, root_index: u16, thumbnail: ?[]const u8) bool {
        if (path.len > item.path_storage.len or name.len > item.name_storage.len) return false;
        item.* = .{};
        @memcpy(item.path_storage[0..path.len], path);
        item.path_len = path.len;
        @memcpy(item.name_storage[0..name.len], name);
        item.name_len = name.len;
        item.kind = kind;
        item.size = size;
        item.count = count;
        item.depth = depth;
        item.root_index = root_index;
        item.level = depth +| 1;

        const metadata = formatBytes(&item.metadata_storage, size) catch item.metadata_storage[0..0];
        item.metadata_len = metadata.len;

        if (thumbnail) |value| {
            if (value.len <= item.thumbnail_storage.len) {
                @memcpy(item.thumbnail_storage[0..value.len], value);
                item.thumbnail_len = value.len;
            }
        }
        return true;
    }

    fn nodeCount(node: protocol.InspectNode) usize {
        var total: usize = 1;
        for (node.children) |child| total += nodeCount(child);
        return total;
    }

    fn nodeFits(node: protocol.InspectNode) bool {
        if (node.path.len > max_path_bytes or node.name.len > max_name_bytes) return false;
        if (node.thumbnail_blob) |thumbnail_blob| {
            if (thumbnail_blob.len > protocol.max_thumbnail_blob_base64_bytes) return false;
        }
        for (node.children) |child| if (!nodeFits(child)) return false;
        return true;
    }

    fn registerThumbnailBlob(item: *Item, encoded: []const u8, fx: *Effects) bool {
        if (encoded.len > protocol.max_thumbnail_blob_base64_bytes) return false;
        const decoded_len = std.base64.standard.Decoder.calcSizeForSlice(encoded) catch return false;
        if (decoded_len == 0 or decoded_len > protocol.max_thumbnail_blob_bytes) return false;
        const decoded = fx.allocator.alloc(u8, decoded_len) catch return false;
        defer fx.allocator.free(decoded);
        std.base64.standard.Decoder.decode(decoded, encoded) catch return false;
        const id = thumbnailId(item.path());
        _ = fx.registerImageBytes(id, decoded) catch return true;
        item.image_id = id;
        return true;
    }

    fn insertNode(model: *Model, node: protocol.InspectNode, depth: u16, root_index: u16, cursor: *usize, fx: *Effects) bool {
        if (model.item_count >= model.items.len or cursor.* > model.item_count) return false;
        const position = cursor.*;
        std.mem.copyBackwards(Item, model.items[position + 1 .. model.item_count + 1], model.items[position..model.item_count]);
        if (!copyItem(&model.items[position], node.path, node.name, node.kind, node.size, node.count, depth, root_index, node.thumbnail)) return false;
        if (node.thumbnail_blob) |thumbnail_blob| if (!registerThumbnailBlob(&model.items[position], thumbnail_blob, fx)) return false;
        model.item_count += 1;
        cursor.* += 1;
        for (node.children) |child| {
            if (!insertNode(model, child, depth +| 1, root_index, cursor, fx)) return false;
        }
        return true;
    }

    fn unregisterItem(_: *Model, item: *const Item, fx: *Effects) void {
        if (item.thumbnail_id != 0) fx.cancel(item.thumbnail_id);
        if (item.image_id != 0) _ = fx.unregisterImage(item.image_id);
    }

    fn clearItems(model: *Model, fx: *Effects) void {
        for (model.items[0..model.item_count]) |item| {
            model.unregisterItem(&item, fx);
        }
        model.item_count = 0;
        model.root_count = 0;
        model.inspect_completed = 0;
        model.process_completed = 0;
        model.process_total = 0;
        model.process_roots_completed = 0;
        model.process_last_root = 0;
        model.output_count = 0;
        model.output_last_len = 0;
        model.thumbnail_pending = 0;
    }

    fn prepareForLoad(model: *Model, fx: *Effects) bool {
        if (model.isProcessing()) return false;
        model.clearItems(fx);
        model.inspect_cancel_pending = false;
        model.process_cancel_pending = false;
        model.inspecting = false;
        model.processing = false;
        return true;
    }

    fn addPath(model: *Model, path: []const u8, fx: *Effects) void {
        _ = fx;
        if (model.isProcessing() or path.len == 0 or path.len > max_path_bytes or model.root_count >= max_paths) return;
        for (model.items[0..model.item_count]) |item| {
            if (item.depth == 0 and std.mem.eql(u8, item.path(), path)) return;
        }
        const root_index: u16 = @intCast(model.root_count);
        if (model.item_count >= model.items.len) return;
        const item = &model.items[model.item_count];
        const name = std.fs.path.basename(path);
        if (!copyItem(item, path, name, .image, 0, 0, 0, root_index, null)) return;
        item.selected = model.root_count == 0;
        model.item_count += 1;
        model.root_count += 1;
        model.clearError();
        setStatus(model, "파일을 살펴보고 있어요...");
    }

    fn startInspection(model: *Model, fx: *Effects) void {
        if (model.inspect_cancel_pending or model.process_cancel_pending or model.isProcessing()) return;
        if (!model.inspecting) {
            model.inspecting = true;
            model.inspect_completed = 0;
            model.submitInspection(fx);
        }
    }

    fn addDialogPaths(model: *Model, fx: *Effects) void {
        if (model.dialog == .output) {
            const first = firstDialogPath(model);
            if (first.len != 0) {
                if (first.len > model.output_storage.len) {
                    model.setError("저장 경로가 너무 깁니다");
                    model.dialog = .none;
                    return;
                }
                copyPath(&model.output_storage, &model.output_len, first);
                model.config.mode = .path;
                model.config_dirty = true;
                persist(model, fx);
                setStatus(model, "저장 폴더를 선택했습니다");
            }
            model.dialog = .none;
            return;
        }
        if (!model.prepareForLoad(fx)) {
            model.dialog = .none;
            return;
        }
        var start: usize = 0;
        for (model.dialog_buffer[0..model.dialog_len], 0..) |byte, index| {
            if (byte != '\n') continue;
            model.addPath(model.dialog_buffer[start..index], fx);
            start = index + 1;
        }
        if (start < model.dialog_len) model.addPath(model.dialog_buffer[start..model.dialog_len], fx);
        model.dialog = .none;
        model.startInspection(fx);
    }

    fn firstDialogPath(model: *const Model) []const u8 {
        const bytes = model.dialog_buffer[0..model.dialog_len];
        return if (std.mem.indexOfScalar(u8, bytes, '\n')) |index| bytes[0..index] else bytes;
    }

    fn rootPaths(model: *const Model, paths: *[max_paths][]const u8) usize {
        var count: usize = 0;
        for (model.items[0..model.item_count]) |*item| {
            if (item.depth != 0) continue;
            paths[count] = item.path();
            count += 1;
        }
        return count;
    }

    fn processTargetTotal(model: *const Model) usize {
        var total: usize = 0;
        for (model.items[0..model.item_count]) |item| {
            if (item.depth != 0) continue;
            const count: usize = switch (item.kind) {
                .directory, .pdf, .zip => @intCast(item.count),
                else => 1,
            };
            total +|= count;
        }
        return total;
    }

    fn submitInspection(model: *Model, fx: *Effects) void {
        const pool = model.job_pool orelse {
            model.inspecting = false;
            model.setError("파일 정보를 읽을 수 없습니다");
            return;
        };
        var paths: [max_paths][]const u8 = undefined;
        const count = model.rootPaths(&paths);
        pool.submitInspection(fx, paths[0..count], Effects.channelMsg(.job_event)) catch {
            model.inspecting = false;
            model.setError("파일 정보를 읽을 수 없습니다");
        };
    }

    fn thumbnailId(path: []const u8) canvas.ImageId {
        var id = std.hash.Wyhash.hash(0, path) | thumbnail_key_base;
        id &= ~canvas.media_surface_image_id_bit;
        if (id == 0 or id == inspect_key or id == process_key or id == config_read_key or id == config_write_key) id +%= thumbnail_key_base;
        return id;
    }

    fn loadThumbnail(model: *Model, item: *Item, fx: *Effects) void {
        const source = item.thumbnail();
        if (source.len == 0 or item.thumbnail_id != 0 or item.image_id != 0) return;
        const id = thumbnailId(item.path());
        item.thumbnail_id = id;
        model.thumbnail_pending += 1;
        fx.loadImage(.{ .id = id, .path = source, .on_result = Effects.imageMsg(.thumbnail_done) });
    }

    fn loadThumbnails(model: *Model, fx: *Effects, root_index: u16) void {
        for (model.items[0..model.item_count]) |*item| {
            if (item.root_index == root_index and item.depth == 0) {
                model.loadThumbnail(item, fx);
                break;
            }
        }
    }

    fn rootItemIndex(model: *const Model, root_index: usize) usize {
        var seen: usize = 0;
        for (model.items[0..model.item_count], 0..) |item, index| {
            if (item.depth == 0) {
                if (seen == root_index) return index;
                seen += 1;
            }
        }
        return model.item_count;
    }

    fn submitProcessing(model: *Model, fx: *Effects) void {
        const pool = model.job_pool orelse {
            model.processing = false;
            model.setError("변환에 실패했습니다");
            return;
        };
        var paths: [max_paths][]const u8 = undefined;
        const count = model.rootPaths(&paths);
        pool.submitProcessing(fx, paths[0..count], model.configValue(), Effects.channelMsg(.job_event)) catch {
            model.processing = false;
            model.setError("변환에 실패했습니다");
        };
    }

    fn persist(model: *Model, fx: *Effects) void {
        if (model.config_path_len == 0 or model.config_saving) return;
        protocol.validateConfig(configValue(model)) catch {
            model.config_dirty = true;
            model.setError("설정을 저장하기 전에 값을 확인해주세요");
            return;
        };
        model.config_dirty = false;
        model.config_saving = true;
        const encoded = protocol.stringify(fx.allocator, configValue(model)) catch {
            model.config_saving = false;
            model.config_dirty = true;
            model.setError("설정을 저장할 수 없습니다");
            return;
        };
        defer fx.allocator.free(encoded);
        fx.writeFile(.{ .key = config_write_key, .path = model.configPath(), .bytes = encoded, .on_result = Effects.fileMsg(.config_saved) });
    }

    fn settingChanged(model: *Model, fx: *Effects) void {
        model.config_dirty = true;
        persist(model, fx);
    }

    fn widthChanged(model: *Model, fx: *Effects) void {
        const value = std.fmt.parseInt(u32, std.mem.trim(u8, model.width(), " \t"), 10) catch {
            model.setError("짧은 변 길이를 숫자로 입력해주세요");
            return;
        };
        if (value == 0 or value > 1_000_000) {
            model.setError("짧은 변 길이는 1에서 1,000,000 사이여야 합니다");
            return;
        }
        model.config.width = value;
        model.clearError();
        model.settingChanged(fx);
    }

    fn copyDialogSelection(model: *Model, selection: DialogSelection) void {
        const amount = @min(selection.paths.len, model.dialog_buffer.len);
        @memcpy(model.dialog_buffer[0..amount], selection.paths[0..amount]);
        model.dialog_len = amount;
        model.dialog_count = selection.count;
    }

    fn selectItem(model: *Model, root_index: u16) void {
        if (root_index >= model.root_count) return;
        for (model.items[0..model.item_count]) |*item| item.selected = item.root_index == root_index and item.depth == 0;
    }

    fn inspectFailure(model: *Model, root_index: u16, message: []const u8) void {
        const root = model.rootItemIndex(root_index);
        if (root < model.item_count) {
            model.items[root].inspected = true;
            model.items[root].inspect_ok = false;
        }
        model.setError(message);
    }

    fn replaceInspectedTree(model: *Model, response: protocol.InspectResponse, root_index: u16, fx: *Effects) bool {
        if (!nodeFits(.{
            .path = response.path,
            .name = response.name,
            .kind = response.kind,
            .size = response.size,
            .count = response.count,
            .thumbnail = response.thumbnail,
            .thumbnail_blob = response.thumbnail_blob,
            .children = response.children,
        })) return false;
        const root = model.rootItemIndex(root_index);
        if (root >= model.item_count) return false;
        var children_count: usize = 0;
        for (response.children) |child| children_count += nodeCount(child);
        if (model.item_count - 1 + children_count > model.items.len) return false;

        const selected = model.items[root].selected;
        var end = root + 1;
        while (end < model.item_count and model.items[end].depth > 0) end += 1;
        for (model.items[root..end]) |*item| model.unregisterItem(item, fx);
        const old_children = end - root - 1;
        if (old_children != 0) {
            std.mem.copyForwards(Item, model.items[root + 1 .. model.item_count - old_children], model.items[end..model.item_count]);
            model.item_count -= old_children;
        }
        if (!copyItem(&model.items[root], response.path, response.name, response.kind, response.size, response.count, 0, root_index, response.thumbnail)) return false;
        if (response.thumbnail_blob) |thumbnail_blob| if (!registerThumbnailBlob(&model.items[root], thumbnail_blob, fx)) return false;
        model.items[root].selected = selected;
        var cursor = root + 1;
        for (response.children) |child| {
            if (!insertNode(model, child, 1, root_index, &cursor, fx)) return false;
        }
        model.items[root].inspected = true;
        model.items[root].inspect_ok = true;
        model.loadThumbnails(fx, root_index);
        return true;
    }

    fn jobError(kind: jobs.Kind) []const u8 {
        return if (kind == .inspect) "파일 정보를 읽을 수 없습니다" else "변환에 실패했습니다";
    }

    fn consumeJob(model: *Model, fx: *Effects, completion: *jobs.Completion) void {
        const root_index = completion.root_index;
        switch (completion.outcome) {
            .inspect => |response| {
                if (!model.replaceInspectedTree(response, root_index, fx)) {
                    model.inspectFailure(root_index, "파일 정보가 너무 크거나 올바르지 않습니다");
                }
                model.inspect_completed += 1;
            },
            .process => |result| {
                model.process_roots_completed += 1;
                if (result.values.items.len == 0) {
                    model.setError("변환된 파일이 없습니다");
                } else {
                    model.output_count = @min(max_output_paths, model.output_count + result.values.items.len);
                    if (root_index >= model.process_last_root) {
                        model.process_last_root = root_index;
                        copyPath(&model.output_last_storage, &model.output_last_len, result.values.items[result.values.items.len - 1]);
                    }
                }
            },
            .failed => {
                if (completion.kind == .inspect) {
                    model.inspectFailure(root_index, jobError(.inspect));
                    model.inspect_completed += 1;
                } else {
                    model.process_roots_completed += 1;
                    model.setError(jobError(.process));
                }
            },
        }
    }

    fn consumeJobEvents(model: *Model, fx: *Effects, event: native_sdk.EffectChannelEvent) void {
        const kind: jobs.Kind = switch (event.key) {
            inspect_key => .inspect,
            process_key => .process,
            else => return,
        };
        if (event.kind == .closed) {
            if (kind == .inspect) model.inspect_cancel_pending = false else model.process_cancel_pending = false;
            return;
        }
        if (event.kind == .rejected) {
            if (kind == .inspect) {
                model.inspecting = false;
                model.inspect_cancel_pending = false;
            } else {
                model.processing = false;
                model.process_cancel_pending = false;
            }
            model.setError(jobError(kind));
            return;
        }
        const pool = model.job_pool orelse return;
        var notification_id: ?u64 = null;
        if (event.bytes.len == jobs.notification_bytes) {
            var bytes: [jobs.notification_bytes]u8 = undefined;
            @memcpy(&bytes, event.bytes);
            notification_id = std.mem.readInt(u64, &bytes, .little);
        }
        var completion: jobs.Completion = undefined;
        var first = true;
        while (pool.take(kind, if (first) notification_id else null, &completion)) {
            model.consumeJob(fx, &completion);
            completion.deinit(pool.allocator);
            first = false;
        }
        if (kind == .process) model.process_completed = @min(model.process_total, pool.progress(.process));
        if (kind == .inspect and model.inspect_completed >= model.root_count) {
            model.inspecting = false;
            if (!model.hasError()) setStatus(model, "파일을 준비했습니다");
        }
        if (kind == .process and model.process_roots_completed >= model.root_count) {
            model.processing = false;
            if (!model.hasError()) setStatus(model, "변환을 완료했습니다");
        }
        pool.rearm(kind);
    }

    pub fn update(model: *Model, msg: Msg, fx: *Effects) void {
        switch (msg) {
            .choose_files => {
                if (model.isProcessing()) return;
                model.dialog = .files;
                model.dialog_serial +%= 1;
            },
            .choose_output => {
                if (model.isProcessing()) return;
                model.dialog = .output;
                model.dialog_serial +%= 1;
            },
            .remove_file => |root_index| {
                if (model.isProcessing()) return;
                if (root_index >= model.root_count) return;
                const begin = model.rootItemIndex(root_index);
                var end = begin + 1;
                while (end < model.item_count and model.items[end].depth > 0) end += 1;
                const removed = end - begin;
                for (model.items[begin..end]) |*item| {
                    model.unregisterItem(item, fx);
                }
                std.mem.copyForwards(Item, model.items[begin .. model.item_count - removed], model.items[end..model.item_count]);
                model.item_count -= removed;
                model.root_count -= 1;
                for (model.items[0..model.item_count]) |*item| {
                    if (item.depth == 0 and item.root_index > root_index) item.root_index -= 1;
                }
                if (model.root_count != 0) {
                    model.selectItem(@intCast(@min(root_index, model.root_count - 1)));
                } else {
                    setStatus(model, "파일을 추가해주세요");
                }
            },
            .select_item => |root_index| {
                if (model.isProcessing()) return;
                model.selectItem(root_index);
            },
            .process => {
                if (!model.canProcess()) return;
                model.processing = true;
                model.process_completed = 0;
                model.process_total = model.processTargetTotal();
                model.process_roots_completed = 0;
                model.process_last_root = 0;
                model.output_count = 0;
                model.output_last_len = 0;
                setStatus(model, "변환 중입니다...");
                model.submitProcessing(fx);
            },
            .reveal_output => {
                if (model.outputRevealPath().len != 0) model.reveal_serial +%= 1;
            },
            .dialog_ready => |selection| {
                model.copyDialogSelection(selection);
                model.addDialogPaths(fx);
            },
            .dialog_cancelled => model.dialog = .none,
            .dropped => |drop| {
                if (!model.prepareForLoad(fx)) return;
                for (drop.paths) |path| model.addPath(path, fx);
                model.startInspection(fx);
            },
            .set_appearance => |appearance| model.appearance = appearance,
            .set_chrome => |chrome| {
                model.chrome_leading = chrome.insets.left;
                model.chrome_top = chrome.insets.top;
            },
            .appearance_system => model.appearance_mode = .system,
            .appearance_light => model.appearance_mode = .light,
            .appearance_dark => model.appearance_mode = .dark,
            .mode_path => {
                if (model.controlsDisabled()) return;
                model.config.mode = .path;
                model.clearError();
                model.settingChanged(fx);
            },
            .mode_overwrite => {
                if (model.controlsDisabled()) return;
                model.config.mode = .overwrite;
                model.clearError();
                model.settingChanged(fx);
            },
            .dir_none => {
                if (model.controlsDisabled()) return;
                model.config.dir_mode = .none;
                model.settingChanged(fx);
            },
            .dir_pdf => {
                if (model.controlsDisabled()) return;
                model.config.dir_mode = .pdf;
                model.settingChanged(fx);
            },
            .dir_zip => {
                if (model.controlsDisabled()) return;
                model.config.dir_mode = .zip;
                model.settingChanged(fx);
            },
            .toggle_ai => {
                if (model.controlsDisabled()) return;
                model.config.ai = !model.config.ai;
                model.settingChanged(fx);
            },
            .edit_suffix => |event| {
                if (model.controlsDisabled()) return;
                model.suffix_buffer.apply(event);
                model.clearError();
                model.settingChanged(fx);
            },
            .edit_width => |event| {
                if (model.controlsDisabled()) return;
                model.width_buffer.apply(event);
                model.widthChanged(fx);
            },
            .quality_changed => {
                if (model.controlsDisabled()) return;
                model.clearError();
                model.settingChanged(fx);
            },
            .job_event => |event| model.consumeJobEvents(fx, event),
            .thumbnail_done => |result| {
                for (model.items[0..model.item_count]) |*item| {
                    if (item.thumbnail_id != result.id) continue;
                    item.thumbnail_id = 0;
                    if (model.thumbnail_pending != 0) model.thumbnail_pending -= 1;
                    if (result.outcome == .loaded) {
                        item.image_id = result.id;
                    } else if (result.outcome != .cancelled) {
                        item.image_id = 0;
                    }
                    break;
                }
                if (result.outcome != .loaded and result.outcome != .cancelled and result.outcome != .not_found) model.setError("미리보기를 불러올 수 없습니다");
            },
            .config_loaded => |result| {
                model.config_loading = false;
                if (result.outcome == .not_found) return;
                if (result.outcome != .ok or result.bytes.len == 0 or result.outcome == .truncated) {
                    model.setError("설정 파일을 읽을 수 없습니다");
                    return;
                }
                var arena_state = std.heap.ArenaAllocator.init(fx.allocator);
                defer arena_state.deinit();
                const parsed = protocol.parseConfig(arena_state.allocator(), result.bytes) catch {
                    model.setError("설정 파일 형식이 올바르지 않습니다");
                    return;
                };
                model.config.mode = parsed.value.mode;
                model.config.width = parsed.value.width;
                model.config.quality = parsed.value.quality;
                model.config.ai = parsed.value.ai;
                model.config.dir_mode = parsed.value.dir_mode;
                model.output_len = 0;
                if (parsed.value.path.len != 0) {
                    if (parsed.value.path.len > model.output_storage.len) {
                        model.setError("저장 경로가 너무 깁니다");
                        return;
                    }
                    copyPath(&model.output_storage, &model.output_len, parsed.value.path);
                } else if (model.default_path_len != 0) {
                    copyPath(&model.output_storage, &model.output_len, model.defaultPath());
                }
                model.suffix_buffer.set(parsed.value.suffix);
                var width_storage: [8]u8 = undefined;
                const width_text = std.fmt.bufPrint(&width_storage, "{d}", .{parsed.value.width}) catch "1440";
                model.width_buffer.set(width_text);
                model.config_dirty = false;
            },
            .config_saved => |result| {
                model.config_saving = false;
                if (result.outcome != .ok) {
                    model.config_dirty = true;
                    model.setError("설정을 저장할 수 없습니다");
                } else if (model.config_dirty) {
                    model.persist(fx);
                }
            },
            .reveal_done => |ok| {
                if (!ok) model.setError("결과 폴더를 열 수 없습니다");
            },
        }
    }

    pub fn initFx(model: *Model, fx: *Effects) void {
        setStatus(model, "파일을 추가해주세요");
        if (model.config_path_len != 0) {
            model.config_loading = true;
            fx.readFile(.{ .key = config_read_key, .path = model.configPath(), .on_result = Effects.fileMsg(.config_loaded) });
        }
    }
};

fn formatBytes(buf: []u8, bytes: u64) ![]const u8 {
    const KB: u64 = 1024;
    const MB: u64 = 1024 * 1024;

    if (bytes >= MB) {
        const whole = bytes / MB;
        const frac = (bytes % MB) * 100 / MB;

        var int_buf: [32]u8 = undefined;
        const integer = try formatComma(&int_buf, whole);

        return std.fmt.bufPrint(buf, "{s}.{d:0>2} MB", .{
            integer,
            frac,
        });
    }

    if (bytes >= KB) {
        const kb = bytes / KB;

        var int_buf: [32]u8 = undefined;
        const integer = try formatComma(&int_buf, kb);

        return std.fmt.bufPrint(buf, "{s} KB", .{integer});
    }

    var int_buf: [32]u8 = undefined;
    const integer = try formatComma(&int_buf, bytes);

    return std.fmt.bufPrint(buf, "{s} B", .{integer});
}

fn formatComma(buf: []u8, value: u64) ![]const u8 {
    var digits_buf: [32]u8 = undefined;
    const digits = try std.fmt.bufPrint(&digits_buf, "{d}", .{value});

    const comma_count = if (digits.len == 0) 0 else (digits.len - 1) / 3;
    const output_len = digits.len + comma_count;

    if (output_len > buf.len)
        return error.NoSpaceLeft;

    var src: usize = digits.len;
    var dst: usize = output_len;
    var count: usize = 0;

    while (src > 0) {
        src -= 1;
        dst -= 1;
        buf[dst] = digits[src];

        count += 1;

        if (count == 3 and src > 0) {
            dst -= 1;
            buf[dst] = ',';
            count = 0;
        }
    }

    return buf[0..output_len];
}
