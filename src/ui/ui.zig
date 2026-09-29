const std = @import("std");
const api = @import("clay");
const Assets = @import("assets.zig");

pub const Command = union(enum) { choose_files, choose_output, reveal_output, process, toggle_settings, mode_path, mode_overwrite, dir_none, dir_pdf, dir_zip, toggle_ai, next_upscaler, remove_file: u16, select_item: u16 };

pub const Input = enum { width, suffix };

pub const Action = union(enum) {
    command: Command,
    focus_input: Input,
    slider,
};

pub const HitTarget = struct {
    id: api.Clay_ElementId,
    action: Action,
};

pub const View = struct {
    const max_hit_targets = 256;

    hit_targets: [max_hit_targets]HitTarget = undefined,
    hit_count: usize = 0,

    pub fn reset(self: *View) void {
        self.hit_count = 0;
    }

    pub fn makeId(name: []const u8) api.Clay_ElementId {
        return api.Clay_GetElementId(.{
            .isStaticallyAllocated = true,
            .length = @intCast(name.len),
            .chars = @ptrCast(name.ptr),
        });
    }

    pub fn makeIndexedId(name: []const u8, index: u32) api.Clay_ElementId {
        return api.Clay_GetElementIdWithIndex(.{
            .isStaticallyAllocated = true,
            .length = @intCast(name.len),
            .chars = @ptrCast(name.ptr),
        }, index);
    }

    pub fn hitAt(self: *const View, x: f32, y: f32) ?Action {
        for (self.hit_targets[0..self.hit_count]) |target| {
            const data = api.Clay_GetElementData(target.id);
            if (!data.found) continue;
            const box = data.boundingBox;
            if (x >= box.x and x <= box.x + box.width and y >= box.y and y <= box.y + box.height) return target.action;
        }
        return null;
    }

    pub fn boundsFor(self: *const View, target_id: api.Clay_ElementId) ?api.Clay_BoundingBox {
        _ = self;
        const data = api.Clay_GetElementData(target_id);
        return if (data.found) data.boundingBox else null;
    }

    pub fn addHit(self: *View, id: api.Clay_ElementId, action: Action) void {
        if (self.hit_count == self.hit_targets.len) return;
        self.hit_targets[self.hit_count] = .{ .id = id, .action = action };
        self.hit_count += 1;
    }
};

pub const Color = struct { r: f32, g: f32, b: f32, a: f32 = 255 };

pub const colors = struct {
    pub const background = Color{ .r = 23, .g = 23, .b = 23 };
    pub const surface = Color{ .r = 26, .g = 26, .b = 26 };
    pub const raised = Color{ .r = 33, .g = 33, .b = 33 };
    pub const hover = Color{ .r = 60, .g = 56, .b = 52 };
    pub const stroke = Color{ .r = 51, .g = 51, .b = 51 };
    pub const accent = Color{ .r = 45, .g = 91, .b = 184 };
    pub const accent_hover = Color{ .r = 27, .g = 39, .b = 55 };
    pub const accent_muted = Color{ .r = 46, .g = 69, .b = 116 };
    pub const text = Color{ .r = 240, .g = 240, .b = 240 };
    pub const muted = Color{ .r = 175, .g = 175, .b = 175 };
    pub const destructive = Color{ .r = 240, .g = 240, .b = 240 };
};

pub fn clayColor(color: Color) api.Clay_Color {
    return .{ .r = color.r, .g = color.g, .b = color.b, .a = color.a };
}

pub fn growAxis() api.Clay_SizingAxis {
    return .{ .size = .{ .minMax = .{ .min = 0, .max = 0 } }, .type = api.CLAY__SIZING_TYPE_GROW };
}

pub fn fitAxis() api.Clay_SizingAxis {
    return .{ .size = .{ .minMax = .{ .min = 0, .max = 0 } }, .type = api.CLAY__SIZING_TYPE_FIT };
}

pub fn fixedAxis(value: f32) api.Clay_SizingAxis {
    return .{ .size = .{ .minMax = .{ .min = value, .max = value } }, .type = api.CLAY__SIZING_TYPE_FIXED };
}

pub fn percentAxis(value: f32) api.Clay_SizingAxis {
    return .{ .size = .{ .percent = value }, .type = api.CLAY__SIZING_TYPE_PERCENT };
}

pub fn layout(width: api.Clay_SizingAxis, height: api.Clay_SizingAxis, direction: u8, padding: u16, gap: u16) api.Clay_LayoutConfig {
    return .{
        .sizing = .{ .width = width, .height = height },
        .padding = .{ .left = padding, .right = padding, .top = padding, .bottom = padding },
        .childGap = gap,
        .childAlignment = .{},
        .layoutDirection = direction,
    };
}

