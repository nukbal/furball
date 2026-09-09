const std = @import("std");
const builtin = @import("builtin");
const runner = @import("runner");
const native_sdk = @import("native_sdk");
const jobs_mod = @import("core/jobs.zig");
const model_mod = @import("model.zig");
const view_mod = @import("view.zig");

pub const panic = std.debug.FullPanic(native_sdk.debug.capturePanic);

const geometry = native_sdk.geometry;
const canvas = native_sdk.canvas;

pub const Model = model_mod.Model;
pub const Msg = model_mod.Msg;
pub const Effects = model_mod.Effects;
pub const JobPool = jobs_mod.JobPool;
pub const update = Model.update;
pub const initFx = Model.initFx;

pub const canvas_label = "furball-canvas";
pub const window_width: f32 = 980;
pub const window_height: f32 = 720;
pub const window_min_width: f32 = 760;
pub const window_min_height: f32 = 560;

const app_permissions = [_][]const u8{
    native_sdk.security.permission_dialog,
    native_sdk.security.permission_filesystem,
    native_sdk.security.permission_view,
};
const shell_views = [_]native_sdk.ShellView{.{
    .label = canvas_label,
    .kind = .gpu_surface,
    .fill = true,
    .role = "Furball canvas",
    .accessibility_label = "Furball",
    .gpu_backend = if (builtin.os.tag == .windows) .direct2d else .metal,
    .gpu_pixel_format = .bgra8_unorm,
    .gpu_present_mode = .timer,
    .gpu_alpha_mode = .@"opaque",
    .gpu_color_space = .srgb,
    .gpu_vsync = true,
}};
const shell_windows = [_]native_sdk.ShellWindow{.{
    .label = "main",
    .title = "Furball",
    .width = window_width,
    .height = window_height,
    .min_width = window_min_width,
    .min_height = window_min_height,
    .titlebar = .hidden_inset_tall,
    .views = &shell_views,
}};
pub const shell_scene: native_sdk.ShellConfig = .{ .windows = &shell_windows };

const SdkApp = native_sdk.UiAppWithFeatures(Model, Msg, .{ .runtime_markup = view_mod.dev_markup_reload });

fn tokensFromModel(model: *const Model) canvas.DesignTokens {
    var tokens = canvas.DesignTokens.theme(.{
        .color_scheme = .dark,
        .contrast = if (model.appearance.high_contrast) .high else .standard,
        .reduce_motion = model.appearance.reduce_motion,
    });
    tokens.typography.font_id = model_mod.regular_font_id;
    tokens.typography.mono_font_id = model_mod.regular_font_id;
    tokens.typography.button_font_id = model_mod.medium_font_id;
    return tokens;
}

fn onDrop(drop: native_sdk.platform.FileDropEvent) ?Msg {
    return .{ .dropped = drop };
}

fn onChrome(chrome: native_sdk.platform.WindowChrome) ?Msg {
    return .{ .set_chrome = chrome };
}

fn sync(model: *Model, layout: canvas.WidgetLayoutTree) void {
    for (layout.nodes) |node| {
        if (node.widget.kind != .slider) continue;
        const fraction = if (node.widget.value < 0) 0 else if (node.widget.value > 1) 1 else node.widget.value;
        model.config.quality = @intFromFloat(@round(fraction * 100));
    }
}

