const std = @import("std");
const builtin = @import("builtin");

extern "c" fn MacOSIsTextNfc(source: [*c]const u8, length: usize) bool;
extern "c" fn MacOSNormalizeText(source: [*c]const u8, length: usize, destination: [*c]u8, capacity: usize) usize;

pub const Font = enum(u8) { regular, medium };

pub const Icon = enum(u8) { folder, file_text, plus, x, settings, sidebar_close };

pub const ImageReference = enum(u8) { preview, folder, file_text, plus, x, settings, sidebar_close };

pub const BinaryThumbnail = struct {
    bytes: []u8,
};

pub const Point = struct { x: f32, y: f32 };
pub const Segment = struct { start: Point, end: Point };
pub const Color = struct { r: u8, g: u8, b: u8, a: u8 = 255 };

pub const SvgIcon = struct {
    width: f32,
    height: f32,
    stroke_width: f32,
    color: Color,
    segments: []Segment,
};

pub const Catalog = struct {
    allocator: std.mem.Allocator,
    icons: [std.meta.fields(Icon).len]SvgIcon,

    pub fn init(allocator: std.mem.Allocator) !Catalog {
        var self: Catalog = .{ .allocator = allocator, .icons = undefined };
        var loaded: usize = 0;
        errdefer for (self.icons[0..loaded]) |asset| allocator.free(asset.segments);

        inline for (std.meta.tags(Icon), 0..) |icon_name, index| {
            self.icons[index] = try parseSvg(allocator, svgBytes(icon_name));
            loaded += 1;
        }
        return self;
    }

    pub fn deinit(self: *Catalog) void {
        for (&self.icons) |asset| self.allocator.free(asset.segments);
    }

    pub fn icon(self: *const Catalog, name: Icon) SvgIcon {
        return self.icons[@intFromEnum(name)];
    }
};

const image_markers = [_]ImageReference{
    .preview,
    .folder,
    .file_text,
    .plus,
    .x,
    .settings,
    .sidebar_close,
};

pub fn clayImageData(reference: ImageReference) ?*anyopaque {
    return @ptrCast(@constCast(&image_markers[@intFromEnum(reference)]));
}

pub fn imageReferenceFromClay(data: ?*anyopaque) ?ImageReference {
    const pointer = data orelse return null;
    for (&image_markers, 0..) |*marker, index| {
        const marker_pointer: *anyopaque = @ptrCast(@constCast(marker));
        if (pointer == marker_pointer) return @enumFromInt(index);
    }
    return null;
}

pub fn referenceForIcon(icon: Icon) ImageReference {
    return switch (icon) {
        .folder => .folder,
        .file_text => .file_text,
        .plus => .plus,
        .x => .x,
        .settings => .settings,
        .sidebar_close => .sidebar_close,
    };
}

pub fn fontBytes(font: Font) []const u8 {
    return switch (font) {
        .regular => @embedFile("fonts/Pretendard-Regular.ttf"),
        .medium => @embedFile("fonts/Pretendard-Medium.ttf"),
    };
}

pub fn displayText(allocator: std.mem.Allocator, text: []const u8) []const u8 {
    if (comptime builtin.os.tag == .macos) {
        if (text.len == 0 or MacOSIsTextNfc(text.ptr, text.len)) return text;
        const length = MacOSNormalizeText(text.ptr, text.len, null, 0);
        if (length == std.math.maxInt(usize)) return text;
        const normalized = allocator.alloc(u8, length) catch return text;
        if (MacOSNormalizeText(text.ptr, text.len, normalized.ptr, normalized.len) != length) {
            allocator.free(normalized);
            return text;
        }
        return normalized;
    }
    return text;
}

pub fn svgBytes(icon: Icon) []const u8 {
    return switch (icon) {
        .folder => @embedFile("icons/folder.svg"),
        .file_text => @embedFile("icons/file-text.svg"),
        .plus => @embedFile("icons/plus.svg"),
        .x => @embedFile("icons/x.svg"),
        .settings => @embedFile("icons/settings.svg"),
        .sidebar_close => @embedFile("icons/sidebar-close.svg"),
    };
}

