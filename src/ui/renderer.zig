const std = @import("std");
const builtin = @import("builtin");
const sdl = @import("sdl");
const stb = @import("stb");
const clay = @import("clay");
const Assets = @import("assets.zig");

const Renderer = @This();
const font_size_count = 128;
const max_scissor_depth = 128;
const max_system_fonts = 512;
const icon_stroke_batch_capacity = 128;
const icon_stroke_cap_segments = 12;
const icon_stroke_vertices_per_segment = 4 + 2 * (icon_stroke_cap_segments + 1);
const icon_stroke_indices_per_segment = 6 + 2 * icon_stroke_cap_segments * 3;

const SystemFont = struct {
    path: [:0]u8,
    fonts: [font_size_count]?*sdl.TTF_Font = [_]?*sdl.TTF_Font{null} ** font_size_count,
    attempted: [font_size_count]bool = [_]bool{false} ** font_size_count,
};

window: *sdl.SDL_Window,
handle: *sdl.SDL_Renderer,
clay_memory: []align(16) u8,
assets: Assets.Catalog,
fonts: [2][font_size_count]?*sdl.TTF_Font = [_][font_size_count]?*sdl.TTF_Font{[_]?*sdl.TTF_Font{null} ** font_size_count} ** 2,
system_fonts: std.ArrayList(SystemFont) = .empty,
preview: ?*sdl.SDL_Texture = null,
scale_x: f32 = 1,
scale_y: f32 = 1,
scissor_stack: [max_scissor_depth]sdl.SDL_Rect = undefined,
scissor_depth: usize = 0,

pub fn init(allocator: std.mem.Allocator, io: std.Io, home: []const u8, window: *sdl.SDL_Window) !Renderer {
    if (!sdl.TTF_Init()) return error.TextInitializationFailed;
    errdefer sdl.TTF_Quit();

    const handle = sdl.SDL_CreateRenderer(window, null) orelse return error.RendererCreationFailed;
    errdefer sdl.SDL_DestroyRenderer(handle);
    _ = sdl.SDL_SetRenderDrawBlendMode(handle, sdl.SDL_BLENDMODE_BLEND);

    var assets = try Assets.Catalog.init(allocator);
    errdefer assets.deinit();
    var system_fonts = discoverSystemFonts(allocator, io, home);
    errdefer deinitSystemFonts(allocator, &system_fonts);
    const memory_size: usize = clay.Clay_MinMemorySize();
    const memory = try allocator.alignedAlloc(u8, .@"16", memory_size);
    errdefer allocator.free(memory);

    const self: Renderer = .{
        .window = window,
        .handle = handle,
        .clay_memory = memory,
        .assets = assets,
        .system_fonts = system_fonts,
    };
    const dimensions = windowSize(window);
    const arena = clay.Clay_CreateArenaWithCapacityAndMemory(memory.len, memory.ptr);
    _ = clay.Clay_Initialize(arena, .{ .width = @floatCast(dimensions.width), .height = @floatCast(dimensions.height) }, .{
        .errorHandlerFunction = clayError,
        .userData = null,
    });
    return self;
}

pub fn bind(self: *Renderer) void {
    clay.Clay_SetMeasureTextFunction(measureText, self);
}

pub fn deinit(self: *Renderer, allocator: std.mem.Allocator) void {
    if (self.preview) |texture| sdl.SDL_DestroyTexture(texture);
    for (&self.fonts) |*family| for (family) |*font| {
        if (font.*) |value| sdl.TTF_CloseFont(value);
    };
    deinitSystemFonts(allocator, &self.system_fonts);
    self.assets.deinit();
    sdl.SDL_DestroyRenderer(self.handle);
    sdl.TTF_Quit();
    allocator.free(self.clay_memory);
}

pub fn windowSize(window: *sdl.SDL_Window) struct { width: f64, height: f64 } {
    var width: c_int = 0;
    var height: c_int = 0;
    _ = sdl.SDL_GetWindowSize(window, &width, &height);
    return .{ .width = @floatFromInt(width), .height = @floatFromInt(height) };
}

pub fn hasPreview(self: *const Renderer) bool {
    return self.preview != null;
}