const TextConfig = struct {
    size: u16,
    color: Color = colors.text,
    font: Assets.Font = .regular,
    wrapMode: u8 = api.CLAY_TEXT_WRAP_WORDS,
    lineHeight: u16 = 5,
};

pub fn text(value: []const u8, conf: TextConfig) void {
    api.Clay__OpenTextElement(.{
        .isStaticallyAllocated = false,
        .length = @intCast(value.len),
        .chars = @ptrCast(value.ptr),
    }, .{
        .userData = null,
        .textColor = clayColor(conf.color),
        .fontId = @intFromEnum(conf.font),
        .fontSize = conf.size,
        .letterSpacing = 0,
        .lineHeight = conf.size + conf.lineHeight,
        .wrapMode = conf.wrapMode,
        .textAlignment = api.CLAY_TEXT_ALIGN_LEFT,
    });
}

pub fn panel(name: []const u8, width: api.Clay_SizingAxis, height: api.Clay_SizingAxis, padding: u16, gap: u16, fill: Color) void {
    var declaration: api.Clay_ElementDeclaration = .{};
    declaration.layout = layout(width, height, api.CLAY_TOP_TO_BOTTOM, padding, gap);
    declaration.backgroundColor = clayColor(fill);
    declaration.cornerRadius = .{ .topLeft = 12, .topRight = 12, .bottomLeft = 12, .bottomRight = 12 };
    declaration.border.color = clayColor(colors.stroke);
    declaration.border.width = .{ .left = 1, .right = 1, .top = 1, .bottom = 1 };
    open(name, declaration);
}

pub fn panelId(id: api.Clay_ElementId, width: api.Clay_SizingAxis, height: api.Clay_SizingAxis, padding: u16, gap: u16, fill: Color) void {
    var declaration: api.Clay_ElementDeclaration = .{};
    declaration.layout = layout(width, height, api.CLAY_TOP_TO_BOTTOM, padding, gap);
    declaration.backgroundColor = clayColor(fill);
    declaration.cornerRadius = .{ .topLeft = 12, .topRight = 12, .bottomLeft = 12, .bottomRight = 12 };
    declaration.border.color = clayColor(colors.stroke);
    declaration.border.width = .{ .left = 1, .right = 1, .top = 1, .bottom = 1 };
    openId(id, declaration);
}

pub fn begin(name: []const u8, width: api.Clay_SizingAxis, height: api.Clay_SizingAxis, direction: u8, padding: u16, gap: u16) void {
    var declaration: api.Clay_ElementDeclaration = .{};
    declaration.layout = layout(width, height, direction, padding, gap);
    open(name, declaration);
}

pub fn beginId(id: api.Clay_ElementId, width: api.Clay_SizingAxis, height: api.Clay_SizingAxis, direction: u8, padding: u16, gap: u16) void {
    var declaration: api.Clay_ElementDeclaration = .{};
    declaration.layout = layout(width, height, direction, padding, gap);
    openId(id, declaration);
}

pub fn end() void {
    api.Clay__CloseElement();
}

pub fn separator(name: []const u8) void {
    var declaration: api.Clay_ElementDeclaration = .{};
    declaration.layout = layout(growAxis(), fixedAxis(1), api.CLAY_LEFT_TO_RIGHT, 0, 0);
    declaration.backgroundColor = clayColor(colors.stroke);

    selfClose(name, declaration);
}

pub fn icon(name: Assets.Icon, size: f32) void {
    var declaration: api.Clay_ElementDeclaration = .{};
    declaration.layout = layout(fixedAxis(size), fixedAxis(size), api.CLAY_LEFT_TO_RIGHT, 0, 0);
    declaration.image.imageData = Assets.clayImageData(Assets.referenceForIcon(name));
    selfClose(@tagName(name), declaration);
}

const ButtonConfig = struct {
  label: ?[]const u8 = null,
  icon: ?Assets.Icon = null,
  enabled: bool = true,
  primary: bool = false,
  action: Action,
  width: api.Clay_SizingAxis = growAxis(),
  height: f32,
};