fn parseSvg(allocator: std.mem.Allocator, source: []const u8) !SvgIcon {
    var segments = std.ArrayList(Segment).empty;
    errdefer segments.deinit(allocator);

    const root = findTag(source, "svg", 0) orelse return error.InvalidSvgAsset;
    const width = attributeFloat(root.content, "width") orelse return error.InvalidSvgAsset;
    const height = attributeFloat(root.content, "height") orelse return error.InvalidSvgAsset;
    const stroke_width = attributeFloat(root.content, "stroke-width") orelse 1;
    const color = attributeColor(root.content, "stroke") orelse return error.InvalidSvgAsset;

    var position: usize = 0;
    while (findTag(source, "line", position)) |tag| : (position = tag.end) {
        try appendSegment(&segments, allocator, .{ .x = attributeFloat(tag.content, "x1") orelse 0, .y = attributeFloat(tag.content, "y1") orelse 0 }, .{ .x = attributeFloat(tag.content, "x2") orelse 0, .y = attributeFloat(tag.content, "y2") orelse 0 });
    }

    position = 0;
    while (findTag(source, "polyline", position)) |tag| : (position = tag.end) {
        if (attribute(tag.content, "points")) |points| try appendPointList(&segments, allocator, points);
    }

    position = 0;
    while (findTag(source, "rect", position)) |tag| : (position = tag.end) {
        const x = attributeFloat(tag.content, "x") orelse 0;
        const y = attributeFloat(tag.content, "y") orelse 0;
        const w = attributeFloat(tag.content, "width") orelse 0;
        const h = attributeFloat(tag.content, "height") orelse 0;
        const rx = attributeFloat(tag.content, "rx") orelse attributeFloat(tag.content, "ry") orelse 0;
        const ry = attributeFloat(tag.content, "ry") orelse rx;
        try appendRoundedRect(&segments, allocator, x, y, w, h, rx, ry);
    }

    position = 0;
    while (findTag(source, "circle", position)) |tag| : (position = tag.end) {
        const center = Point{ .x = attributeFloat(tag.content, "cx") orelse 0, .y = attributeFloat(tag.content, "cy") orelse 0 };
        const radius = attributeFloat(tag.content, "r") orelse 0;
        const circle_step: f32 = @as(f32, std.math.pi) * 2 / 32;
        var previous = Point{ .x = center.x + radius, .y = center.y };
        for (1..33) |step| {
            const angle = @as(f32, @floatFromInt(step)) * circle_step;
            const current = Point{ .x = center.x + @cos(angle) * radius, .y = center.y + @sin(angle) * radius };
            try appendSegment(&segments, allocator, previous, current);
            previous = current;
        }
    }

    position = 0;
    while (findTag(source, "path", position)) |tag| : (position = tag.end) {
        if (attribute(tag.content, "d")) |path| try appendPath(&segments, allocator, path);
    }

    return .{ .width = width, .height = height, .stroke_width = stroke_width, .color = color, .segments = try segments.toOwnedSlice(allocator) };
}

const Tag = struct { content: []const u8, end: usize };

fn findTag(source: []const u8, name: []const u8, from: usize) ?Tag {
    var cursor = from;
    while (std.mem.indexOfPos(u8, source, cursor, "<")) |start| {
        const name_start = start + 1;
        const name_end = name_start + name.len;
        if (name_end <= source.len and std.mem.eql(u8, source[name_start..name_end], name) and (name_end == source.len or isSpace(source[name_end]) or source[name_end] == '>' or source[name_end] == '/')) {
            const end = std.mem.indexOfPos(u8, source, name_end, ">") orelse return null;
            return .{ .content = source[name_start..end], .end = end + 1 };
        }
        cursor = name_end;
    }
    return null;
}

