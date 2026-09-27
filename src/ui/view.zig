const std = @import("std");
const clay = @import("clay");
const ui = @import("ui.zig");
const state_mod = @import("../state.zig");
const Assets = @import("assets.zig");

pub const Focus = ui.Input;
pub const HitTarget = ui.HitTarget;
pub const Action = ui.Action;

const View = @This();

pub const header_height: f32 = 48;
const footer_height: f32 = 96;
const footer_margin: f32 = 16;
const options_gap: f32 = 16;

elements: ui.View = .{},
focused: ?Focus = null,
settings_open: bool = true,

pub fn actionAt(self: *const View, x: f32, y: f32) ?HitTarget {
    for (0..self.elements.hit_count) |reverse_index| {
        const target = self.elements.hit_targets[self.elements.hit_count - 1 - reverse_index];
        const data = clay.Clay_GetElementData(target.id);
        if (!data.found) continue;
        const box = data.boundingBox;
        if (x >= box.x and x <= box.x + box.width and y >= box.y and y <= box.y + box.height) return target;
    }
    return null;
}

pub fn qualityAt(self: *const View, x: f32) ?u8 {
    for (self.elements.hit_targets[0..self.elements.hit_count]) |target| {
        if (target.action != .slider) continue;
        const data = clay.Clay_GetElementData(target.id);
        if (!data.found or data.boundingBox.width <= 0) continue;
        return qualityAtPosition(x, data.boundingBox.x, data.boundingBox.width);
    }
    return null;
}

pub fn draw(self: *View, model: *const state_mod.State, preview_available: bool, phase: u8, completed: usize, total: usize, width: f32, height: f32, pointer: clay.Clay_Vector2, pointer_down: bool, scroll: clay.Clay_Vector2, scratch: std.mem.Allocator) clay.Clay_RenderCommandArray {
    clay.Clay_SetLayoutDimensions(.{ .width = width, .height = height });
    clay.Clay_SetPointerState(pointer, pointer_down);
    clay.Clay_UpdateScrollContainers(false, scroll, 1.0 / 60.0);
    clay.Clay_BeginLayout();
    self.elements.reset();

    ui.begin("app-root", ui.growAxis(), ui.growAxis(), clay.CLAY_TOP_TO_BOTTOM, 0, 0);
      self.drawHeader(model, scratch);
      ui.begin("workspace", ui.growAxis(), ui.growAxis(), clay.CLAY_LEFT_TO_RIGHT, 16, 12);
        self.drawFiles(model, preview_available, phase, scratch);
      ui.end();
      self.drawProgress(model, phase, completed, total, scratch);
      if (self.settings_open) self.drawConfig(model, height - header_height - footer_height - footer_margin - options_gap, scratch);
    ui.end();
    return clay.Clay_EndLayout(0);
}

fn elementsPtr(self: *View) *ui.View {
    return &self.elements;
}

fn drawHeader(view: *View, model: *const state_mod.State, scratch: std.mem.Allocator) void {
    var header: clay.Clay_ElementDeclaration = .{};
    header.layout = ui.layout(ui.growAxis(), ui.fixedAxis(header_height), clay.CLAY_LEFT_TO_RIGHT, 0, 10);
    header.layout.padding.right = 16;
    header.backgroundColor = ui.clayColor(ui.colors.surface);
    header.border.color = ui.clayColor(ui.colors.stroke);
    header.border.width = .{ .left = 0, .right = 0, .top = 0, .bottom = 1 };

    ui.open("window-header", header);
      ui.begin("traffic-light-space", ui.fixedAxis(76), ui.fixedAxis(1), clay.CLAY_LEFT_TO_RIGHT, 0, 0);
      ui.end();

      var content: clay.Clay_ElementDeclaration = .{};
      content.layout = ui.layout(ui.growAxis(), ui.growAxis(), clay.CLAY_LEFT_TO_RIGHT, 0, 10);
      content.layout.padding.top = 8;
      ui.open("header-contents", content);

        if (model.root_count > 0) {
          var sum: clay.Clay_ElementDeclaration = .{};
          sum.layout = ui.layout(ui.growAxis(), ui.growAxis(), clay.CLAY_LEFT_TO_RIGHT, 0, 0);
          sum.layout.padding.left = 6;
          sum.layout.padding.top = 6;

          ui.open("header-summary", sum);
            const summary = std.fmt.allocPrint(scratch, "{d}개 파일 · {s}", .{ model.root_count, model.fileSummary(scratch) }) catch "파일 목록";
            ui.text(summary, .{ .size = 12, .color = ui.colors.muted });
          ui.end();
        }

        ui.begin("header-spacer", ui.growAxis(), ui.fixedAxis(1), clay.CLAY_LEFT_TO_RIGHT, 0, 0);
        ui.end();

        ui.button(view.elementsPtr(), ui.View.makeId("add-files"), .{ .icon = .plus, .action = .{ .command = .choose_files }, .enabled = !model.controlsDisabled(), .width = ui.fixedAxis(32), .height = 32 });
        ui.button(view.elementsPtr(), ui.View.makeId("settings-toggle"), .{ .icon = if (view.settings_open) .sidebar_close else .settings, .action = .{ .command = .toggle_settings }, .width = ui.fixedAxis(32), .height = 32 });
      ui.end();
    ui.end();
}

