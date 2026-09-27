const std = @import("std");
const builtin = @import("builtin");
const sdl = @import("sdl");
const clay = @import("clay");
const state_mod = @import("state.zig");
const View = @import("ui/view.zig");
const Renderer = @import("ui/renderer.zig");
const Assets = @import("ui/assets.zig");
const image = @import("core/image.zig");
const memory = @import("core/memory.zig");
const operations = @import("core/operations.zig");
const protocol = @import("core/protocol.zig");

const allocator = std.heap.page_allocator;

extern "c" fn MacOsWindowConfigure(window: ?*anyopaque, redraw: *const fn (?*anyopaque) callconv(.c) void, context: ?*anyopaque) void;

const Worker = struct {
    const Kind = enum { load, process };

    thread: ?std.Thread = null,
    done: std.atomic.Value(bool) = .init(false),
    completed: std.atomic.Value(usize) = .init(0),
    total: std.atomic.Value(usize) = .init(0),
    kind: Kind = .load,
    snapshot: state_mod.State = undefined,
    paths: [state_mod.max_paths][state_mod.max_path_bytes]u8 = undefined,
    path_lens: [state_mod.max_paths]usize = undefined,
    path_count: usize = 0,
    preview_thumbnail: ?Assets.BinaryThumbnail = null,
    preview_changed: bool = false,
    wake_event_type: u32 = 0,
    wake_pending: std.atomic.Value(bool) = .init(false),

    fn active(self: *const Worker) bool {
        return self.thread != null;
    }

    fn startLoad(self: *Worker, alloc: std.mem.Allocator, io: std.Io, state: *state_mod.State, paths: []const []const u8) !void {
        if (self.active()) return error.AlreadyWorking;
        if (paths.len > self.paths.len) return error.TooManyPaths;
        for (paths, 0..) |path, index| {
            if (path.len > state_mod.max_path_bytes) return error.PathTooLong;
            @memcpy(self.paths[index][0..path.len], path);
            self.path_lens[index] = path.len;
        }
        self.snapshot = state.*;
        self.snapshot.loading = false;
        self.preview_changed = false;
        self.path_count = paths.len;
        self.kind = .load;
        self.completed.store(0, .release);
        self.total.store(0, .release);
        self.done.store(false, .release);
        self.thread = try std.Thread.spawn(.{}, run, .{ self, alloc, io });
        state.loading = true;
        state.clearError();
        state.setStatus("파일을 불러오는 중...");
    }

    fn startProcess(self: *Worker, alloc: std.mem.Allocator, io: std.Io, state: *state_mod.State) !void {
        if (self.active()) return error.AlreadyWorking;
        state.processing = true;
        self.snapshot = state.*;
        self.snapshot.processing = false;
        self.kind = .process;
        self.completed.store(0, .release);
        var estimated_total: usize = 0;
        for (state.items[0..state.item_count]) |item| if (item.depth == 0) {
            estimated_total += @max(1, item.count);
        };
        self.total.store(estimated_total, .release);
        self.done.store(false, .release);
        self.thread = std.Thread.spawn(.{}, run, .{ self, alloc, io }) catch |err| {
            state.processing = false;
            return err;
        };
        state.processed = 0;
        state.output_last_len = 0;
        state.setStatus("변환 중입니다...");
    }

    fn run(self: *Worker, alloc: std.mem.Allocator, io: std.Io) void {
        switch (self.kind) {
            .load => {
                var paths: [state_mod.max_paths][]const u8 = undefined;
                for (0..self.path_count) |index| paths[index] = self.paths[index][0..self.path_lens[index]];

                var first_response: ?protocol.InspectResponse = null;
                self.preview_changed = if (self.path_count != 0)
                    self.snapshot.addPaths(alloc, io, paths[0..self.path_count], &first_response)
                else
                    true;

                if (self.preview_changed) {
                    if (first_response) |*response| {
                        self.loadPreview(alloc, io, response);
                        operations.freeResponse(alloc, response);
                    } else if (self.snapshot.item_count != 0) {
                        var response = operations.inspect(alloc, io, self.snapshot.items[0].path()) catch null;
                        if (response) |*value| {
                            self.loadPreview(alloc, io, value);
                            operations.freeResponse(alloc, value);
                        }
                    }
                }
            },
            .process => self.snapshot.process(alloc, io, self.reporter()),
        }
        self.done.store(true, .release);
        self.postWake();
    }

    fn reporter(self: *Worker) protocol.Progress {
        return .{ .context = self, .advance_fn = advance, .total_fn = setTotal };
    }

    fn advance(context: *anyopaque) void {
        const self: *Worker = @ptrCast(@alignCast(context));
        _ = self.completed.fetchAdd(1, .acq_rel);
        self.postWake();
    }

    fn setTotal(context: *anyopaque, total: usize) void {
        const self: *Worker = @ptrCast(@alignCast(context));
        self.total.store(total, .release);
        self.postWake();
    }

    fn postWake(self: *Worker) void {
        if (self.wake_pending.swap(true, .acq_rel)) return;
        var event: sdl.SDL_Event = std.mem.zeroes(sdl.SDL_Event);
        event.type = self.wake_event_type;
        if (!sdl.SDL_PushEvent(&event)) self.wake_pending.store(false, .release);
    }

    fn loadPreview(self: *Worker, alloc: std.mem.Allocator, io: std.Io, result: *const protocol.InspectResponse) void {
        if (result.thumbnail) |path| {
            const bytes = std.Io.Dir.cwd().readFileAlloc(io, path, alloc, .limited(512 * 1024 * 1024)) catch return;
            defer alloc.free(bytes);
            self.preview_thumbnail = .{ .bytes = image.thumbnailBytes(alloc, bytes) catch return };
        } else if (result.thumbnail_blob) |blob| {
            const length = std.base64.standard.Decoder.calcSizeForSlice(blob) catch return;
            const bytes = alloc.alloc(u8, length) catch return;
            std.base64.standard.Decoder.decode(bytes, blob) catch {
                alloc.free(bytes);
                return;
            };
            self.preview_thumbnail = .{ .bytes = bytes };
        }
    }

    fn finish(self: *Worker, state: *state_mod.State, renderer: *Renderer, alloc: std.mem.Allocator) bool {
        if (!self.active() or !self.done.load(.acquire)) return false;
        self.thread.?.join();
        self.thread = null;
        state.* = self.snapshot;
        if (self.kind == .load and self.preview_changed) {
            renderer.setPreviewThumbnail(alloc, self.preview_thumbnail) catch {};
            self.preview_thumbnail = null;
        }
        if (self.kind == .process) memory.releaseIdle();
        return true;
    }

    fn shutdown(self: *Worker, alloc: std.mem.Allocator) void {
        if (self.thread) |thread| thread.join();
        if (self.preview_thumbnail) |thumbnail| alloc.free(thumbnail.bytes);
    }
};