pub fn setPreviewThumbnail(self: *Renderer, allocator: std.mem.Allocator, thumbnail: ?Assets.BinaryThumbnail) !void {
    if (self.preview) |texture| sdl.SDL_DestroyTexture(texture);
    self.preview = null;
    const image = thumbnail orelse return;
    defer allocator.free(image.bytes);

    var width: c_int = 0;
    var height: c_int = 0;
    var channels: c_int = 0;
    const pixels = stb.stbi_load_from_memory(image.bytes.ptr, @intCast(image.bytes.len), &width, &height, &channels, 4) orelse return error.ThumbnailDecodeFailed;
    defer stb.stbi_image_free(pixels);
    if (width <= 0 or height <= 0) return error.ThumbnailDecodeFailed;

    const texture = sdl.SDL_CreateTexture(self.handle, sdl.SDL_PIXELFORMAT_RGBA32, sdl.SDL_TEXTUREACCESS_STATIC, width, height) orelse return error.ThumbnailTextureFailed;
    errdefer sdl.SDL_DestroyTexture(texture);
    if (!sdl.SDL_UpdateTexture(texture, null, pixels, width * 4)) return error.ThumbnailTextureFailed;
    self.preview = texture;
}

pub fn render(self: *Renderer, commands: clay.Clay_RenderCommandArray, width: f64, height: f64) void {
    self.updateOutputScale(width, height);
    _ = sdl.SDL_SetRenderDrawColor(self.handle, 10, 10, 10, 255);
    _ = sdl.SDL_RenderClear(self.handle);
    self.scissor_depth = 0;

    if (commands.internalArray) |items| {
        for (items[0..@intCast(commands.length)]) |command| self.drawCommand(command);
    }
    while (self.scissor_depth != 0) self.endScissor();
    _ = sdl.SDL_RenderPresent(self.handle);
}

pub fn updateOutputScale(self: *Renderer, width: f64, height: f64) void {
    var pixel_width: c_int = 0;
    var pixel_height: c_int = 0;
    if (!sdl.SDL_GetRenderOutputSize(self.handle, &pixel_width, &pixel_height)) return;
    self.scale_x = if (width > 0) @as(f32, @floatCast(@as(f64, @floatFromInt(pixel_width)) / width)) else 1;
    self.scale_y = if (height > 0) @as(f32, @floatCast(@as(f64, @floatFromInt(pixel_height)) / height)) else 1;
    _ = sdl.SDL_SetRenderScale(self.handle, self.scale_x, self.scale_y);
}

pub fn showOpenFileDialog(window: *sdl.SDL_Window, default_path: []const u8, allow_many: bool, callback: sdl.SDL_DialogFileCallback, user_data: ?*anyopaque) !void {
    const path = if (default_path.len == 0) null else try std.heap.page_allocator.dupeZ(u8, default_path);
    defer if (path) |value| std.heap.page_allocator.free(value);
    sdl.SDL_ShowOpenFileDialog(callback, user_data, window, null, 0, if (path) |value| value.ptr else null, allow_many);
}

pub fn showOpenFolderDialog(window: *sdl.SDL_Window, default_path: []const u8, callback: sdl.SDL_DialogFileCallback, user_data: ?*anyopaque) !void {
    const path = if (default_path.len == 0) null else try std.heap.page_allocator.dupeZ(u8, default_path);
    defer if (path) |value| std.heap.page_allocator.free(value);
    sdl.SDL_ShowOpenFolderDialog(callback, user_data, window, if (path) |value| value.ptr else null, false);
}

pub fn revealPath(path: []const u8) bool {
    var uri = std.ArrayList(u8).empty;
    defer uri.deinit(std.heap.page_allocator);
    uri.appendSlice(std.heap.page_allocator, "file://") catch return false;
    for (path) |byte| {
        if (std.ascii.isAlphanumeric(byte) or std.mem.indexOfScalar(u8, "/-._~:", byte) != null) {
            uri.append(std.heap.page_allocator, byte) catch return false;
        } else {
            const hex = "0123456789ABCDEF";
            uri.appendSlice(std.heap.page_allocator, &.{ '%', hex[byte >> 4], hex[byte & 0x0f] }) catch return false;
        }
    }
    uri.append(std.heap.page_allocator, 0) catch return false;
    return sdl.SDL_OpenURL(@ptrCast(uri.items.ptr));
}

