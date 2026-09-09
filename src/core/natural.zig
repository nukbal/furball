const std = @import("std");

pub fn compare(a: []const u8, b: []const u8) std.math.Order {
    var left: usize = 0;
    var right: usize = 0;
    while (left < a.len and right < b.len) {
        if (std.ascii.isDigit(a[left]) and std.ascii.isDigit(b[right])) {
            const left_start = left;
            const right_start = right;
            while (left < a.len and std.ascii.isDigit(a[left])) : (left += 1) {}
            while (right < b.len and std.ascii.isDigit(b[right])) : (right += 1) {}
            const left_digits = std.mem.trimStart(u8, a[left_start..left], "0");
            const right_digits = std.mem.trimStart(u8, b[right_start..right], "0");
            const left_value = if (left_digits.len == 0) "0" else left_digits;
            const right_value = if (right_digits.len == 0) "0" else right_digits;
            if (left_value.len != right_value.len) return std.math.order(left_value.len, right_value.len);
            const numeric = std.mem.order(u8, left_value, right_value);
            if (numeric != .eq) return numeric;
            if (left - left_start != right - right_start) return std.math.order(left - left_start, right - right_start);
            continue;
        }
        const left_byte = std.ascii.toLower(a[left]);
        const right_byte = std.ascii.toLower(b[right]);
        if (left_byte != right_byte) return std.math.order(left_byte, right_byte);
        left += 1;
        right += 1;
    }
    return std.math.order(a.len, b.len);
}

pub fn lessThan(_: void, a: []const u8, b: []const u8) bool {
    return compare(a, b) == .lt;
}

test "natural ordering puts page 2 before page 10" {
    var values = [_][]const u8{ "page10.png", "page2.png", "page1.png" };
    std.mem.sort([]const u8, &values, {}, lessThan);
    try std.testing.expectEqualStrings("page1.png", values[0]);
    try std.testing.expectEqualStrings("page2.png", values[1]);
    try std.testing.expectEqualStrings("page10.png", values[2]);
}

test "natural ordering is case insensitive" {
    try std.testing.expectEqual(std.math.Order.eq, compare("A", "a"));
}