fn attribute(content: []const u8, name: []const u8) ?[]const u8 {
    var cursor: usize = 0;
    while (std.mem.indexOfPos(u8, content, cursor, name)) |start| {
        const end = start + name.len;
        if (start != 0 and isAttributeChar(content[start - 1])) {
            cursor = end;
            continue;
        }
        if (end < content.len and isAttributeChar(content[end])) {
            cursor = end;
            continue;
        }
        var value_start = end;
        while (value_start < content.len and isSpace(content[value_start])) : (value_start += 1) {}
        if (value_start == content.len or content[value_start] != '=') {
            cursor = end;
            continue;
        }
        value_start += 1;
        while (value_start < content.len and isSpace(content[value_start])) : (value_start += 1) {}
        if (value_start == content.len or (content[value_start] != '"' and content[value_start] != '\'')) return null;
        const quote = content[value_start];
        value_start += 1;
        const value_end = std.mem.indexOfScalarPos(u8, content, value_start, quote) orelse return null;
        return content[value_start..value_end];
    }
    return null;
}

fn attributeFloat(content: []const u8, name: []const u8) ?f32 {
    const value = attribute(content, name) orelse return null;
    return std.fmt.parseFloat(f32, value) catch null;
}

fn attributeColor(content: []const u8, name: []const u8) ?Color {
    const value = attribute(content, name) orelse return null;
    if (value.len != 7 or value[0] != '#') return null;
    return .{
        .r = std.fmt.parseInt(u8, value[1..3], 16) catch return null,
        .g = std.fmt.parseInt(u8, value[3..5], 16) catch return null,
        .b = std.fmt.parseInt(u8, value[5..7], 16) catch return null,
    };
}

fn appendPointList(segments: *std.ArrayList(Segment), allocator: std.mem.Allocator, source: []const u8) !void {
    var scanner = NumberScanner{ .source = source };
    var previous: ?Point = null;
    while (scanner.number()) |x| {
        const y = scanner.number() orelse return error.InvalidSvgAsset;
        const point = Point{ .x = x, .y = y };
        if (previous) |start| try appendSegment(segments, allocator, start, point);
        previous = point;
    }
}