pub const App = struct {
    app: *SdkApp,
    jobs: *JobPool,
    handled_dialog_serial: u64 = 0,
    handled_reveal_serial: u64 = 0,

    pub fn getApp(self: *App) native_sdk.App {
        return .{ .context = self, .name = "furball", .scene_fn = scene, .event_fn = event, .stop_fn = stop };
    }

    fn scene(context: *anyopaque) anyerror!native_sdk.ShellConfig {
        _ = context;
        return shell_scene;
    }

    fn event(context: *anyopaque, runtime: *native_sdk.Runtime, event_value: native_sdk.Event) anyerror!void {
        const self: *App = @ptrCast(@alignCast(context));
        try self.app.app().event(runtime, event_value);
        try self.presentDialog(runtime);
        try self.revealOutput(runtime);
    }

    fn stop(context: *anyopaque, runtime: *native_sdk.Runtime) anyerror!void {
        const self: *App = @ptrCast(@alignCast(context));
        self.jobs.cancelAll(&self.app.effects);
        self.jobs.shutdown();
        try self.app.app().stop(runtime);
    }

    fn presentDialog(self: *App, runtime: *native_sdk.Runtime) !void {
        if (self.app.model.dialog == .none) return;
        if (self.app.model.dialog_serial == self.handled_dialog_serial) return;
        self.handled_dialog_serial = self.app.model.dialog_serial;
        const dialog = self.app.model.dialog;
        var buffer: [native_sdk.platform.max_dialog_paths_bytes]u8 = undefined;
        const result = runtime.showOpenDialog(.{
            .title = if (dialog == .files) "파일 고르기" else "저장 폴더",
            .default_path = if (dialog == .files) self.app.model.defaultPath() else self.app.model.outputPath(),
            .allow_directories = true,
            .allow_multiple = dialog == .files,
        }, &buffer) catch {
            try self.app.dispatch(runtime, 1, .dialog_cancelled);
            return;
        };
        if (result.count == 0) {
            try self.app.dispatch(runtime, 1, .dialog_cancelled);
            return;
        }
        try self.app.dispatch(runtime, 1, .{ .dialog_ready = .{ .paths = result.paths, .count = result.count } });
    }

    fn revealOutput(self: *App, runtime: *native_sdk.Runtime) !void {
        if (self.app.model.reveal_serial == self.handled_reveal_serial) return;
        self.handled_reveal_serial = self.app.model.reveal_serial;
        const path = self.app.model.outputRevealPath();
        if (path.len == 0) {
            try self.app.dispatch(runtime, 1, .{ .reveal_done = false });
            return;
        }
        const ok = blk: {
            runtime.revealPath(path) catch break :blk false;
            break :blk true;
        };
        try self.app.dispatch(runtime, 1, .{ .reveal_done = ok });
    }
};

pub fn main(init: std.process.Init) !void {
    var job_pool: JobPool = undefined;
    job_pool.init(std.heap.page_allocator, init.io);
    errdefer job_pool.deinit();
    const app_state = try std.heap.page_allocator.create(SdkApp);
    defer std.heap.page_allocator.destroy(app_state);
    var model = Model{};
    model.initPaths(init.io, init.environ_map);
    model.job_pool = &job_pool;
    app_state.* = SdkApp.init(std.heap.page_allocator, model, .{
        .name = "furball",
        .scene = shell_scene,
        .canvas_label = canvas_label,
        .update_fx = update,
        .init_fx = initFx,
        .tokens_fn = tokensFromModel,
        .sync = sync,
        .fonts = &.{
            .{ .id = model_mod.regular_font_id, .name = "Pretendard-Regular.ttf", .ttf = @embedFile("fonts/Pretendard-Regular.ttf") },
            .{ .id = model_mod.medium_font_id, .name = "Pretendard-Medium.ttf", .ttf = @embedFile("fonts/Pretendard-Medium.ttf") },
        },
        .on_chrome = onChrome,
        .on_drop = onDrop,
        .view = view_mod.CompiledAppView.build,
        .markup = if (view_mod.dev_markup_reload) .{ .source = view_mod.app_markup, .watch_path = "native/app.native", .io = init.io } else null,
    });
    defer app_state.deinit();
    defer job_pool.deinit();
    var app_wrapper = App{ .app = app_state, .jobs = &job_pool };
    try runner.runWithOptions(app_wrapper.getApp(), .{
        .app_name = "furball",
        .window_title = "Furball",
        .bundle_id = "dev.nukbal.furball",
        .icon_path = "assets/icon.icns",
        .default_frame = geometry.RectF.init(0, 0, window_width, window_height),
        .js_window_api = false,
        .security = .{ .permissions = &app_permissions, .navigation = .{ .allowed_origins = &.{ "zero://inline", "zero://app" } } },
    }, init);
}

test {
    _ = @import("tests.zig");
}