pub fn button(view: *View, id: api.Clay_ElementId, conf: ButtonConfig) void {
    api.Clay__OpenElementWithId(id);
    const hovered = api.Clay_Hovered();

    var declaration: api.Clay_ElementDeclaration = .{};
    declaration.layout = layout(conf.width, fixedAxis(conf.height), api.CLAY_LEFT_TO_RIGHT, 10, 4);
    declaration.layout.childAlignment = .{ .x = api.CLAY_ALIGN_X_CENTER, .y = api.CLAY_ALIGN_Y_CENTER };
    if (conf.primary) {
      declaration.backgroundColor = clayColor(if (!conf.enabled) colors.accent_muted else if (hovered) colors.accent_hover else colors.accent);
    } else {
      declaration.backgroundColor = clayColor(if (!conf.enabled) colors.hover else if (hovered) colors.hover else colors.surface);
    }
    declaration.cornerRadius = .{ .topLeft = 8, .topRight = 8, .bottomLeft = 8, .bottomRight = 8 };

    api.Clay__ConfigureOpenElement(declaration);
      if (conf.icon) |icn| {
        icon(icn, if (conf.label != null) 12 else 16);
      }
      if (conf.label) |label| {
        text(label, .{ .size = if (conf.icon != null) 12 else 13, .color = if (conf.enabled) colors.text else colors.muted, .font = .medium });
      }
    end();

    if (conf.enabled) view.addHit(id, conf.action);
}

pub fn checkbox(view: *View, name: []const u8, action: Action, selected: bool, enabled: bool) void {
    const id = View.makeId(name);
    api.Clay__OpenElementWithId(id);
    const hovered = api.Clay_Hovered();

    var declaration: api.Clay_ElementDeclaration = .{};
    declaration.layout = layout(fixedAxis(18), fixedAxis(18), api.CLAY_LEFT_TO_RIGHT, 0, 0);
    declaration.layout.childAlignment = .{ .x = api.CLAY_ALIGN_X_CENTER, .y = api.CLAY_ALIGN_Y_CENTER };
    declaration.backgroundColor = clayColor(if (selected) colors.accent else if (hovered and enabled) colors.hover else colors.surface);
    declaration.cornerRadius = .{ .topLeft = 4, .topRight = 4, .bottomLeft = 4, .bottomRight = 4 };
    declaration.border.color = clayColor(if (selected) colors.accent else colors.stroke);
    declaration.border.width = .{ .left = 1, .right = 1, .top = 1, .bottom = 1 };

    api.Clay__ConfigureOpenElement(declaration);
      if (selected) text("✓", .{ .size = 11, .color = colors.text, .font = .medium });
    end();
    if (enabled) view.addHit(id, action);
}

pub fn textField(view: *View, name: []const u8, label: []const u8, value: []const u8, placeholder: []const u8, action: Input, focused: bool, enabled: bool) void {
    text(label, .{ .size = 12, .color = colors.muted });

    const id = View.makeId(name);
    api.Clay__OpenElementWithId(id);
    const hovered = api.Clay_Hovered();

    var declaration: api.Clay_ElementDeclaration = .{};
    declaration.layout = layout(growAxis(), fixedAxis(38), api.CLAY_LEFT_TO_RIGHT, 10, 0);
    declaration.layout.childAlignment.y = api.CLAY_ALIGN_Y_CENTER;
    declaration.backgroundColor = clayColor(if (focused) colors.raised else if (hovered and enabled) colors.hover else colors.surface);
    declaration.cornerRadius = .{ .topLeft = 7, .topRight = 7, .bottomLeft = 7, .bottomRight = 7 };
    declaration.border.color = clayColor(if (focused) colors.accent else colors.stroke);
    declaration.border.width = .{ .left = 1, .right = 1, .top = 1, .bottom = 1 };

    api.Clay__ConfigureOpenElement(declaration);
      text(if (value.len == 0) placeholder else value, .{ .size = 13, .color = if (enabled and value.len != 0) colors.text else colors.muted });
    end();
    if (enabled) view.addHit(id, .{ .focus_input = action });
}