fn appendPath(segments: *std.ArrayList(Segment), allocator: std.mem.Allocator, source: []const u8) !void {
    var scanner = NumberScanner{ .source = source };
    var command: u8 = 0;
    var previous_command: u8 = 0;
    var previous_control: ?Point = null;
    var current = Point{ .x = 0, .y = 0 };
    var start = current;
    while (scanner.index < source.len) {
        scanner.skipSeparators();
        if (scanner.index == source.len) break;
        if (std.ascii.isAlphabetic(source[scanner.index])) command = source[scanner.index];
        if (std.ascii.isAlphabetic(source[scanner.index])) scanner.index += 1;
        switch (command) {
            'M', 'm' => {
                const x = scanner.number() orelse return error.InvalidSvgAsset;
                const y = scanner.number() orelse return error.InvalidSvgAsset;
                current = if (command == 'm') .{ .x = current.x + x, .y = current.y + y } else .{ .x = x, .y = y };
                start = current;
                command = if (command == 'm') 'l' else 'L';
                previous_command = 0;
                previous_control = null;
            },
            'L', 'l' => {
                const x = scanner.number() orelse return error.InvalidSvgAsset;
                const y = scanner.number() orelse return error.InvalidSvgAsset;
                const next = if (command == 'l') Point{ .x = current.x + x, .y = current.y + y } else Point{ .x = x, .y = y };
                try appendSegment(segments, allocator, current, next);
                current = next;
                previous_command = 0;
                previous_control = null;
            },
            'H', 'h' => {
                const x = scanner.number() orelse return error.InvalidSvgAsset;
                const next = Point{ .x = if (command == 'h') current.x + x else x, .y = current.y };
                try appendSegment(segments, allocator, current, next);
                current = next;
                previous_command = 0;
                previous_control = null;
            },
            'V', 'v' => {
                const y = scanner.number() orelse return error.InvalidSvgAsset;
                const next = Point{ .x = current.x, .y = if (command == 'v') current.y + y else y };
                try appendSegment(segments, allocator, current, next);
                current = next;
                previous_command = 0;
                previous_control = null;
            },
            'C', 'c' => {
                const x1 = scanner.number() orelse return error.InvalidSvgAsset;
                const y1 = scanner.number() orelse return error.InvalidSvgAsset;
                const x2 = scanner.number() orelse return error.InvalidSvgAsset;
                const y2 = scanner.number() orelse return error.InvalidSvgAsset;
                const x = scanner.number() orelse return error.InvalidSvgAsset;
                const y = scanner.number() orelse return error.InvalidSvgAsset;
                const first = relativePoint(current, x1, y1, command == 'c');
                const second = relativePoint(current, x2, y2, command == 'c');
                const next = relativePoint(current, x, y, command == 'c');
                try appendCubic(segments, allocator, current, first, second, next);
                current = next;
                previous_control = second;
                previous_command = command;
            },
            'S', 's' => {
                const x2 = scanner.number() orelse return error.InvalidSvgAsset;
                const y2 = scanner.number() orelse return error.InvalidSvgAsset;
                const x = scanner.number() orelse return error.InvalidSvgAsset;
                const y = scanner.number() orelse return error.InvalidSvgAsset;
                const first = if (isCubicCommand(previous_command)) reflectedControl(current, previous_control) else current;
                const second = relativePoint(current, x2, y2, command == 's');
                const next = relativePoint(current, x, y, command == 's');
                try appendCubic(segments, allocator, current, first, second, next);
                current = next;
                previous_control = second;
                previous_command = command;
            },
            'Q', 'q' => {
                const x1 = scanner.number() orelse return error.InvalidSvgAsset;
                const y1 = scanner.number() orelse return error.InvalidSvgAsset;
                const x = scanner.number() orelse return error.InvalidSvgAsset;
                const y = scanner.number() orelse return error.InvalidSvgAsset;
                const control = relativePoint(current, x1, y1, command == 'q');
                const next = relativePoint(current, x, y, command == 'q');
                try appendQuadratic(segments, allocator, current, control, next);
                current = next;
                previous_control = control;
                previous_command = command;
            },
            'T', 't' => {
                const x = scanner.number() orelse return error.InvalidSvgAsset;
                const y = scanner.number() orelse return error.InvalidSvgAsset;
                const control = if (isQuadraticCommand(previous_command)) reflectedControl(current, previous_control) else current;
                const next = relativePoint(current, x, y, command == 't');
                try appendQuadratic(segments, allocator, current, control, next);
                current = next;
                previous_control = control;
                previous_command = command;
            },
            'A', 'a' => {
                const rx = scanner.number() orelse return error.InvalidSvgAsset;
                const ry = scanner.number() orelse return error.InvalidSvgAsset;
                const rotation = scanner.number() orelse return error.InvalidSvgAsset;
                const large_arc = scanner.number() orelse return error.InvalidSvgAsset;
                const sweep = scanner.number() orelse return error.InvalidSvgAsset;
                const x = scanner.number() orelse return error.InvalidSvgAsset;
                const y = scanner.number() orelse return error.InvalidSvgAsset;
                const next = relativePoint(current, x, y, command == 'a');
                try appendArc(segments, allocator, current, rx, ry, rotation, large_arc != 0, sweep != 0, next);
                current = next;
                previous_command = 0;
                previous_control = null;
            },
            'Z', 'z' => {
                try appendSegment(segments, allocator, current, start);
                current = start;
                command = 0;
                previous_command = 0;
                previous_control = null;
            },
            else => return error.UnsupportedSvgPath,
        }
    }
}

fn appendRoundedRect(segments: *std.ArrayList(Segment), allocator: std.mem.Allocator, x: f32, y: f32, width: f32, height: f32, rx_value: f32, ry_value: f32) !void {
    const rx = @min(@max(0, rx_value), width / 2);
    const ry = @min(@max(0, ry_value), height / 2);
    if (rx == 0 or ry == 0) {
        try appendSegment(segments, allocator, .{ .x = x, .y = y }, .{ .x = x + width, .y = y });
        try appendSegment(segments, allocator, .{ .x = x + width, .y = y }, .{ .x = x + width, .y = y + height });
        try appendSegment(segments, allocator, .{ .x = x + width, .y = y + height }, .{ .x = x, .y = y + height });
        try appendSegment(segments, allocator, .{ .x = x, .y = y + height }, .{ .x = x, .y = y });
        return;
    }

    var current = Point{ .x = x + rx, .y = y };
    const top_right = Point{ .x = x + width - rx, .y = y };
    try appendSegment(segments, allocator, current, top_right);
    current = .{ .x = x + width, .y = y + ry };
    try appendArc(segments, allocator, top_right, rx, ry, 0, false, true, current);
    const bottom_right = Point{ .x = x + width, .y = y + height - ry };
    try appendSegment(segments, allocator, current, bottom_right);
    current = .{ .x = x + width - rx, .y = y + height };
    try appendArc(segments, allocator, bottom_right, rx, ry, 0, false, true, current);
    const bottom_left = Point{ .x = x + rx, .y = y + height };
    try appendSegment(segments, allocator, current, bottom_left);
    current = .{ .x = x, .y = y + height - ry };
    try appendArc(segments, allocator, bottom_left, rx, ry, 0, false, true, current);
    const top_left = Point{ .x = x, .y = y + ry };
    try appendSegment(segments, allocator, current, top_left);
    try appendArc(segments, allocator, top_left, rx, ry, 0, false, true, .{ .x = x + rx, .y = y });
}