const App = struct {
    const Dialog = enum { files, output };

    window: *sdl.SDL_Window,
    io: std.Io,
    home: []const u8,
    state: state_mod.State,
    renderer: *Renderer,
    scratch: *std.heap.ArenaAllocator,
    view: View = .{},
    worker: Worker = .{},
    worker_io: std.Io,
    arrow: *sdl.SDL_Cursor,
    hand: *sdl.SDL_Cursor,
    ibeam: *sdl.SDL_Cursor,
    resize: *sdl.SDL_Cursor,
    active_cursor: ?*sdl.SDL_Cursor = null,
    pending_dialog: ?Dialog = null,
    dialog_kind: std.atomic.Value(u8) = .init(0),
    dialog_result_ready: std.atomic.Value(bool) = .init(false),
    dialog_error: bool = false,
    dialog_path_count: usize = 0,
    dialog_paths: [state_mod.max_paths][state_mod.max_path_bytes]u8 = undefined,
    dialog_path_lengths: [state_mod.max_paths]usize = undefined,
    dirty: bool = true,
    quit: bool = false,
    pointer_x: f32 = 0,
    pointer_y: f32 = 0,
    pointer_down: bool = false,
    scroll: clay.Clay_Vector2 = .{ .x = 0, .y = 0 },
    slider_dragging: bool = false,
    pressed: ?View.HitTarget = null,
    dropped_paths: [state_mod.max_paths][state_mod.max_path_bytes]u8 = undefined,
    dropped_lengths: [state_mod.max_paths]usize = undefined,
    dropped_count: usize = 0,

    fn render(self: *App) void {
        _ = self.scratch.reset(.retain_capacity);
        const size = Renderer.windowSize(self.window);
        self.renderer.updateOutputScale(size.width, size.height);
        const phase: u8 = if (self.state.loading) @intCast((sdl.SDL_GetTicks() / 125) % 4) else 0;
        const commands = self.view.draw(&self.state, self.renderer.hasPreview(), phase, self.worker.completed.load(.acquire), self.worker.total.load(.acquire), @floatCast(size.width), @floatCast(size.height), .{
            .x = self.pointer_x,
            .y = self.pointer_y,
        }, self.pointer_down, self.scroll, self.scratch.allocator());
        self.scroll = .{ .x = 0, .y = 0 };
        self.renderer.render(commands, size.width, size.height);
        self.updateCursor();
        self.dirty = false;
    }

    fn updateCursor(self: *App) void {
        const cursor = if (self.slider_dragging) self.resize else if (self.view.actionAt(self.pointer_x, self.pointer_y)) |target| switch (target.action) {
            .focus_input => self.ibeam,
            .slider => self.resize,
            .command => self.hand,
        } else self.arrow;
        if (cursor != self.active_cursor) {
            _ = sdl.SDL_SetCursor(cursor);
            self.active_cursor = cursor;
        }
    }

    fn setFocus(self: *App, focus: ?View.Focus) void {
        if (self.view.focused == focus) return;
        self.view.focused = focus;
        if (focus) |_| {
            _ = sdl.SDL_StartTextInput(self.window);
        } else {
            _ = sdl.SDL_StopTextInput(self.window);
        }
        self.dirty = true;
    }

    fn updateQuality(self: *App) void {
        const value = self.view.qualityAt(self.pointer_x) orelse return;
        if (value == self.state.config.quality) return;
        self.state.config.quality = value;
        self.dirty = true;
    }

    fn persist(self: *App) void {
        self.state.saveConfig(allocator, self.io, self.home);
    }

    fn command(self: *App, value: @import("ui/ui.zig").Command) void {
        switch (value) {
            .choose_files => self.openDialog(.files),
            .choose_output => self.openDialog(.output),
            .reveal_output => if (!Renderer.revealPath(self.state.outputRevealPath())) self.state.setError("결과 폴더를 열 수 없습니다"),
            .process => self.worker.startProcess(allocator, self.worker_io, &self.state) catch self.state.setError("변환을 시작할 수 없습니다"),
            .toggle_settings => self.view.settings_open = !self.view.settings_open,
            .remove_file => |index| {
                self.state.remove(index);
                self.worker.startLoad(allocator, self.worker_io, &self.state, &.{}) catch self.state.setError("미리보기를 불러올 수 없습니다");
            },
            .select_item => |index| self.state.select(index),
            .mode_path => {
                self.state.config.mode = .path;
                self.persist();
            },
            .mode_overwrite => {
                self.state.config.mode = .overwrite;
                self.persist();
            },
            .dir_none => {
                self.state.config.dir_mode = .none;
                self.persist();
            },
            .dir_pdf => {
                self.state.config.dir_mode = .pdf;
                self.persist();
            },
            .dir_zip => {
                self.state.config.dir_mode = .zip;
                self.persist();
            },
            .toggle_ai => {
                self.state.config.ai = !self.state.config.ai;
                self.persist();
            },
        }
        self.dirty = true;
    }

    fn openDialog(self: *App, dialog: Dialog) void {
        if (self.pending_dialog != null) return;
        self.pending_dialog = dialog;
        self.dialog_kind.store(@intCast(@intFromEnum(dialog) + 1), .release);
        const result = switch (dialog) {
            .files => Renderer.showOpenFileDialog(self.window, "", true, dialogResult, self),
            .output => Renderer.showOpenFolderDialog(self.window, self.state.outputPath(), dialogResult, self),
        };
        result catch {
            self.dialog_kind.store(0, .release);
            self.pending_dialog = null;
            self.state.setError("대화상자를 열 수 없습니다");
        };
    }

    fn finishDialogResult(self: *App) bool {
        if (!self.dialog_result_ready.swap(false, .acq_rel)) return false;
        const dialog = self.pending_dialog orelse return false;
        self.pending_dialog = null;
        self.dialog_kind.store(0, .release);

        if (self.dialog_error) {
            self.state.setError("선택한 경로를 읽을 수 없습니다");
        } else if (self.dialog_path_count != 0) {
            switch (dialog) {
                .files => {
                    var paths: [state_mod.max_paths][]const u8 = undefined;
                    for (0..self.dialog_path_count) |index| paths[index] = self.dialog_paths[index][0..self.dialog_path_lengths[index]];
                    self.worker.startLoad(allocator, self.worker_io, &self.state, paths[0..self.dialog_path_count]) catch self.state.setError("파일을 불러올 수 없습니다");
                },
                .output => {
                    self.state.setOutput(self.dialog_paths[0][0..self.dialog_path_lengths[0]]);
                    self.persist();
                },
            }
            self.dirty = true;
            return true;
        } else {
            return false;
        }
        self.dirty = true;
        return true;
    }

    fn edit(self: *App, operation: state_mod.EditOperation, value: ?[]const u8) void {
        const focused = self.view.focused orelse return;
        self.state.edit(if (focused == .suffix) .suffix else .width, operation, value);
        self.persist();
        self.dirty = true;
    }

    fn handleEvent(self: *App, event: sdl.SDL_Event) void {
        switch (event.type) {
            sdl.SDL_EVENT_QUIT, sdl.SDL_EVENT_WINDOW_CLOSE_REQUESTED => self.quit = true,
            sdl.SDL_EVENT_WINDOW_RESIZED,
            sdl.SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED,
            sdl.SDL_EVENT_WINDOW_DISPLAY_SCALE_CHANGED,
            sdl.SDL_EVENT_WINDOW_EXPOSED,
            sdl.SDL_EVENT_WINDOW_RESTORED,
            => self.dirty = true,
            sdl.SDL_EVENT_WINDOW_MOUSE_LEAVE => {
                self.pointer_x = -1;
                self.pointer_y = -1;
                self.updateCursor();
                self.dirty = true;
            },
            sdl.SDL_EVENT_MOUSE_MOTION => {
                const x: f32 = event.motion.x;
                const y: f32 = event.motion.y;
                if (x == self.pointer_x and y == self.pointer_y) return;
                self.pointer_x = x;
                self.pointer_y = y;
                if (self.slider_dragging) self.updateQuality();
                self.updateCursor();
                self.dirty = true;
            },
            sdl.SDL_EVENT_MOUSE_BUTTON_DOWN, sdl.SDL_EVENT_MOUSE_BUTTON_UP => self.handleMouseButton(event.button),
            sdl.SDL_EVENT_MOUSE_WHEEL => {
                const direction: f32 = if (event.wheel.direction == sdl.SDL_MOUSEWHEEL_FLIPPED) -1 else 1;
                self.pointer_x = event.wheel.mouse_x;
                self.pointer_y = event.wheel.mouse_y;
                const x = event.wheel.x * direction;
                const y = event.wheel.y * direction;
                if (x != 0 or y != 0) {
                    self.scroll.x += x;
                    self.scroll.y += y;
                    self.dirty = true;
                }
            },
            sdl.SDL_EVENT_TEXT_INPUT => {
                if (event.text.text) |text| self.edit(.end, std.mem.span(text));
            },
            sdl.SDL_EVENT_KEY_DOWN => self.handleKey(event.key),
            sdl.SDL_EVENT_DROP_BEGIN => self.dropped_count = 0,
            sdl.SDL_EVENT_DROP_FILE => self.handleDropFile(event.drop),
            sdl.SDL_EVENT_DROP_COMPLETE => self.finishDrop(),
            else => if (event.type == self.worker.wake_event_type) {
                self.worker.wake_pending.store(false, .release);
                if (self.finishDialogResult() or self.worker.active()) self.dirty = true;
            },
        }
    }

    fn handleMouseButton(self: *App, button: sdl.SDL_MouseButtonEvent) void {
        if (button.button != sdl.SDL_BUTTON_LEFT) return;
        self.pointer_x = button.x;
        self.pointer_y = button.y;
        const target = self.view.actionAt(self.pointer_x, self.pointer_y);
        if (button.down) {
            self.pointer_down = true;
            self.pressed = target;
            self.slider_dragging = if (target) |hit| hit.action == .slider else false;
            if (target) |hit| switch (hit.action) {
                .focus_input => |input| self.setFocus(input),
                .slider => self.updateQuality(),
                .command => self.setFocus(null),
            } else self.setFocus(null);
        } else {
            self.pointer_down = false;
            if (self.slider_dragging) {
                self.updateQuality();
                self.persist();
            } else if (self.pressed) |pressed| {
                if (target) |released| {
                    if (pressed.id.id == released.id.id and pressed.id.offset == released.id.offset) switch (released.action) {
                        .command => |action| self.command(action),
                        else => {},
                    };
                }
            }
            self.slider_dragging = false;
            self.pressed = null;
        }
        self.updateCursor();
        self.dirty = true;
    }

    fn handleKey(self: *App, key: sdl.SDL_KeyboardEvent) void {
        if (!key.down) return;
        switch (key.key) {
            sdl.SDLK_BACKSPACE => self.edit(.backspace, null),
            sdl.SDLK_DELETE => self.edit(.delete, null),
            sdl.SDLK_LEFT => self.edit(.left, null),
            sdl.SDLK_RIGHT => self.edit(.right, null),
            sdl.SDLK_HOME => self.edit(.home, null),
            sdl.SDLK_END => self.edit(.end, null),
            sdl.SDLK_RETURN, sdl.SDLK_ESCAPE => self.setFocus(null),
            sdl.SDLK_TAB => self.setFocus(if (self.view.focused == .suffix) .width else .suffix),
            else => {},
        }
    }

    fn handleDropFile(self: *App, event: sdl.SDL_DropEvent) void {
        const data = event.data orelse return;
        const path = std.mem.span(data);
        if (path.len > state_mod.max_path_bytes or self.dropped_count == self.dropped_paths.len) {
            self.state.setError("드롭한 파일이 너무 많거나 경로가 너무 깁니다");
            self.dirty = true;
            return;
        }
        @memcpy(self.dropped_paths[self.dropped_count][0..path.len], path);
        self.dropped_lengths[self.dropped_count] = path.len;
        self.dropped_count += 1;
    }

    fn finishDrop(self: *App) void {
        if (self.dropped_count == 0) return;
        if (self.state.controlsDisabled()) {
            self.dropped_count = 0;
            return;
        }
        var paths: [state_mod.max_paths][]const u8 = undefined;
        for (0..self.dropped_count) |index| paths[index] = self.dropped_paths[index][0..self.dropped_lengths[index]];
        self.worker.startLoad(allocator, self.worker_io, &self.state, paths[0..self.dropped_count]) catch self.state.setError("파일을 불러올 수 없습니다");
        self.dropped_count = 0;
        self.dirty = true;
    }
};