pub fn slider(view: *View, name: []const u8, value: f32, enabled: bool) api.Clay_ElementId {
    const id = View.makeId(name);

    var declaration: api.Clay_ElementDeclaration = .{};
    declaration.layout = layout(growAxis(), fixedAxis(30), api.CLAY_TOP_TO_BOTTOM, 0, 0);
    declaration.layout.padding.top = 10;
    declaration.layout.padding.bottom = 10;

    openId(id, declaration);
      api.Clay__OpenElement();
      var track: api.Clay_ElementDeclaration = .{};
      track.layout = layout(growAxis(), fixedAxis(10), api.CLAY_LEFT_TO_RIGHT, 0, 0);
      track.backgroundColor = clayColor(colors.raised);
      track.cornerRadius = .{ .topLeft = 5, .topRight = 5, .bottomLeft = 5, .bottomRight = 5 };
      api.Clay__ConfigureOpenElement(track);

        api.Clay__OpenElement();
        var fill: api.Clay_ElementDeclaration = .{};
        fill.layout = layout(percentAxis(std.math.clamp(value, 0, 1)), growAxis(), api.CLAY_LEFT_TO_RIGHT, 0, 0);
        fill.backgroundColor = clayColor(if (enabled) colors.accent else colors.muted);
        fill.cornerRadius = .{ .topLeft = 5, .topRight = 5, .bottomLeft = 5, .bottomRight = 5 };
        api.Clay__ConfigureOpenElement(fill);
        end();
      end();
    end();

    if (enabled) view.addHit(id, .slider);
    return id;
}

pub fn spinner(phase: u8, slot: u32) void {
    beginId(View.makeIndexedId("spinner", slot), fixedAxis(20), fixedAxis(20), api.CLAY_TOP_TO_BOTTOM, 0, 4);
    for (0..2) |row| {
        beginId(View.makeIndexedId("spinner-row", slot * 2 + @as(u32, @intCast(row))), fixedAxis(20), fixedAxis(8), api.CLAY_LEFT_TO_RIGHT, 0, 4);
        for (0..2) |column| {
            const position: u8 = @intCast(row * 2 + column);
            const index: u8 = if (position == 2) 3 else if (position == 3) 2 else position;
            var dot: api.Clay_ElementDeclaration = .{};
            dot.layout = layout(fixedAxis(8), fixedAxis(8), api.CLAY_LEFT_TO_RIGHT, 0, 0);
            dot.backgroundColor = clayColor(if (phase % 4 == index) colors.text else colors.stroke);
            dot.cornerRadius = .{ .topLeft = 4, .topRight = 4, .bottomLeft = 4, .bottomRight = 4 };
            openId(View.makeIndexedId("spinner-dot", slot * 4 + position), dot);
            end();
        }
        end();
    }
    end();
}

pub fn progressBar(active: bool, value: ?f32, phase: u8) void {
    var track: api.Clay_ElementDeclaration = .{};
    track.layout = layout(growAxis(), fixedAxis(5), api.CLAY_LEFT_TO_RIGHT, 0, 0);
    track.backgroundColor = clayColor(colors.raised);
    track.cornerRadius = .{ .topLeft = 3, .topRight = 3, .bottomLeft = 3, .bottomRight = 3 };

    open("progress-track", track);
    if (active or value != null) {
        if (value == null) {
            begin("progress-leading", percentAxis(@as(f32, @floatFromInt(phase % 4)) * 0.2), growAxis(), api.CLAY_LEFT_TO_RIGHT, 0, 0);
            end();
        }
        var fill: api.Clay_ElementDeclaration = .{};
        fill.layout = layout(percentAxis(if (value) |fraction| std.math.clamp(fraction, 0, 1) else 0.2), growAxis(), api.CLAY_LEFT_TO_RIGHT, 0, 0);
        fill.backgroundColor = clayColor(colors.accent);
        fill.cornerRadius = .{ .topLeft = 3, .topRight = 3, .bottomLeft = 3, .bottomRight = 3 };
        open("progress-fill", fill);
        end();
    }
    end();
}

pub fn scrollContainer(name: []const u8, width: api.Clay_SizingAxis, height: api.Clay_SizingAxis, padding: u16, gap: u16, background: Color) void {
    var declaration: api.Clay_ElementDeclaration = .{};
    declaration.layout = layout(width, height, api.CLAY_TOP_TO_BOTTOM, padding, gap);
    declaration.clip.vertical = true;
    declaration.backgroundColor = clayColor(background);
    declaration.cornerRadius = .{ .topLeft = 8, .topRight = 8, .bottomLeft = 8, .bottomRight = 8 };

    api.Clay__OpenElementWithId(View.makeId(name));
    declaration.clip.childOffset = api.Clay_GetScrollOffset();
    api.Clay__ConfigureOpenElement(declaration);
}

pub fn open(name: []const u8, declaration: api.Clay_ElementDeclaration) void {
    openId(View.makeId(name), declaration);
}

pub fn openId(id: api.Clay_ElementId, declaration: api.Clay_ElementDeclaration) void {
    api.Clay__OpenElementWithId(id);
    api.Clay__ConfigureOpenElement(declaration);
}

pub fn selfClose(name: []const u8, declaration: api.Clay_ElementDeclaration) void {
    open(name, declaration);
    end();
}