fn drawFiles(view: *View, model: *const state_mod.State, preview_available: bool, phase: u8, scratch: std.mem.Allocator) void {
    var area: clay.Clay_ElementDeclaration = .{};
    area.layout = ui.layout(ui.growAxis(), ui.growAxis(), clay.CLAY_TOP_TO_BOTTOM, 0, 10);
    if (view.settings_open) area.layout.padding.right = 272;

    ui.open("files-area", area);
    if (model.root_count == 0) {
        var empty: clay.Clay_ElementDeclaration = .{};
        empty.layout = ui.layout(ui.growAxis(), ui.growAxis(), clay.CLAY_TOP_TO_BOTTOM, 0, 12);
        empty.layout.childAlignment = .{ .x = clay.CLAY_ALIGN_X_CENTER, .y = clay.CLAY_ALIGN_Y_CENTER };
        ui.open("files-empty", empty);
        if (model.loading) {
            ui.spinner(phase, 0);
            ui.text("파일을 불러오는 중...", .{ .size = 17, .font = .medium });
        } else {
            iconImage("empty-folder", .folder, 56);
            ui.text("파일을 추가해주세요.", .{ .size = 17, .font = .medium });
            ui.text("이미지, PDF, ZIP, MP4, 폴더를 끌어다 놓거나 파일을 골라주세요", .{ .size = 12, .color = ui.colors.muted });
        }
        ui.end();
        return ui.end();
    }

    ui.panel("preview-card", ui.growAxis(), ui.fixedAxis(204), 12, 0, ui.colors.surface);
    ui.begin("preview-row", ui.growAxis(), ui.growAxis(), clay.CLAY_LEFT_TO_RIGHT, 0, 10);
    var image_box: clay.Clay_ElementDeclaration = .{};
    image_box.layout = ui.layout(ui.fixedAxis(160), ui.fixedAxis(180), clay.CLAY_TOP_TO_BOTTOM, 0, 0);
    image_box.backgroundColor = ui.clayColor(ui.colors.background);
    image_box.cornerRadius = .{ .topLeft = 7, .topRight = 7, .bottomLeft = 7, .bottomRight = 7 };
    image_box.layout.childAlignment = .{ .x = clay.CLAY_ALIGN_X_CENTER, .y = clay.CLAY_ALIGN_Y_CENTER };
    ui.open("preview-image-box", image_box);
    if (preview_available) {
        var declaration: clay.Clay_ElementDeclaration = .{};
        declaration.layout = ui.layout(ui.growAxis(), ui.growAxis(), clay.CLAY_TOP_TO_BOTTOM, 0, 0);
        declaration.image.imageData = Assets.clayImageData(.preview);
        ui.selfClose("preview-image", declaration);
    } else if (model.loading) {
        ui.spinner(phase, 1);
    } else {
        ui.text("미리보기 없음", .{ .size = 11, .color = ui.colors.muted });
    }
    ui.end();
    ui.begin("preview-info", ui.growAxis(), ui.growAxis(), clay.CLAY_TOP_TO_BOTTOM, 0, 6);
    ui.text(Assets.displayText(scratch, model.items[0].name()), .{ .size = 14 });
    ui.text(model.items[0].metadata(), .{ .size = 11, .color = ui.colors.muted });
    ui.end();
    ui.button(view.elementsPtr(), ui.View.makeId("remove-first"), .{ .icon = .x, .action = .{ .command = .{ .remove_file = 0 } }, .enabled = !model.controlsDisabled(), .width = ui.fixedAxis(30), .height = 30 });
    ui.end();
    ui.end();

    const scroll_data = clay.Clay_GetScrollContainerData(ui.View.makeId("file-list"));
    const scroll_offset = if (scroll_data.found and scroll_data.scrollPosition != null) @max(0, -scroll_data.scrollPosition[0].y) else 0;
    const viewport = if (scroll_data.found) scroll_data.scrollContainerDimensions.height else 600;
    const rows = listRowCount(model);
    const first = @min(rows, @as(usize, @intFromFloat(scroll_offset / 50)) -| 1);
    const last = @min(rows, first + @as(usize, @intFromFloat(@ceil(viewport / 50))) + 3);
    ui.scrollContainer("file-list", ui.growAxis(), ui.growAxis(), 0, 0, ui.colors.background);
    if (first != 0) listSpacer("list-before", @floatFromInt(first * 50));
    for (first..last) |row_index| {
        const entry = listEntryAt(model, row_index) orelse continue;
        switch (entry) {
            .item => |index| {
                const item = &model.items[index];
                const root = &model.items[item.root_index];
                const name = if (root.kind == .directory and item.path().len > root.path().len + 1 and std.mem.startsWith(u8, item.path(), root.path()))
                    item.path()[root.path().len + 1 ..]
                else
                    item.name();
                view.drawRow(@intCast(row_index), Assets.displayText(scratch, name), item.metadata(), if (item.depth == 0 and index != 0) @intCast(index) else null, !model.controlsDisabled());
            },
            .page => |page| {
                const page_name = std.fmt.allocPrint(scratch, "{d}페이지", .{page.number}) catch "PDF 페이지";
                view.drawRow(@intCast(row_index), page_name, Assets.displayText(scratch, model.items[page.item_index].name()), null, !model.controlsDisabled());
            },
        }
        listSpacerIndexed(@intCast(row_index), 4);
    }
    if (last < rows) listSpacer("list-after", @floatFromInt((rows - last) * 50));
    listSpacer("list-floating-clearance", 144);
    ui.end();
    ui.end();
}