fn drawCommand(self: *Renderer, command: clay.Clay_RenderCommand) void {
    const box = command.boundingBox;
    const rect = sdl.SDL_FRect{ .x = box.x, .y = box.y, .w = box.width, .h = box.height };
    switch (command.commandType) {
        clay.CLAY_RENDER_COMMAND_TYPE_RECTANGLE => {
            const color = command.renderData.rectangle.backgroundColor;
            const radius = maxCornerRadius(command.renderData.rectangle.cornerRadius);
            setColor(self, color.r, color.g, color.b, color.a);
            if (radius > 0) {
                self.fillRoundedRect(rect, radius, color);
            } else {
                _ = sdl.SDL_RenderFillRect(self.handle, &rect);
            }
        },
        clay.CLAY_RENDER_COMMAND_TYPE_BORDER => self.drawBorder(rect, command.renderData.border),
        clay.CLAY_RENDER_COMMAND_TYPE_TEXT => self.drawText(box, command.renderData.text),
        clay.CLAY_RENDER_COMMAND_TYPE_IMAGE => self.drawImage(rect, Assets.imageReferenceFromClay(command.renderData.image.imageData)),
        clay.CLAY_RENDER_COMMAND_TYPE_SCISSOR_START => self.beginScissor(rect),
        clay.CLAY_RENDER_COMMAND_TYPE_SCISSOR_END => self.endScissor(),
        else => {},
    }
}

fn drawBorder(self: *Renderer, rect: sdl.SDL_FRect, data: clay.Clay_BorderRenderData) void {
    const widths = data.width;
    if (widths.top == 0 and widths.right == 0 and widths.bottom == 0 and widths.left == 0) return;

    const left: f32 = @floatFromInt(widths.left);
    const top: f32 = @floatFromInt(widths.top);
    const right: f32 = @floatFromInt(widths.right);
    const bottom: f32 = @floatFromInt(widths.bottom);
    const inset = sdl.SDL_FRect{ .x = rect.x + left, .y = rect.y + top, .w = rect.w - left - right, .h = rect.h - top - bottom };
    const color = sdl.SDL_FColor{ .r = data.color.r / 255, .g = data.color.g / 255, .b = data.color.b / 255, .a = data.color.a / 255 };
    if (inset.w <= 0 or inset.h <= 0) {
        setColor(self, data.color.r, data.color.g, data.color.b, data.color.a);
        self.fillRoundedRect(rect, maxCornerRadius(data.cornerRadius), data.color);
        return;
    }

    const outer_points = roundedRectPoints(rect, outlineRadii(rect, data.cornerRadius, .{}));
    const inner_points = roundedRectPoints(inset, outlineRadii(inset, data.cornerRadius, .{
        .top_left_x = left,
        .top_left_y = top,
        .top_right_x = right,
        .top_right_y = top,
        .bottom_right_x = right,
        .bottom_right_y = bottom,
        .bottom_left_x = left,
        .bottom_left_y = bottom,
    }));
    const point_count = outer_points.len;
    var vertices: [point_count * 4]sdl.SDL_Vertex = undefined;
    var indices: [point_count * 6]c_int = undefined;
    for (0..point_count) |index| {
        const next = (index + 1) % point_count;
        const base = index * 4;
        vertices[base] = .{ .position = outer_points[index], .color = color, .tex_coord = .{} };
        vertices[base + 1] = .{ .position = inner_points[index], .color = color, .tex_coord = .{} };
        vertices[base + 2] = .{ .position = inner_points[next], .color = color, .tex_coord = .{} };
        vertices[base + 3] = .{ .position = outer_points[next], .color = color, .tex_coord = .{} };
        indices[index * 6 ..][0..6].* = .{ @intCast(base), @intCast(base + 1), @intCast(base + 2), @intCast(base), @intCast(base + 2), @intCast(base + 3) };
    }
    _ = sdl.SDL_RenderGeometry(self.handle, null, &vertices, @intCast(vertices.len), &indices, @intCast(indices.len));
}

const OutlineInset = struct {
    top_left_x: f32 = 0,
    top_left_y: f32 = 0,
    top_right_x: f32 = 0,
    top_right_y: f32 = 0,
    bottom_right_x: f32 = 0,
    bottom_right_y: f32 = 0,
    bottom_left_x: f32 = 0,
    bottom_left_y: f32 = 0,
};

const OutlineRadii = struct {
    top_left_x: f32,
    top_left_y: f32,
    top_right_x: f32,
    top_right_y: f32,
    bottom_right_x: f32,
    bottom_right_y: f32,
    bottom_left_x: f32,
    bottom_left_y: f32,
};

fn outlineRadii(rect: sdl.SDL_FRect, radius: clay.Clay_CornerRadius, inset: OutlineInset) OutlineRadii {
    return .{
        .top_left_x = @min(@max(0, radius.topLeft - inset.top_left_x), rect.w / 2),
        .top_left_y = @min(@max(0, radius.topLeft - inset.top_left_y), rect.h / 2),
        .top_right_x = @min(@max(0, radius.topRight - inset.top_right_x), rect.w / 2),
        .top_right_y = @min(@max(0, radius.topRight - inset.top_right_y), rect.h / 2),
        .bottom_right_x = @min(@max(0, radius.bottomRight - inset.bottom_right_x), rect.w / 2),
        .bottom_right_y = @min(@max(0, radius.bottomRight - inset.bottom_right_y), rect.h / 2),
        .bottom_left_x = @min(@max(0, radius.bottomLeft - inset.bottom_left_x), rect.w / 2),
        .bottom_left_y = @min(@max(0, radius.bottomLeft - inset.bottom_left_y), rect.h / 2),
    };
}