fn appendQuadratic(segments: *std.ArrayList(Segment), allocator: std.mem.Allocator, from: Point, control: Point, to: Point) !void {
    const steps = 12;
    var previous = from;
    for (1..steps + 1) |step| {
        const t = @as(f32, @floatFromInt(step)) / steps;
        const inverse = 1 - t;
        const next = Point{
            .x = inverse * inverse * from.x + 2 * inverse * t * control.x + t * t * to.x,
            .y = inverse * inverse * from.y + 2 * inverse * t * control.y + t * t * to.y,
        };
        try appendSegment(segments, allocator, previous, next);
        previous = next;
    }
}

fn appendCubic(segments: *std.ArrayList(Segment), allocator: std.mem.Allocator, from: Point, first: Point, second: Point, to: Point) !void {
    const steps = 16;
    var previous = from;
    for (1..steps + 1) |step| {
        const t = @as(f32, @floatFromInt(step)) / steps;
        const inverse = 1 - t;
        const next = Point{
            .x = inverse * inverse * inverse * from.x + 3 * inverse * inverse * t * first.x + 3 * inverse * t * t * second.x + t * t * t * to.x,
            .y = inverse * inverse * inverse * from.y + 3 * inverse * inverse * t * first.y + 3 * inverse * t * t * second.y + t * t * t * to.y,
        };
        try appendSegment(segments, allocator, previous, next);
        previous = next;
    }
}

fn appendArc(segments: *std.ArrayList(Segment), allocator: std.mem.Allocator, from: Point, rx_value: f32, ry_value: f32, rotation: f32, large_arc: bool, sweep: bool, to: Point) !void {
    var rx = @abs(rx_value);
    var ry = @abs(ry_value);
    if (rx == 0 or ry == 0 or (from.x == to.x and from.y == to.y)) return appendSegment(segments, allocator, from, to);

    const phi = rotation * (@as(f32, std.math.pi) / 180);
    const cosine = @cos(phi);
    const sine = @sin(phi);
    const half_x = (from.x - to.x) / 2;
    const half_y = (from.y - to.y) / 2;
    const prime_x = cosine * half_x + sine * half_y;
    const prime_y = -sine * half_x + cosine * half_y;
    const lambda = prime_x * prime_x / (rx * rx) + prime_y * prime_y / (ry * ry);
    if (lambda > 1) {
        const factor = @sqrt(lambda);
        rx *= factor;
        ry *= factor;
    }

    const rx2 = rx * rx;
    const ry2 = ry * ry;
    const prime_x2 = prime_x * prime_x;
    const prime_y2 = prime_y * prime_y;
    const denominator = rx2 * prime_y2 + ry2 * prime_x2;
    const numerator = @max(0, rx2 * ry2 - rx2 * prime_y2 - ry2 * prime_x2);
    const sign: f32 = if (large_arc == sweep) -1 else 1;
    const factor = if (denominator == 0) 0 else sign * @sqrt(numerator / denominator);
    const center_prime_x = factor * rx * prime_y / ry;
    const center_prime_y = factor * -ry * prime_x / rx;
    const center = Point{
        .x = cosine * center_prime_x - sine * center_prime_y + (from.x + to.x) / 2,
        .y = sine * center_prime_x + cosine * center_prime_y + (from.y + to.y) / 2,
    };
    const start_x = (prime_x - center_prime_x) / rx;
    const start_y = (prime_y - center_prime_y) / ry;
    const end_x = (-prime_x - center_prime_x) / rx;
    const end_y = (-prime_y - center_prime_y) / ry;
    const start_angle = std.math.atan2(start_y, start_x);
    var delta = std.math.atan2(start_x * end_y - start_y * end_x, start_x * end_x + start_y * end_y);
    if (!sweep and delta > 0) delta -= 2 * @as(f32, std.math.pi);
    if (sweep and delta < 0) delta += 2 * @as(f32, std.math.pi);

    const max_step: f32 = @as(f32, std.math.pi) / 12;
    const step_count: usize = @intFromFloat(@min(48, @max(1, @ceil(@abs(delta) / max_step))));
    var previous = from;
    for (1..step_count + 1) |step| {
        const angle = start_angle + delta * @as(f32, @floatFromInt(step)) / @as(f32, @floatFromInt(step_count));
        const next = if (step == step_count) to else Point{
            .x = center.x + cosine * rx * @cos(angle) - sine * ry * @sin(angle),
            .y = center.y + sine * rx * @cos(angle) + cosine * ry * @sin(angle),
        };
        try appendSegment(segments, allocator, previous, next);
        previous = next;
    }
}