const ListEntry = union(enum) {
    item: usize,
    page: struct { item_index: usize, number: usize },
};

fn listRowCount(model: *const state_mod.State) usize {
    var count: usize = 0;
    for (model.items[0..model.item_count]) |item| {
        if (item.kind == .directory or item.kind == .zip) continue;
        count += if (item.kind == .pdf and item.depth == 0) item.count else 1;
    }
    return count;
}

fn listEntryAt(model: *const state_mod.State, requested: usize) ?ListEntry {
    var row = requested;
    for (model.items[0..model.item_count], 0..) |item, index| {
        if (item.kind == .directory or item.kind == .zip) continue;
        if (item.kind == .pdf and item.depth == 0) {
            if (row < item.count) return .{ .page = .{ .item_index = index, .number = row + 1 } };
            row -= item.count;
        } else {
            if (row == 0) return .{ .item = index };
            row -= 1;
        }
    }
    return null;
}

fn listSpacer(name: []const u8, height: f32) void {
    ui.begin(name, ui.growAxis(), ui.fixedAxis(height), clay.CLAY_LEFT_TO_RIGHT, 0, 0);
    ui.end();
}

fn listSpacerIndexed(index: u32, height: f32) void {
    ui.beginId(ui.View.makeIndexedId("list-gap", index), ui.growAxis(), ui.fixedAxis(height), clay.CLAY_LEFT_TO_RIGHT, 0, 0);
    ui.end();
}