fn roundedRectPoints(rect: sdl.SDL_FRect, radius: OutlineRadii) [36]sdl.SDL_FPoint {
    const segments_per_corner = 8;
    const quarter_turn: f32 = @as(f32, std.math.pi) / 2;
    const starts = [_]f32{ @as(f32, std.math.pi), -quarter_turn, 0, quarter_turn };
    const centers = [_]sdl.SDL_FPoint{
        .{ .x = rect.x + radius.top_left_x, .y = rect.y + radius.top_left_y },
        .{ .x = rect.x + rect.w - radius.top_right_x, .y = rect.y + radius.top_right_y },
        .{ .x = rect.x + rect.w - radius.bottom_right_x, .y = rect.y + rect.h - radius.bottom_right_y },
        .{ .x = rect.x + radius.bottom_left_x, .y = rect.y + rect.h - radius.bottom_left_y },
    };
    const radii = [_]sdl.SDL_FPoint{
        .{ .x = radius.top_left_x, .y = radius.top_left_y },
        .{ .x = radius.top_right_x, .y = radius.top_right_y },
        .{ .x = radius.bottom_right_x, .y = radius.bottom_right_y },
        .{ .x = radius.bottom_left_x, .y = radius.bottom_left_y },
    };
    var points: [36]sdl.SDL_FPoint = undefined;
    var index: usize = 0;
    for (0..4) |corner| {
        for (0..segments_per_corner + 1) |step| {
            const angle = starts[corner] + quarter_turn * @as(f32, @floatFromInt(step)) / @as(f32, @floatFromInt(segments_per_corner));
            points[index] = .{ .x = centers[corner].x + radii[corner].x * @cos(angle), .y = centers[corner].y + radii[corner].y * @sin(angle) };
            index += 1;
        }
    }
    return points;
}

fn drawText(self: *Renderer, box: clay.Clay_BoundingBox, data: clay.Clay_TextRenderData) void {
    const bytes = if (data.stringContents.chars) |chars| chars[0..@intCast(data.stringContents.length)] else return;
    const family: Assets.Font = if (data.fontId == @intFromEnum(Assets.Font.medium)) .medium else .regular;
    const font = self.fontFor(family, data.fontSize) orelse return;
    self.ensureGlyphCoverage(font, data.fontSize, bytes);
    var width: c_int = 0;
    var height: c_int = 0;
    if (!sdl.TTF_GetStringSize(font, bytes.ptr, bytes.len, &width, &height)) return;
    const color = sdl.SDL_Color{ .r = @intFromFloat(data.textColor.r), .g = @intFromFloat(data.textColor.g), .b = @intFromFloat(data.textColor.b), .a = @intFromFloat(data.textColor.a) };
    const surface = sdl.TTF_RenderText_Blended(font, bytes.ptr, bytes.len, color) orelse return;
    defer sdl.SDL_DestroySurface(surface);
    const texture = sdl.SDL_CreateTextureFromSurface(self.handle, surface) orelse return;
    defer sdl.SDL_DestroyTexture(texture);

    const dest = sdl.SDL_FRect{
        .x = box.x,
        .y = box.y + @max(0, (box.height - @as(f32, @floatFromInt(height)) / @max(self.scale_y, 0.01)) / 2),
        .w = @as(f32, @floatFromInt(width)) / @max(self.scale_x, 0.01),
        .h = @as(f32, @floatFromInt(height)) / @max(self.scale_y, 0.01),
    };
    _ = sdl.SDL_RenderTexture(self.handle, texture, null, &dest);
}