fn relativePoint(origin: Point, x: f32, y: f32, relative: bool) Point {
    return if (relative) .{ .x = origin.x + x, .y = origin.y + y } else .{ .x = x, .y = y };
}

fn reflectedControl(origin: Point, control: ?Point) Point {
    const previous = control orelse return origin;
    return .{ .x = 2 * origin.x - previous.x, .y = 2 * origin.y - previous.y };
}

fn isCubicCommand(command: u8) bool {
    return command == 'C' or command == 'c' or command == 'S' or command == 's';
}

fn isQuadraticCommand(command: u8) bool {
    return command == 'Q' or command == 'q' or command == 'T' or command == 't';
}

const NumberScanner = struct {
    source: []const u8,
    index: usize = 0,

    fn skipSeparators(self: *NumberScanner) void {
        while (self.index < self.source.len and (isSpace(self.source[self.index]) or self.source[self.index] == ',')) : (self.index += 1) {}
    }

    fn number(self: *NumberScanner) ?f32 {
        self.skipSeparators();
        if (self.index == self.source.len or std.ascii.isAlphabetic(self.source[self.index])) return null;
        const start = self.index;
        if (self.source[self.index] == '+' or self.source[self.index] == '-') self.index += 1;
        var has_digit = false;
        while (self.index < self.source.len and std.ascii.isDigit(self.source[self.index])) : (self.index += 1) has_digit = true;
        if (self.index < self.source.len and self.source[self.index] == '.') {
            self.index += 1;
            while (self.index < self.source.len and std.ascii.isDigit(self.source[self.index])) : (self.index += 1) has_digit = true;
        }
        if (!has_digit) return null;
        if (self.index < self.source.len and (self.source[self.index] == 'e' or self.source[self.index] == 'E')) {
            self.index += 1;
            if (self.index < self.source.len and (self.source[self.index] == '+' or self.source[self.index] == '-')) self.index += 1;
            const exponent_start = self.index;
            while (self.index < self.source.len and std.ascii.isDigit(self.source[self.index])) : (self.index += 1) {}
            if (self.index == exponent_start) return null;
        }
        return std.fmt.parseFloat(f32, self.source[start..self.index]) catch null;
    }
};

fn appendSegment(segments: *std.ArrayList(Segment), allocator: std.mem.Allocator, start: Point, end: Point) !void {
    if (start.x == end.x and start.y == end.y) return;
    try segments.append(allocator, .{ .start = start, .end = end });
}

fn isSpace(value: u8) bool {
    return value == ' ' or value == '\t' or value == '\r' or value == '\n';
}

fn isAttributeChar(value: u8) bool {
    return std.ascii.isAlphanumeric(value) or value == '-' or value == '_';
}