fn drawRow(view: *View, row_index: u32, name: []const u8, metadata: []const u8, remove_index: ?u16, enabled: bool) void {
    const row_id = ui.View.makeIndexedId("file-row", row_index);
    var row: clay.Clay_ElementDeclaration = .{};
    row.layout = ui.layout(ui.growAxis(), ui.fixedAxis(46), clay.CLAY_LEFT_TO_RIGHT, 9, 9);
    row.layout.childAlignment.y = clay.CLAY_ALIGN_Y_CENTER;
    row.backgroundColor = ui.clayColor(ui.colors.surface);
    row.cornerRadius = .{ .topLeft = 7, .topRight = 7, .bottomLeft = 7, .bottomRight = 7 };

    ui.openId(row_id, row);
      iconImageIndexed("list-icon", row_index, .file_text, 20);

      ui.beginId(ui.View.makeIndexedId("file-label", row_index), ui.growAxis(), ui.fixedAxis(38), clay.CLAY_TOP_TO_BOTTOM, 0, 1);
        ui.text(name, .{ .size = 12 });
        ui.text(metadata, .{ .size = 10, .color = ui.colors.muted });
      ui.end();

      if (remove_index) |index| ui.button(view.elementsPtr(), ui.View.makeIndexedId("remove-file", row_index), .{ .icon = .x, .action = .{ .command = .{ .remove_file = index } }, .enabled = enabled, .width = ui.fixedAxis(27), .height = 27 });
    ui.end();
}

fn drawConfig(view: *View, model: *const state_mod.State, height: f32, scratch: std.mem.Allocator) void {
    const disabled = model.controlsDisabled();
    var sidebar: clay.Clay_ElementDeclaration = .{};
    sidebar.layout = ui.layout(ui.fixedAxis(256), ui.fixedAxis(@max(0, height)), clay.CLAY_TOP_TO_BOTTOM, 8, 0);
    sidebar.backgroundColor = ui.clayColor(ui.colors.background);
    sidebar.cornerRadius = .{ .topLeft = 12, .topRight = 12, .bottomLeft = 12, .bottomRight = 12 };
    sidebar.border.color = ui.clayColor(ui.colors.stroke);
    sidebar.border.width = .{ .left = 1, .right = 1, .top = 1, .bottom = 1 };
    sidebar.floating.attachTo = @intCast(clay.CLAY_ATTACH_TO_ELEMENT_WITH_ID);
    sidebar.floating.parentId = ui.View.makeId("settings-toggle").id;
    sidebar.floating.attachPoints = .{ .element = @intCast(clay.CLAY_ATTACH_POINT_RIGHT_TOP), .parent = @intCast(clay.CLAY_ATTACH_POINT_RIGHT_BOTTOM) };
    sidebar.floating.offset = .{ .x = 0, .y = 18 };
    sidebar.floating.zIndex = 20;

    ui.open("sidebar", sidebar);
    ui.scrollContainer("settings-scroll", ui.growAxis(), ui.growAxis(), 0, 8, ui.colors.background);

    ui.panel("save-card", ui.growAxis(), ui.fixedAxis(115), 10, 8, ui.colors.surface);
      ui.begin("save-heading", ui.growAxis(), ui.fixedAxis(30), clay.CLAY_LEFT_TO_RIGHT, 0, 6);
        ui.text("저장 방식", .{ .size = 13, .font = .medium });
        ui.begin("save-spacer", ui.growAxis(), ui.fixedAxis(1), clay.CLAY_LEFT_TO_RIGHT, 0, 0);
        ui.end();
        ui.button(view.elementsPtr(), ui.View.makeId("choose-output"), .{ .label = "폴더 선택", .action = .{ .command = .choose_output }, .enabled = !disabled, .width = ui.fixedAxis(92), .height = 28 });
      ui.end();

      const output = if (model.outputPath().len == 0) "폴더를 선택해주세요" else model.outputPath();
      const location = std.fmt.allocPrint(scratch, "저장 위치: {s}", .{output}) catch "저장 위치";
      ui.text(Assets.displayText(scratch, location), .{ .size = 11, .color = ui.colors.muted });
      ui.begin("mode-options", ui.growAxis(), ui.fixedAxis(30), clay.CLAY_LEFT_TO_RIGHT, 0, 5);
        ui.button(view.elementsPtr(), ui.View.makeId("mode-path"), .{ .label = "지정 위치에 저장", .action = .{ .command = .mode_path }, .primary = model.isPathMode(), .enabled = !disabled, .height = 28 });
        ui.button(view.elementsPtr(), ui.View.makeId("mode-overwrite"), .{ .label = "원본 덮어쓰기", .action = .{ .command = .mode_overwrite }, .primary = model.isOverwriteMode(), .enabled = !disabled, .height = 28 });
      ui.end();
    ui.end();

    ui.panel("image-card", ui.growAxis(), ui.fixedAxis(232), 10, 6, ui.colors.surface);
      ui.textField(view.elementsPtr(), "width-field", "짧은 변 길이 (px)", model.width(), "1440", .width, view.focused == .width, !disabled);
      _ = ui.slider(view.elementsPtr(), "quality-slider", model.qualityFraction(), !disabled);
      const quality = std.fmt.allocPrint(scratch, "품질 {d}", .{model.config.quality}) catch "품질";
      ui.text(quality, .{ .size = 12, .color = ui.colors.muted });
      ui.textField(view.elementsPtr(), "suffix-field", "파일 이름 접미사", model.suffix(), "예: -optimized", .suffix, view.focused == .suffix, !disabled);
      ui.begin("ai-row", ui.growAxis(), ui.fixedAxis(28), clay.CLAY_LEFT_TO_RIGHT, 0, 8);
        ui.checkbox(view.elementsPtr(), "toggle-ai", .{ .command = .toggle_ai }, model.aiEnabled(), !disabled);
        ui.text("AI 업스케일", .{ .size = 12, .font = .medium });
      ui.end();
    ui.end();

    ui.panel("batch-card", ui.growAxis(), ui.fixedAxis(75), 10, 6, ui.colors.surface);
      ui.text("다수 파일 처리 방식", .{ .size = 12, .color = ui.colors.muted });
      ui.begin("dir-options", ui.growAxis(), ui.fixedAxis(30), clay.CLAY_LEFT_TO_RIGHT, 0, 5);
        ui.button(view.elementsPtr(), ui.View.makeId("dir-none"), .{ .label = "개별 처리", .action = .{ .command = .dir_none }, .primary = model.isDirNone(), .enabled = !disabled, .height = 28 });
        ui.button(view.elementsPtr(), ui.View.makeId("dir-pdf"), .{ .label = "PDF", .action = .{ .command = .dir_pdf }, .primary = model.isDirPdf(), .enabled = !disabled, .height = 28 });
        ui.button(view.elementsPtr(), ui.View.makeId("dir-zip"), .{ .label = "ZIP", .action = .{ .command = .dir_zip }, .primary = model.isDirZip(), .enabled = !disabled, .height = 28 });
      ui.end();
    ui.end();
    ui.end();
    ui.end();
}