fn drawImage(self: *Renderer, rect: sdl.SDL_FRect, reference: ?Assets.ImageReference) void {
    switch (reference orelse return) {
        .preview => if (self.preview) |texture| {
            var image_width: f32 = 0;
            var image_height: f32 = 0;
            if (!sdl.SDL_GetTextureSize(texture, &image_width, &image_height) or image_width <= 0 or image_height <= 0) return;
            const scale = @min(rect.w / image_width, rect.h / image_height);
            const draw_rect = sdl.SDL_FRect{ .x = rect.x + (rect.w - image_width * scale) / 2, .y = rect.y + (rect.h - image_height * scale) / 2, .w = image_width * scale, .h = image_height * scale };
            _ = sdl.SDL_RenderTexture(self.handle, texture, null, &draw_rect);
        },
        .folder => self.drawIcon(.folder, rect),
        .file_text => self.drawIcon(.file_text, rect),
        .plus => self.drawIcon(.plus, rect),
        .x => self.drawIcon(.x, rect),
        .settings => self.drawIcon(.settings, rect),
        .sidebar_close => self.drawIcon(.sidebar_close, rect),
    }
}

fn drawIcon(self: *Renderer, icon: Assets.Icon, rect: sdl.SDL_FRect) void {
    const data = self.assets.icon(icon);
    const fit = @min(rect.w / data.width, rect.h / data.height);
    if (fit <= 0) return;
    const offset_x = rect.x + (rect.w - data.width * fit) / 2;
    const offset_y = rect.y + (rect.h - data.height * fit) / 2;
    const line_width = @max(1, data.stroke_width * fit);
    const color = sdl.SDL_FColor{
        .r = @as(f32, @floatFromInt(data.color.r)) / 255,
        .g = @as(f32, @floatFromInt(data.color.g)) / 255,
        .b = @as(f32, @floatFromInt(data.color.b)) / 255,
        .a = @as(f32, @floatFromInt(data.color.a)) / 255,
    };
    var vertices: [icon_stroke_batch_capacity * icon_stroke_vertices_per_segment]sdl.SDL_Vertex = undefined;
    var indices: [icon_stroke_batch_capacity * icon_stroke_indices_per_segment]c_int = undefined;
    var segment_index: usize = 0;
    while (segment_index < data.segments.len) {
        var vertex_count: usize = 0;
        var index_count: usize = 0;
        const batch_end = @min(segment_index + icon_stroke_batch_capacity, data.segments.len);
        while (segment_index < batch_end) : (segment_index += 1) {
            const segment = data.segments[segment_index];
            const start = sdl.SDL_FPoint{ .x = offset_x + segment.start.x * fit, .y = offset_y + segment.start.y * fit };
            const end = sdl.SDL_FPoint{ .x = offset_x + segment.end.x * fit, .y = offset_y + segment.end.y * fit };
            const dx = end.x - start.x;
            const dy = end.y - start.y;
            const length = @sqrt(dx * dx + dy * dy);
            if (length == 0) continue;
            const normal_x = -dy / length * line_width / 2;
            const normal_y = dx / length * line_width / 2;
            appendStrokeQuad(&vertices, &indices, &vertex_count, &index_count, start, end, normal_x, normal_y, color);
            appendStrokeCap(&vertices, &indices, &vertex_count, &index_count, start, line_width / 2, color);
            appendStrokeCap(&vertices, &indices, &vertex_count, &index_count, end, line_width / 2, color);
        }
        _ = sdl.SDL_RenderGeometry(self.handle, null, vertices[0..vertex_count].ptr, @intCast(vertex_count), indices[0..index_count].ptr, @intCast(index_count));
    }
}

fn appendStrokeQuad(vertices: *[icon_stroke_batch_capacity * icon_stroke_vertices_per_segment]sdl.SDL_Vertex, indices: *[icon_stroke_batch_capacity * icon_stroke_indices_per_segment]c_int, vertex_count: *usize, index_count: *usize, start: sdl.SDL_FPoint, end: sdl.SDL_FPoint, normal_x: f32, normal_y: f32, color: sdl.SDL_FColor) void {
    const base = vertex_count.*;
    vertices[base] = .{ .position = .{ .x = start.x + normal_x, .y = start.y + normal_y }, .color = color, .tex_coord = .{} };
    vertices[base + 1] = .{ .position = .{ .x = start.x - normal_x, .y = start.y - normal_y }, .color = color, .tex_coord = .{} };
    vertices[base + 2] = .{ .position = .{ .x = end.x - normal_x, .y = end.y - normal_y }, .color = color, .tex_coord = .{} };
    vertices[base + 3] = .{ .position = .{ .x = end.x + normal_x, .y = end.y + normal_y }, .color = color, .tex_coord = .{} };
    indices[index_count.* ..][0..6].* = .{ @intCast(base), @intCast(base + 1), @intCast(base + 2), @intCast(base), @intCast(base + 2), @intCast(base + 3) };
    vertex_count.* += 4;
    index_count.* += 6;
}