fn dialogResult(user_data: ?*anyopaque, filelist: [*c]const [*c]const u8, _: c_int) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(user_data orelse return));
    const kind = app.dialog_kind.load(.acquire);
    if (kind == 0) return;

    app.dialog_path_count = 0;
    app.dialog_error = filelist == null;
    if (filelist != null and filelist[0] != null) {
        const dialog: App.Dialog = @enumFromInt(kind - 1);
        const limit = if (dialog == .output) 1 else app.dialog_paths.len;
        while (app.dialog_path_count < limit and filelist[app.dialog_path_count] != null) : (app.dialog_path_count += 1) {
            const path = std.mem.span(filelist[app.dialog_path_count]);
            if (path.len > state_mod.max_path_bytes) {
                app.dialog_error = true;
                app.dialog_path_count = 0;
                break;
            }
            @memcpy(app.dialog_paths[app.dialog_path_count][0..path.len], path);
            app.dialog_path_lengths[app.dialog_path_count] = path.len;
        }
        if (dialog == .files and app.dialog_path_count == limit and filelist[limit] != null) {
            app.dialog_error = true;
            app.dialog_path_count = 0;
        }
    }
    app.dialog_result_ready.store(true, .release);
    app.worker.postWake();
}

pub fn main(init: std.process.Init) !void {
    if (!sdl.SDL_Init(sdl.SDL_INIT_VIDEO)) return error.SdlInitializationFailed;
    defer sdl.SDL_Quit();

    const wake_event_type = sdl.SDL_RegisterEvents(1);
    if (wake_event_type == 0xFFFFFFFF) return error.EventRegistrationFailed;

    const window = sdl.SDL_CreateWindow("Furball", 1060, 760, sdl.SDL_WINDOW_RESIZABLE | sdl.SDL_WINDOW_HIGH_PIXEL_DENSITY | sdl.SDL_WINDOW_HIDDEN) orelse return error.WindowCreationFailed;
    defer sdl.SDL_DestroyWindow(window);
    _ = sdl.SDL_SetWindowMinimumSize(window, 780, 600);

    var renderer = try Renderer.init(allocator, init.io, init.environ_map.get("HOME") orelse "", window);
    defer renderer.deinit(allocator);
    renderer.bind();

    var scratch = std.heap.ArenaAllocator.init(allocator);
    defer scratch.deinit();

    var threaded = std.Io.Threaded.init(allocator, .{});
    defer threaded.deinit();

    const arrow = sdl.SDL_CreateSystemCursor(sdl.SDL_SYSTEM_CURSOR_DEFAULT) orelse return error.CursorCreationFailed;
    defer sdl.SDL_DestroyCursor(arrow);
    const hand = sdl.SDL_CreateSystemCursor(sdl.SDL_SYSTEM_CURSOR_POINTER) orelse return error.CursorCreationFailed;
    defer sdl.SDL_DestroyCursor(hand);
    const ibeam = sdl.SDL_CreateSystemCursor(sdl.SDL_SYSTEM_CURSOR_TEXT) orelse return error.CursorCreationFailed;
    defer sdl.SDL_DestroyCursor(ibeam);
    const resize = sdl.SDL_CreateSystemCursor(sdl.SDL_SYSTEM_CURSOR_EW_RESIZE) orelse return error.CursorCreationFailed;
    defer sdl.SDL_DestroyCursor(resize);

    var app: App = .{
        .window = window,
        .io = init.io,
        .worker_io = threaded.io(),
        .home = init.environ_map.get("HOME") orelse "",
        .state = state_mod.State.init(),
        .renderer = &renderer,
        .scratch = &scratch,
        .arrow = arrow,
        .hand = hand,
        .ibeam = ibeam,
        .resize = resize,
    };
    app.worker.wake_event_type = wake_event_type;
    app.state.loadConfig(allocator, init.io, app.home);
    defer app.worker.shutdown(allocator);

    if (builtin.os.tag == .macos and !sdl.SDL_SetWindowHitTest(window, titlebarHitTest, &app)) return error.WindowHitTestFailed;
    if (builtin.os.tag == .macos) {
        const cocoa_window = sdl.SDL_GetPointerProperty(sdl.SDL_GetWindowProperties(window), sdl.SDL_PROP_WINDOW_COCOA_WINDOW_POINTER, null);
        MacOsWindowConfigure(cocoa_window, macWindowResized, &app);
    }

    if (!sdl.SDL_ShowWindow(window)) return error.WindowShowFailed;

    while (!app.quit or app.pending_dialog != null) {
        if (app.worker.finish(&app.state, app.renderer, allocator)) app.dirty = true;
        if (app.dirty) app.render();

        var event: sdl.SDL_Event = undefined;
        const received = sdl.SDL_WaitEventTimeout(&event, 125);
        if (received) {
            app.handleEvent(event);
        } else if (app.state.loading) {
            app.dirty = true;
        }
        while (sdl.SDL_PollEvent(&event)) app.handleEvent(event);
    }
}

export fn macWindowResized(context: ?*anyopaque) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(context orelse return));
    app.render();
}

fn titlebarHitTest(_: ?*sdl.SDL_Window, area: [*c]const sdl.SDL_Point, data: ?*anyopaque) callconv(.c) sdl.SDL_HitTestResult {
    if (area == null) return @intCast(sdl.SDL_HITTEST_NORMAL);

    const point = area[0];
    const app: *App = @ptrCast(@alignCast(data orelse return @intCast(sdl.SDL_HITTEST_NORMAL)));

    if (point.x < 76 or point.y < 0 or point.y >= View.header_height) return @intCast(sdl.SDL_HITTEST_NORMAL);
    if (app.view.actionAt(@floatFromInt(point.x), @floatFromInt(point.y)) != null) return @intCast(sdl.SDL_HITTEST_NORMAL);
    return @intCast(sdl.SDL_HITTEST_DRAGGABLE);
}

test {
    _ = @import("tests.zig");
    _ = @import("ui/view.zig");
}