fn drawProgress(view: *View, model: *const state_mod.State, phase: u8, completed: usize, total: usize, scratch: std.mem.Allocator) void {
    const disabled = model.controlsDisabled();
    var panel: clay.Clay_ElementDeclaration = .{};
    panel.layout = ui.layout(ui.fixedAxis(258), ui.fixedAxis(96), clay.CLAY_TOP_TO_BOTTOM, 10, 8);
    panel.backgroundColor = ui.clayColor(ui.colors.raised);
    panel.cornerRadius = .{ .topLeft = 12, .topRight = 12, .bottomLeft = 12, .bottomRight = 12 };
    panel.border.color = ui.clayColor(ui.colors.stroke);
    panel.border.width = .{ .left = 1, .right = 1, .top = 1, .bottom = 1 };
    panel.floating.attachTo = @intCast(clay.CLAY_ATTACH_TO_ELEMENT_WITH_ID);
    panel.floating.parentId = ui.View.makeId("app-root").id;
    panel.floating.attachPoints = .{ .element = @intCast(clay.CLAY_ATTACH_POINT_RIGHT_BOTTOM), .parent = @intCast(clay.CLAY_ATTACH_POINT_RIGHT_BOTTOM) };
    panel.floating.offset = .{ .x = -16, .y = -16 };
    panel.floating.zIndex = 10;

    ui.open("progress-float", panel);
      const progress: ?f32 = if (model.processing and total != 0)
          @as(f32, @floatFromInt(@min(completed, total))) / @as(f32, @floatFromInt(total))
      else if (!model.controlsDisabled() and model.hasOutput()) 1 else null;

      ui.progressBar(model.controlsDisabled(), progress, phase);

      ui.begin("progress-status", ui.growAxis(), ui.fixedAxis(22), clay.CLAY_LEFT_TO_RIGHT, 0, 7);
        const status = if (model.processing)
            std.fmt.allocPrint(scratch, "진행중... {d}/{d}", .{ @min(completed, total), total }) catch "진행중..."
        else if (model.hasError()) model.errorText() else model.status();
        ui.text(status, .{ .size = 11, .color = if (model.hasError()) ui.colors.destructive else ui.colors.muted });
      ui.end();

      ui.begin("process-buttons", ui.growAxis(), ui.fixedAxis(32), clay.CLAY_LEFT_TO_RIGHT, 0, 6);
        ui.button(view.elementsPtr(), ui.View.makeId("process"), .{ .label = if (model.loading) "불러오는 중..." else if (model.processing) status else model.processLabel(scratch), .action = .{ .command = .process }, .enabled = model.canProcess(), .primary = true, .width = ui.growAxis(), .height = 32 });
        if (model.hasOutput()) {
          ui.button(view.elementsPtr(), ui.View.makeId("reveal-output"), .{ .label = "결과 확인", .action = .{ .command = .reveal_output }, .enabled = !disabled, .width = ui.growAxis(), .height = 32 });
        }
      ui.end();
    ui.end();
}