fn appendStrokeCap(vertices: *[icon_stroke_batch_capacity * icon_stroke_vertices_per_segment]sdl.SDL_Vertex, indices: *[icon_stroke_batch_capacity * icon_stroke_indices_per_segment]c_int, vertex_count: *usize, index_count: *usize, center: sdl.SDL_FPoint, radius: f32, color: sdl.SDL_FColor) void {
    const base = vertex_count.*;
    vertices[base] = .{ .position = center, .color = color, .tex_coord = .{} };
    for (0..icon_stroke_cap_segments) |index| {
        const angle = @as(f32, @floatCast(2 * std.math.pi)) * @as(f32, @floatFromInt(index)) / icon_stroke_cap_segments;
        vertices[base + index + 1] = .{
            .position = .{ .x = center.x + @cos(angle) * radius, .y = center.y + @sin(angle) * radius },
            .color = color,
            .tex_coord = .{},
        };
    }
    for (0..icon_stroke_cap_segments) |index| {
        const next = (index + 1) % icon_stroke_cap_segments;
        indices[index_count.* ..][0..3].* = .{ @intCast(base), @intCast(base + index + 1), @intCast(base + next + 1) };
        index_count.* += 3;
    }
    vertex_count.* += icon_stroke_cap_segments + 1;
}

fn fillRoundedRect(self: *Renderer, rect: sdl.SDL_FRect, radius: f32, color: clay.Clay_Color) void {
    const clamped_radius = @min(radius, @min(rect.w, rect.h) / 2);
    if (clamped_radius <= 0) {
        self.fillRect(rect);
        return;
    }

    const segments_per_corner = 8;
    const point_count = 4 * (segments_per_corner + 1);
    const corner_step: f32 = (@as(f32, std.math.pi) / 2) / @as(f32, @floatFromInt(segments_per_corner));
    var vertices: [point_count + 1]sdl.SDL_Vertex = undefined;
    var indices: [point_count * 3]c_int = undefined;
    const center = sdl.SDL_FPoint{ .x = rect.x + rect.w / 2, .y = rect.y + rect.h / 2 };
    const vertex_color = sdl.SDL_FColor{
        .r = color.r / 255,
        .g = color.g / 255,
        .b = color.b / 255,
        .a = color.a / 255,
    };
    vertices[0] = .{ .position = center, .color = vertex_color, .tex_coord = .{} };

    var point_index: usize = 0;
    for (0..4) |corner| {
        const cx = switch (corner) {
            0, 3 => rect.x + clamped_radius,
            else => rect.x + rect.w - clamped_radius,
        };
        const cy = switch (corner) {
            0, 1 => rect.y + clamped_radius,
            else => rect.y + rect.h - clamped_radius,
        };
        const half_pi: f32 = @as(f32, std.math.pi) / 2;
        const start_angle: f32 = switch (corner) {
            0 => @as(f32, std.math.pi),
            1 => -half_pi,
            2 => 0,
            else => half_pi,
        };
        for (0..segments_per_corner + 1) |segment_index| {
            const angle = start_angle + @as(f32, @floatFromInt(segment_index)) * corner_step;
            vertices[point_index + 1] = .{
                .position = .{ .x = cx + @cos(angle) * clamped_radius, .y = cy + @sin(angle) * clamped_radius },
                .color = vertex_color,
                .tex_coord = .{},
            };
            point_index += 1;
        }
    }

    for (0..point_count) |index| {
        indices[index * 3] = 0;
        indices[index * 3 + 1] = @intCast(index + 1);
        indices[index * 3 + 2] = @intCast((index + 1) % point_count + 1);
    }
    _ = sdl.SDL_RenderGeometry(self.handle, null, &vertices, @intCast(vertices.len), &indices, @intCast(indices.len));
}

fn fillRect(self: *Renderer, rect: sdl.SDL_FRect) void {
    _ = sdl.SDL_RenderFillRect(self.handle, &rect);
}

fn beginScissor(self: *Renderer, rect: sdl.SDL_FRect) void {
    if (self.scissor_depth == self.scissor_stack.len) return;
    var clip = sdl.SDL_Rect{ .x = @intFromFloat(rect.x), .y = @intFromFloat(rect.y), .w = @intFromFloat(rect.w), .h = @intFromFloat(rect.h) };
    if (self.scissor_depth != 0) {
        const parent = self.scissor_stack[self.scissor_depth - 1];
        const left = @max(clip.x, parent.x);
        const top = @max(clip.y, parent.y);
        const right = @min(clip.x + clip.w, parent.x + parent.w);
        const bottom = @min(clip.y + clip.h, parent.y + parent.h);
        clip = .{ .x = left, .y = top, .w = @max(0, right - left), .h = @max(0, bottom - top) };
    }
    self.scissor_stack[self.scissor_depth] = clip;
    self.scissor_depth += 1;
    _ = sdl.SDL_SetRenderClipRect(self.handle, &clip);
}

fn endScissor(self: *Renderer) void {
    if (self.scissor_depth == 0) return;
    self.scissor_depth -= 1;
    if (self.scissor_depth == 0) {
        _ = sdl.SDL_SetRenderClipRect(self.handle, null);
    } else {
        _ = sdl.SDL_SetRenderClipRect(self.handle, &self.scissor_stack[self.scissor_depth - 1]);
    }
}

fn fontFor(self: *Renderer, family: Assets.Font, font_size: u16) ?*sdl.TTF_Font {
    const family_index = @intFromEnum(family);
    const logical_size = @max(font_size, 8);
    const pixel_size: usize = @min(@as(usize, logical_size) * @as(usize, @intFromFloat(@max(1, @round(@max(self.scale_x, self.scale_y))))), font_size_count - 1);
    if (self.fonts[family_index][pixel_size]) |font| return font;

    const bytes = Assets.fontBytes(family);
    const stream = sdl.SDL_IOFromConstMem(bytes.ptr, bytes.len) orelse return null;
    const font = sdl.TTF_OpenFontIO(stream, true, @floatFromInt(pixel_size)) orelse return null;
    self.fonts[family_index][pixel_size] = font;
    return font;
}

fn ensureGlyphCoverage(self: *Renderer, font: *sdl.TTF_Font, font_size: u16, bytes: []const u8) void {
    const pixel_size: usize = @min(@as(usize, @max(font_size, 8)) * @as(usize, @intFromFloat(@max(1, @round(@max(self.scale_x, self.scale_y))))), font_size_count - 1);
    var cursor: [*c]const u8 = @ptrCast(bytes.ptr);
    var remaining = bytes.len;
    while (remaining != 0) {
        const codepoint = sdl.SDL_StepUTF8(&cursor, &remaining);
        if (codepoint == 0 or sdl.TTF_FontHasGlyph(font, codepoint)) continue;
        for (self.system_fonts.items) |*system_font| {
            const fallback = systemFontForSize(system_font, pixel_size) orelse continue;
            if (!sdl.TTF_FontHasGlyph(fallback, codepoint)) continue;
            if (sdl.TTF_AddFallbackFont(font, fallback)) break;
        }
    }
}

fn systemFontForSize(system_font: *SystemFont, pixel_size: usize) ?*sdl.TTF_Font {
    if (system_font.attempted[pixel_size]) return system_font.fonts[pixel_size];
    system_font.attempted[pixel_size] = true;
    const font = sdl.TTF_OpenFont(system_font.path.ptr, @floatFromInt(pixel_size)) orelse return null;
    system_font.fonts[pixel_size] = font;
    return font;
}

fn discoverSystemFonts(allocator: std.mem.Allocator, io: std.Io, home: []const u8) std.ArrayList(SystemFont) {
    var fonts: std.ArrayList(SystemFont) = .empty;
    if (builtin.os.tag == .macos) {
        appendSystemFontPath(allocator, io, &fonts, "/System/Library/Fonts/Supplemental/Arial Unicode.ttf");
        appendSystemFontPath(allocator, io, &fonts, "/System/Library/Fonts/Apple Color Emoji.ttc");
        appendSystemFontDirectory(allocator, io, &fonts, "/System/Library/Fonts");
        appendSystemFontDirectory(allocator, io, &fonts, "/Library/Fonts");
        if (home.len != 0) appendHomeFontDirectory(allocator, io, &fonts, home, "Library/Fonts");
    } else if (builtin.os.tag == .windows) {
        appendSystemFontPath(allocator, io, &fonts, "C:/Windows/Fonts/seguiemj.ttf");
        appendSystemFontDirectory(allocator, io, &fonts, "C:/Windows/Fonts");
    } else {
        appendSystemFontPath(allocator, io, &fonts, "/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf");
        appendSystemFontDirectory(allocator, io, &fonts, "/usr/share/fonts");
        appendSystemFontDirectory(allocator, io, &fonts, "/usr/local/share/fonts");
        if (home.len != 0) {
            appendHomeFontDirectory(allocator, io, &fonts, home, ".local/share/fonts");
            appendHomeFontDirectory(allocator, io, &fonts, home, ".fonts");
        }
    }
    return fonts;
}