fn iconImage(name: []const u8, icon: Assets.Icon, size: f32) void {
    var declaration: clay.Clay_ElementDeclaration = .{};
    declaration.layout = ui.layout(ui.fixedAxis(size), ui.fixedAxis(size), clay.CLAY_LEFT_TO_RIGHT, 0, 0);
    declaration.image.imageData = Assets.clayImageData(Assets.referenceForIcon(icon));
    ui.open(name, declaration);
    ui.end();
}

fn iconImageIndexed(name: []const u8, index: u32, icon: Assets.Icon, size: f32) void {
    var declaration: clay.Clay_ElementDeclaration = .{};
    declaration.layout = ui.layout(ui.fixedAxis(size), ui.fixedAxis(size), clay.CLAY_LEFT_TO_RIGHT, 0, 0);
    declaration.image.imageData = Assets.clayImageData(Assets.referenceForIcon(icon));
    ui.openId(ui.View.makeIndexedId(name, index), declaration);
    ui.end();
}

fn qualityAtPosition(x: f32, left: f32, width: f32) u8 {
    const fraction = std.math.clamp((x - left) / width, 0, 1);
    return @intFromFloat(@round(fraction * 100));
}

test "slider maps pointer position to quality" {
    try std.testing.expectEqual(@as(u8, 0), qualityAtPosition(50, 100, 200));
    try std.testing.expectEqual(@as(u8, 25), qualityAtPosition(150, 100, 200));
    try std.testing.expectEqual(@as(u8, 100), qualityAtPosition(400, 100, 200));
}

test "file list flattens containers and expands PDF pages" {
    var model = state_mod.State.init();
    model.item_count = 6;
    model.items[0] = .{ .kind = .directory };
    model.items[1] = .{ .kind = .image, .depth = 1 };
    model.items[2] = .{ .kind = .directory, .depth = 1 };
    model.items[3] = .{ .kind = .image, .depth = 2 };
    model.items[4] = .{ .kind = .pdf, .count = 3 };
    model.items[5] = .{ .kind = .zip };
    try std.testing.expectEqual(@as(usize, 5), listRowCount(&model));
    try std.testing.expectEqual(@as(usize, 1), listEntryAt(&model, 0).?.item);
    try std.testing.expectEqual(@as(usize, 3), listEntryAt(&model, 1).?.item);
    try std.testing.expectEqual(@as(usize, 1), listEntryAt(&model, 2).?.page.number);
    try std.testing.expectEqual(@as(usize, 3), listEntryAt(&model, 4).?.page.number);
    try std.testing.expect(listEntryAt(&model, 5) == null);
    model.items[4].count = 1_000;
    try std.testing.expectEqual(@as(usize, 1_002), listRowCount(&model));
    try std.testing.expectEqual(@as(usize, 1_000), listEntryAt(&model, 1_001).?.page.number);
}