fn appendHomeFontDirectory(allocator: std.mem.Allocator, io: std.Io, fonts: *std.ArrayList(SystemFont), home: []const u8, suffix: []const u8) void {
    const path = std.fs.path.join(allocator, &.{ home, suffix }) catch return;
    defer allocator.free(path);
    appendSystemFontDirectory(allocator, io, fonts, path);
}

fn appendSystemFontDirectory(allocator: std.mem.Allocator, io: std.Io, fonts: *std.ArrayList(SystemFont), root: []const u8) void {
    var directory = std.Io.Dir.cwd().openDir(io, root, .{ .iterate = true, .follow_symlinks = false }) catch return;
    defer directory.close(io);
    var walker = directory.walk(allocator) catch return;
    defer walker.deinit();

    while (fonts.items.len < max_system_fonts) {
        const maybe_entry = walker.next(io) catch return;
        const entry = maybe_entry orelse return;
        if (entry.kind != .file or !isFontFile(entry.path)) continue;
        const path = std.fs.path.join(allocator, &.{ root, entry.path }) catch continue;
        defer allocator.free(path);
        appendSystemFontPath(allocator, io, fonts, path);
    }
}

fn appendSystemFontPath(allocator: std.mem.Allocator, io: std.Io, fonts: *std.ArrayList(SystemFont), path: []const u8) void {
    if (fonts.items.len >= max_system_fonts) return;
    for (fonts.items) |font| if (std.mem.eql(u8, font.path, path)) return;
    _ = std.Io.Dir.cwd().statFile(io, path, .{}) catch return;
    const path_z = allocator.dupeZ(u8, path) catch return;
    fonts.append(allocator, .{ .path = path_z }) catch allocator.free(path_z);
}

fn deinitSystemFonts(allocator: std.mem.Allocator, fonts: *std.ArrayList(SystemFont)) void {
    for (fonts.items) |*font| {
        for (font.fonts) |fallback| if (fallback) |value| sdl.TTF_CloseFont(value);
        allocator.free(font.path);
    }
    fonts.deinit(allocator);
}

fn isFontFile(path: []const u8) bool {
    const extension = std.fs.path.extension(path);
    return std.ascii.eqlIgnoreCase(extension, ".ttf") or
        std.ascii.eqlIgnoreCase(extension, ".ttc") or
        std.ascii.eqlIgnoreCase(extension, ".otf") or
        std.ascii.eqlIgnoreCase(extension, ".otc");
}

fn measureText(text: clay.Clay_StringSlice, config: ?*clay.Clay_TextElementConfig, user_data: ?*anyopaque) callconv(.c) clay.Clay_Dimensions {
    const renderer: *Renderer = @ptrCast(@alignCast(user_data.?));
    const text_config = config orelse return .{ .width = 0, .height = 0 };
    const bytes = if (text.chars) |chars| chars[0..@intCast(text.length)] else return .{ .width = 0, .height = @floatFromInt(text_config.fontSize) };
    const family: Assets.Font = if (text_config.fontId == @intFromEnum(Assets.Font.medium)) .medium else .regular;
    const font = renderer.fontFor(family, text_config.fontSize) orelse return .{ .width = 0, .height = @floatFromInt(text_config.fontSize) };
    renderer.ensureGlyphCoverage(font, text_config.fontSize, bytes);
    var width: c_int = 0;
    var height: c_int = 0;
    if (!sdl.TTF_GetStringSize(font, bytes.ptr, bytes.len, &width, &height)) return .{ .width = 0, .height = @floatFromInt(text_config.fontSize) };
    const scale_x = @max(renderer.scale_x, 0.01);
    const scale_y = @max(renderer.scale_y, 0.01);
    const measured_height = if (text_config.lineHeight != 0) text_config.lineHeight else @as(f32, @floatFromInt(height)) / scale_y;
    return .{ .width = @as(f32, @floatFromInt(width)) / scale_x, .height = measured_height };
}

fn clayError(data: clay.Clay_ErrorData) callconv(.c) void {
    _ = data;
}

fn setColor(self: *Renderer, red: f32, green: f32, blue: f32, alpha: f32) void {
    _ = sdl.SDL_SetRenderDrawColor(self.handle, @intFromFloat(std.math.clamp(red, 0, 255)), @intFromFloat(std.math.clamp(green, 0, 255)), @intFromFloat(std.math.clamp(blue, 0, 255)), @intFromFloat(std.math.clamp(alpha, 0, 255)));
}

fn maxCornerRadius(radius: clay.Clay_CornerRadius) f32 {
    return @max(radius.topLeft, @max(radius.topRight, @max(radius.bottomLeft, radius.bottomRight)));
}