test "floating settings and conversion panel use separate screen space" {
    clay.Clay_SetMaxElementCount(768);
    clay.Clay_SetMaxMeasureTextCacheWordCount(2048);
    const allocator = std.testing.allocator;
    const memory = try allocator.alignedAlloc(u8, .@"16", clay.Clay_MinMemorySize());
    defer allocator.free(memory);
    const arena = clay.Clay_CreateArenaWithCapacityAndMemory(memory.len, memory.ptr);
    _ = clay.Clay_Initialize(arena, .{ .width = 1060, .height = 760 }, .{ .errorHandlerFunction = layoutError });
    clay.Clay_SetMeasureTextFunction(measureLayoutText, null);
    var scratch = std.heap.ArenaAllocator.init(allocator);
    defer scratch.deinit();
    var model = state_mod.State.init();
    model.root_count = 1;
    model.item_count = 20;
    for (model.items[0..model.item_count]) |*item| item.* = .{};
    var view: View = .{};
    _ = view.draw(&model, false, 0, 0, 0, 1060, 760, .{ .x = 0, .y = 0 }, false, .{ .x = 0, .y = 0 }, scratch.allocator());
    const sidebar = clay.Clay_GetElementData(ui.View.makeId("sidebar"));
    const progress = clay.Clay_GetElementData(ui.View.makeId("progress-float"));
    const toggle = clay.Clay_GetElementData(ui.View.makeId("settings-toggle"));
    const header = clay.Clay_GetElementData(ui.View.makeId("window-header"));
    const add_files = clay.Clay_GetElementData(ui.View.makeId("add-files"));
    const list = clay.Clay_GetScrollContainerData(ui.View.makeId("file-list"));
    try std.testing.expect(sidebar.found and progress.found and toggle.found and header.found and add_files.found);
    try std.testing.expect(list.found and list.contentDimensions.height >= 20 * 50 + 144);
    try std.testing.expect(sidebar.boundingBox.y >= header.boundingBox.y + header.boundingBox.height);
    try std.testing.expect(sidebar.boundingBox.y + sidebar.boundingBox.height + 16 <= progress.boundingBox.y);
    try std.testing.expect(toggle.boundingBox.y < sidebar.boundingBox.y);
    const hit = view.actionAt(toggle.boundingBox.x + 18, toggle.boundingBox.y + 18) orelse return error.MissingSettingsToggle;
    try std.testing.expect(hit.action == .command and hit.action.command == .toggle_settings);
    _ = scratch.reset(.retain_capacity);
    view.settings_open = false;
    _ = view.draw(&model, false, 0, 0, 0, 1060, 760, .{ .x = 0, .y = 0 }, false, .{ .x = 0, .y = 0 }, scratch.allocator());
    const closed_sidebar = clay.Clay_GetElementData(ui.View.makeId("sidebar"));
    const fixed_progress = clay.Clay_GetElementData(ui.View.makeId("progress-float"));
    try std.testing.expect(!closed_sidebar.found);
    try std.testing.expect(fixed_progress.found);
    try std.testing.expectEqual(progress.boundingBox.x, fixed_progress.boundingBox.x);
    try std.testing.expectEqual(progress.boundingBox.y, fixed_progress.boundingBox.y);
}

fn layoutError(data: clay.Clay_ErrorData) callconv(.c) void {
    if (data.errorText.chars) |chars| std.debug.print("Clay error {d}: {s}\n", .{ data.errorType, chars[0..@intCast(data.errorText.length)] });
}

fn measureLayoutText(text: clay.Clay_StringSlice, config: [*c]clay.Clay_TextElementConfig, _: ?*anyopaque) callconv(.c) clay.Clay_Dimensions {
    return .{ .width = @as(f32, @floatFromInt(text.length)) * 7, .height = @floatFromInt(config.*.fontSize) };
}
