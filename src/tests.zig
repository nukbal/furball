const std = @import("std");

const image = @import("core/image.zig");
const main = @import("main.zig");
const operations = @import("core/operations.zig");
const pdf = @import("core/pdf.zig");
const protocol = @import("core/protocol.zig");
const realesrgan = @import("core/realesrgan.zig");
const zip = @import("core/zip.zig");

const png_base64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=";
const flate_pdf_base64 = "JVBERi0xLjcKJeLjz9MKMSAwIG9iago8PCAvVHlwZSAvQ2F0YWxvZyAvUGFnZXMgMiAwIFIgPj4KZW5kb2JqCjIgMCBvYmoKPDwgL1R5cGUgL1BhZ2VzIC9LaWRzIFszIDAgUl0gL0NvdW50IDEgPj4KZW5kb2JqCjMgMCBvYmoKPDwgL1R5cGUgL1BhZ2UgL1BhcmVudCAyIDAgUiAvUmVzb3VyY2VzIDQgMCBSIC9NZWRpYUJveCBbMCAwIDEgMV0gL0NvbnRlbnRzIDYgMCBSID4+CmVuZG9iago0IDAgb2JqCjw8IC9YT2JqZWN0IDw8IC9JbTAgNSAwIFIgPj4gPj4KZW5kb2JqCjUgMCBvYmoKPDwgL1R5cGUgL1hPYmplY3QgL1N1YnR5cGUgL0ltYWdlIC9XaWR0aCAxIC9IZWlnaHQgMSAvQml0c1BlckNvbXBvbmVudCA4IC9Db2xvclNwYWNlIC9EZXZpY2VSR0IgL0ZpbHRlciAvRmxhdGVEZWNvZGUgL0xlbmd0aCAxMSA+PgpzdHJlYW0KeJz7z8AAAAMAAQAKZW5kc3RyZWFtCmVuZG9iago2IDAgb2JqCjw8IC9MZW5ndGggMjcgPj4Kc3RyZWFtCnEKMSAwIDAgMSAwIDAgY20KL0ltMCBEbwpRCmVuZHN0cmVhbQplbmRvYmoKeHJlZgowIDcKMDAwMDAwMDAwMCA2NTUzNSBmIAowMDAwMDAwMDE1IDAwMDAwIG4gCjAwMDAwMDAwNjQgMDAwMDAgbiAKMDAwMDAwMDEyMSAwMDAwMCBuIAowMDAwMDAwMjIxIDAwMDAwIG4gCjAwMDAwMDAyNjggMDAwMDAgbiAKMDAwMDAwMDQ0MyAwMDAwMCBuIAp0cmFpbGVyCjw8IC9TaXplIDcgL1Jvb3QgMSAwIFIgPj4Kc3RhcnR4cmVmCjUxOQolJUVPRgo=";

const ProgressCounter = struct {
    value: usize = 0,

    fn advance(context: *anyopaque) void {
        const counter: *ProgressCounter = @ptrCast(@alignCast(context));
        counter.value += 1;
    }

    fn reporter(counter: *ProgressCounter) protocol.Progress {
        return .{ .context = counter, .advance_fn = advance };
    }
};

fn fixturePng(allocator: std.mem.Allocator) ![]u8 {
    const size = std.base64.standard.Decoder.calcSizeForSlice(png_base64) catch unreachable;
    const result = try allocator.alloc(u8, size);
    errdefer allocator.free(result);
    try std.base64.standard.Decoder.decode(result, png_base64);
    return result;
}

fn fixtureJpeg(allocator: std.mem.Allocator) ![]u8 {
    const png = try fixturePng(allocator);
    defer allocator.free(png);
    return image.encodeBytesFromMemory(allocator, std.testing.io, png, .{ .width = 1, .quality = 80, .ai = false });
}

fn fixtureFlatePdf(allocator: std.mem.Allocator) ![]u8 {
    const size = std.base64.standard.Decoder.calcSizeForSlice(flate_pdf_base64) catch unreachable;
    const result = try allocator.alloc(u8, size);
    errdefer allocator.free(result);
    try std.base64.standard.Decoder.decode(result, flate_pdf_base64);
    return result;
}

fn fixtureMixedPdf(allocator: std.mem.Allocator, jpeg: []const u8) ![]u8 {
    const flate = [_]u8{ 0x78, 0x9c, 0xfb, 0xcf, 0xc0, 0xf0, 0x9f, 0x81, 0x01, 0x00, 0x08, 0xfd, 0x01, 0xff };
    const content = "q\n/A Do\nQ\n";
    var output = std.ArrayList(u8).empty;
    errdefer output.deinit(allocator);
    var offsets: [8]usize = undefined;
    try output.appendSlice(allocator, "%PDF-1.7\n%\xE2\xE3\xCF\xD3\n");
    offsets[1] = output.items.len;
    try output.print(allocator, "1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n", .{});
    offsets[2] = output.items.len;
    try output.print(allocator, "2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n", .{});
    offsets[3] = output.items.len;
    try output.print(allocator, "3 0 obj\n<< /Type /Page /Parent 2 0 R /Resources 4 0 R /MediaBox [0 0 2 1] /Contents 6 0 R >>\nendobj\n", .{});
    offsets[4] = output.items.len;
    try output.print(allocator, "4 0 obj\n<< /XObject << /A 5 0 R /B 7 0 R >> >>\nendobj\n", .{});
    offsets[5] = output.items.len;
    try output.print(allocator, "5 0 obj\n<< /Type /XObject /Subtype /Image /Width 2 /Height 1 /BitsPerComponent 8 /ColorSpace /DeviceRGB /Filter /FlateDecode /Length {d} >>\nstream\n", .{flate.len});
    try output.appendSlice(allocator, &flate);
    try output.appendSlice(allocator, "\nendstream\nendobj\n");
    offsets[6] = output.items.len;
    try output.print(allocator, "6 0 obj\n<< /Length {d} >>\nstream\n{s}endstream\nendobj\n", .{ content.len, content });
    offsets[7] = output.items.len;
    try output.print(allocator, "7 0 obj\n<< /Type /XObject /Subtype /Image /Width 1 /Height 1 /BitsPerComponent 8 /ColorSpace /DeviceRGB /Filter /DCTDecode /Length {d} >>\nstream\n", .{jpeg.len});
    try output.appendSlice(allocator, jpeg);
    try output.appendSlice(allocator, "\nendstream\nendobj\n");
    const xref_offset = output.items.len;
    try output.appendSlice(allocator, "xref\n0 8\n0000000000 65535 f \n");
    for (offsets[1..]) |offset| try output.print(allocator, "{d:0>10} 00000 n \n", .{offset});
    try output.print(allocator, "trailer\n<< /Size 8 /Root 1 0 R >>\nstartxref\n{d}\n%%EOF\n", .{xref_offset});
    return output.toOwnedSlice(allocator);
}

fn fixtureCrossPagePdf(allocator: std.mem.Allocator, jpeg: []const u8) ![]u8 {
    const content = "q\n1 0 0 1 0 0 cm\n/Im0 Do\nQ\n";
    var output = std.ArrayList(u8).empty;
    errdefer output.deinit(allocator);
    var offsets: [8]usize = undefined;
    try output.appendSlice(allocator, "%PDF-1.7\n%\xE2\xE3\xCF\xD3\n");
    offsets[1] = output.items.len;
    try output.print(allocator, "1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n", .{});
    offsets[2] = output.items.len;
    try output.print(allocator, "2 0 obj\n<< /Type /Pages /Kids [3 0 R 6 0 R] /Count 2 >>\nendobj\n", .{});
    offsets[3] = output.items.len;
    try output.print(allocator, "3 0 obj\n<< /Type /Page /Parent 2 0 R /Resources << >> /MediaBox [0 0 1 1] /Contents 4 0 R >>\nendobj\n", .{});
    offsets[4] = output.items.len;
    try output.print(allocator, "4 0 obj\n<< /Length 0 >>\nstream\n\nendstream\nendobj\n", .{});
    offsets[5] = output.items.len;
    try output.print(allocator, "5 0 obj\n<< /Type /XObject /Subtype /Image /Width 1 /Height 1 /BitsPerComponent 8 /ColorSpace /DeviceRGB /Filter /DCTDecode /Length {d} >>\nstream\n", .{jpeg.len});
    try output.appendSlice(allocator, jpeg);
    try output.appendSlice(allocator, "\nendstream\nendobj\n");
    offsets[6] = output.items.len;
    try output.print(allocator, "6 0 obj\n<< /Type /Page /Parent 2 0 R /Resources << /XObject << /Im0 5 0 R >> >> /MediaBox [0 0 1 1] /Contents 7 0 R >>\nendobj\n", .{});
    offsets[7] = output.items.len;
    try output.print(allocator, "7 0 obj\n<< /Length {d} >>\nstream\n{s}endstream\nendobj\n", .{ content.len, content });
    const xref_offset = output.items.len;
    try output.appendSlice(allocator, "xref\n0 8\n0000000000 65535 f \n");
    for (offsets[1..]) |offset| try output.print(allocator, "{d:0>10} 00000 n \n", .{offset});
    try output.print(allocator, "trailer\n<< /Size 8 /Root 1 0 R >>\nstartxref\n{d}\n%%EOF\n", .{xref_offset});
    return output.toOwnedSlice(allocator);
}

fn fixtureBlankInteriorPdf(allocator: std.mem.Allocator, jpeg: []const u8) ![]u8 {
    const image_content = "q\n/Im0 Do\nQ\n";
    var output = std.ArrayList(u8).empty;
    errdefer output.deinit(allocator);
    var offsets: [14]usize = undefined;
    try output.appendSlice(allocator, "%PDF-1.7\n%\xE2\xE3\xCF\xD3\n");
    offsets[1] = output.items.len;
    try output.appendSlice(allocator, "1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n");
    offsets[2] = output.items.len;
    try output.appendSlice(allocator, "2 0 obj\n<< /Type /Pages /Kids [3 0 R 5 0 R 7 0 R 9 0 R] /Count 4 >>\nendobj\n");
    offsets[3] = output.items.len;
    try output.appendSlice(allocator, "3 0 obj\n<< /Type /Page /Parent 2 0 R /Resources 11 0 R /MediaBox [0 0 1 1] /Contents 4 0 R >>\nendobj\n");
    offsets[4] = output.items.len;
    try output.print(allocator, "4 0 obj\n<< /Length {d} >>\nstream\n{s}endstream\nendobj\n", .{ image_content.len, image_content });
    offsets[5] = output.items.len;
    try output.appendSlice(allocator, "5 0 obj\n<< /Type /Page /Parent 2 0 R /Resources << >> /MediaBox [0 0 1 1] /Contents 6 0 R >>\nendobj\n");
    offsets[6] = output.items.len;
    try output.appendSlice(allocator, "6 0 obj\n<< /Length 0 >>\nstream\n\nendstream\nendobj\n");
    offsets[7] = output.items.len;
    try output.appendSlice(allocator, "7 0 obj\n<< /Type /Page /Parent 2 0 R /Resources << >> /MediaBox [0 0 1 1] /Contents 8 0 R >>\nendobj\n");
    offsets[8] = output.items.len;
    try output.appendSlice(allocator, "8 0 obj\n<< /Length 0 >>\nstream\n\nendstream\nendobj\n");
    offsets[9] = output.items.len;
    try output.appendSlice(allocator, "9 0 obj\n<< /Type /Page /Parent 2 0 R /Resources 12 0 R /MediaBox [0 0 1 1] /Contents 10 0 R >>\nendobj\n");
    offsets[10] = output.items.len;
    try output.print(allocator, "10 0 obj\n<< /Length {d} >>\nstream\n{s}endstream\nendobj\n", .{ image_content.len, image_content });
    offsets[11] = output.items.len;
    try output.appendSlice(allocator, "11 0 obj\n<< /XObject << /Im0 13 0 R >> >>\nendobj\n");
    offsets[12] = output.items.len;
    try output.appendSlice(allocator, "12 0 obj\n<< /XObject << /Im0 13 0 R >> >>\nendobj\n");
    offsets[13] = output.items.len;
    try output.print(allocator, "13 0 obj\n<< /Type /XObject /Subtype /Image /Width 1 /Height 1 /BitsPerComponent 8 /ColorSpace /DeviceRGB /Filter /DCTDecode /Length {d} >>\nstream\n", .{jpeg.len});
    try output.appendSlice(allocator, jpeg);
    try output.appendSlice(allocator, "\nendstream\nendobj\n");
    const xref_offset = output.items.len;
    try output.appendSlice(allocator, "xref\n0 14\n0000000000 65535 f \n");
    for (offsets[1..]) |offset| try output.print(allocator, "{d:0>10} 00000 n \n", .{offset});
    try output.print(allocator, "trailer\n<< /Size 14 /Root 1 0 R >>\nstartxref\n{d}\n%%EOF\n", .{xref_offset});
    return output.toOwnedSlice(allocator);
}

fn fixtureFormBoundaryPdf(allocator: std.mem.Allocator, jpeg: []const u8) ![]u8 {
    const form_content = "q\n/Im0 Do\nQ\n";
    const page_content = "q\n/Fm0 Do\nQ\n";
    const blank_content = "q\nQ\n";
    var output = std.ArrayList(u8).empty;
    errdefer output.deinit(allocator);
    var offsets: [16]usize = undefined;
    try output.appendSlice(allocator, "%PDF-1.7\n%\xE2\xE3\xCF\xD3\n");
    offsets[1] = output.items.len;
    try output.appendSlice(allocator, "1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n");
    offsets[2] = output.items.len;
    try output.appendSlice(allocator, "2 0 obj\n<< /Type /Pages /Kids [3 0 R 5 0 R 7 0 R 9 0 R] /Count 4 /Resources 11 0 R >>\nendobj\n");
    offsets[3] = output.items.len;
    try output.appendSlice(allocator, "3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 1 1] /Contents 4 0 R >>\nendobj\n");
    offsets[4] = output.items.len;
    try output.print(allocator, "4 0 obj\n<< /Length {d} >>\nstream\n{s}endstream\nendobj\n", .{ page_content.len, page_content });
    offsets[5] = output.items.len;
    try output.appendSlice(allocator, "5 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 1 1] >>\nendobj\n");
    offsets[6] = output.items.len;
    try output.print(allocator, "6 0 obj\n<< /Length {d} >>\nstream\n{s}endstream\nendobj\n", .{ blank_content.len, blank_content });
    offsets[7] = output.items.len;
    try output.appendSlice(allocator, "7 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 1 1] >>\nendobj\n");
    offsets[8] = output.items.len;
    try output.print(allocator, "8 0 obj\n<< /Length {d} >>\nstream\n{s}endstream\nendobj\n", .{ blank_content.len, blank_content });
    offsets[9] = output.items.len;
    try output.appendSlice(allocator, "9 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 1 1] /Contents 10 0 R >>\nendobj\n");
    offsets[10] = output.items.len;
    try output.print(allocator, "10 0 obj\n<< /Length {d} >>\nstream\n{s}endstream\nendobj\n", .{ page_content.len, page_content });
    offsets[11] = output.items.len;
    try output.appendSlice(allocator, "11 0 obj\n<< /XObject << /Fm0 13 0 R >> >>\nendobj\n");
    offsets[12] = output.items.len;
    try output.appendSlice(allocator, "12 0 obj\n<< /Unused true >>\nendobj\n");
    offsets[13] = output.items.len;
    try output.print(allocator, "13 0 obj\n<< /Type /XObject /Subtype /Form /FormType 1 /BBox [0 0 1 1] /Resources 14 0 R /Length {d} >>\nstream\n{s}endstream\nendobj\n", .{ form_content.len, form_content });
    offsets[14] = output.items.len;
    try output.appendSlice(allocator, "14 0 obj\n<< /XObject << /Im0 15 0 R >> >>\nendobj\n");
    offsets[15] = output.items.len;
    try output.print(allocator, "15 0 obj\n<< /Type /XObject /Subtype /Image /Width 1 /Height 1 /BitsPerComponent 8 /ColorSpace /DeviceRGB /Filter /DCTDecode /Length {d} >>\nstream\n", .{jpeg.len});
    try output.appendSlice(allocator, jpeg);
    try output.appendSlice(allocator, "\nendstream\nendobj\n");
    const xref_offset = output.items.len;
    try output.appendSlice(allocator, "xref\n0 16\n0000000000 65535 f \n");
    for (offsets[1..]) |offset| try output.print(allocator, "{d:0>10} 00000 n \n", .{offset});
    try output.print(allocator, "trailer\n<< /Size 16 /Root 1 0 R >>\nstartxref\n{d}\n%%EOF\n", .{xref_offset});
    return output.toOwnedSlice(allocator);
}

fn fixtureDirectResourceBoundaryPdf(allocator: std.mem.Allocator, jpeg: []const u8) ![]u8 {
    var output = std.ArrayList(u8).empty;
    errdefer output.deinit(allocator);
    var offsets: [14]usize = undefined;
    try output.appendSlice(allocator, "%PDF-1.7\n%\xE2\xE3\xCF\xD3\n");
    offsets[1] = output.items.len;
    try output.appendSlice(allocator, "1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n");
    offsets[2] = output.items.len;
    try output.appendSlice(allocator, "2 0 obj\n<< /Type /Pages /Kids [3 0 R 5 0 R 7 0 R 9 0 R] /Count 4 /Resources 11 0 R >>\nendobj\n");
    offsets[3] = output.items.len;
    try output.appendSlice(allocator, "3 0 obj\n<< /Type /Page /Parent 2 0 R /Resources 12 0 R /MediaBox [0 0 1 1] >>\nendobj\n");
    offsets[4] = output.items.len;
    try output.appendSlice(allocator, "4 0 obj\n<< /Unused true >>\nendobj\n");
    offsets[5] = output.items.len;
    try output.appendSlice(allocator, "5 0 obj\n<< /Type /Page /Parent 2 0 R /Resources << >> /MediaBox [0 0 1 1] >>\nendobj\n");
    offsets[6] = output.items.len;
    try output.appendSlice(allocator, "6 0 obj\n<< /Unused true >>\nendobj\n");
    offsets[7] = output.items.len;
    try output.appendSlice(allocator, "7 0 obj\n<< /Type /Page /Parent 2 0 R /Resources << >> /MediaBox [0 0 1 1] >>\nendobj\n");
    offsets[8] = output.items.len;
    try output.appendSlice(allocator, "8 0 obj\n<< /Unused true >>\nendobj\n");
    offsets[9] = output.items.len;
    try output.appendSlice(allocator, "9 0 obj\n<< /Type /Page /Parent 2 0 R /Resources 13 0 R /MediaBox [0 0 1 1] >>\nendobj\n");
    offsets[10] = output.items.len;
    try output.appendSlice(allocator, "10 0 obj\n<< /Unused true >>\nendobj\n");
    offsets[11] = output.items.len;
    try output.appendSlice(allocator, "11 0 obj\n<< /XObject << /Im0 14 0 R >> >>\nendobj\n");
    offsets[12] = output.items.len;
    try output.appendSlice(allocator, "12 0 obj\n<< /XObject << /Im0 14 0 R >> >>\nendobj\n");
    offsets[13] = output.items.len;
    try output.appendSlice(allocator, "13 0 obj\n<< /XObject << /Im0 14 0 R >> >>\nendobj\n");
    const image_offset = output.items.len;
    try output.print(allocator, "14 0 obj\n<< /Type /XObject /Subtype /Image /Width 1 /Height 1 /BitsPerComponent 8 /ColorSpace /DeviceRGB /Filter /DCTDecode /Length {d} >>\nstream\n", .{jpeg.len});
    try output.appendSlice(allocator, jpeg);
    try output.appendSlice(allocator, "\nendstream\nendobj\n");
    const xref_offset = output.items.len;
    try output.appendSlice(allocator, "xref\n0 15\n0000000000 65535 f \n");
    for (offsets[1..]) |offset| try output.print(allocator, "{d:0>10} 00000 n \n", .{offset});
    try output.print(allocator, "{d:0>10} 00000 n \ntrailer\n<< /Size 15 /Root 1 0 R >>\nstartxref\n{d}\n%%EOF\n", .{ image_offset, xref_offset });
    return output.toOwnedSlice(allocator);
}

fn ascii85Encode(allocator: std.mem.Allocator, bytes: []const u8) ![]u8 {
    var encoded = std.ArrayList(u8).empty;
    errdefer encoded.deinit(allocator);
    try encoded.appendSlice(allocator, "<~");

    var index: usize = 0;
    while (index + 4 <= bytes.len) : (index += 4) {
        var number: u32 = 0;
        for (bytes[index .. index + 4]) |value| number = (number << 8) | value;
        try appendAscii85Tuple(allocator, &encoded, number, 5);
    }

    const remaining = bytes.len - index;
    if (remaining != 0) {
        var number: u32 = 0;
        for (bytes[index..]) |value| number = (number << 8) | value;
        number <<= @intCast((4 - remaining) * 8);
        try appendAscii85Tuple(allocator, &encoded, number, remaining + 1);
    }

    try encoded.appendSlice(allocator, "~>");
    return encoded.toOwnedSlice(allocator);
}

fn appendAscii85Tuple(allocator: std.mem.Allocator, encoded: *std.ArrayList(u8), number: u32, count: usize) !void {
    if (number == 0 and count == 5) {
        try encoded.append(allocator, 'z');
        return;
    }

    var digits: [5]u8 = undefined;
    var value: u32 = number;
    var index: usize = digits.len;
    while (index > 0) {
        index -= 1;
        digits[index] = @intCast(value % 85 + '!');
        value /= 85;
    }
    try encoded.appendSlice(allocator, digits[0..count]);
}

fn fixtureAscii85Pdf(allocator: std.mem.Allocator, jpeg: []const u8) ![]u8 {
    const encoded = try ascii85Encode(allocator, jpeg);
    defer allocator.free(encoded);
    const content = "q\n/Im0 Do\nQ\n";

    var output = std.ArrayList(u8).empty;
    errdefer output.deinit(allocator);
    var offsets: [7]usize = undefined;
    try output.appendSlice(allocator, "%PDF-1.7\n%\xE2\xE3\xCF\xD3\n");
    offsets[1] = output.items.len;
    try output.appendSlice(allocator, "1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n");
    offsets[2] = output.items.len;
    try output.appendSlice(allocator, "2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n");
    offsets[3] = output.items.len;
    try output.appendSlice(allocator, "3 0 obj\n<< /Type /Page /Parent 2 0 R /Resources 4 0 R /MediaBox [0 0 1 1] /Contents 6 0 R >>\nendobj\n");
    offsets[4] = output.items.len;
    try output.appendSlice(allocator, "4 0 obj\n<< /XObject << /Im0 5 0 R >> >>\nendobj\n");
    offsets[5] = output.items.len;
    try output.print(allocator, "5 0 obj\n<< /Type /XObject /Subtype /Image /Width 1 /Height 1 /BitsPerComponent 8 /ColorSpace /DeviceRGB /Filter [/ASCII85Decode /DCTDecode] /Length {d} >>\nstream\n", .{encoded.len});
    try output.appendSlice(allocator, encoded);
    try output.appendSlice(allocator, "\nendstream\nendobj\n");
    offsets[6] = output.items.len;
    try output.print(allocator, "6 0 obj\n<< /Length {d} >>\nstream\n{s}endstream\nendobj\n", .{ content.len, content });
    const xref_offset = output.items.len;
    try output.appendSlice(allocator, "xref\n0 7\n0000000000 65535 f \n");
    for (offsets[1..]) |offset| try output.print(allocator, "{d:0>10} 00000 n \n", .{offset});
    try output.print(allocator, "trailer\n<< /Size 7 /Root 1 0 R >>\nstartxref\n{d}\n%%EOF\n", .{xref_offset});
    return output.toOwnedSlice(allocator);
}

fn fixtureVectorOnlyPdf(allocator: std.mem.Allocator) ![]u8 {
    const content = "q\n0 0 1 rg\n0 0 1 1 re\nf\nQ\n";
    var output = std.ArrayList(u8).empty;
    errdefer output.deinit(allocator);
    var offsets: [5]usize = undefined;
    try output.appendSlice(allocator, "%PDF-1.7\n%\xE2\xE3\xCF\xD3\n");
    offsets[1] = output.items.len;
    try output.print(allocator, "1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n", .{});
    offsets[2] = output.items.len;
    try output.print(allocator, "2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n", .{});
    offsets[3] = output.items.len;
    try output.print(allocator, "3 0 obj\n<< /Type /Page /Parent 2 0 R /Resources << >> /MediaBox [0 0 1 1] /Contents 4 0 R >>\nendobj\n", .{});
    offsets[4] = output.items.len;
    try output.print(allocator, "4 0 obj\n<< /Length {d} >>\nstream\n{s}endstream\nendobj\n", .{ content.len, content });
    const xref_offset = output.items.len;
    try output.appendSlice(allocator, "xref\n0 5\n0000000000 65535 f \n");
    for (offsets[1..]) |offset| try output.print(allocator, "{d:0>10} 00000 n \n", .{offset});
    try output.print(allocator, "trailer\n<< /Size 5 /Root 1 0 R >>\nstartxref\n{d}\n%%EOF\n", .{xref_offset});
    return output.toOwnedSlice(allocator);
}

fn testPath(tmp: *std.testing.TmpDir, allocator: std.mem.Allocator, name: []const u8) ![]u8 {
    return std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/{s}", .{ tmp.sub_path, name });
}

test "fixed image pipeline never upscales without AI" {
    const allocator = std.testing.allocator;
    const png = try fixturePng(allocator);
    defer allocator.free(png);
    const output = try image.encodeBytesFromMemory(allocator, std.testing.io, png, .{ .width = 1440, .quality = 80, .ai = false });
    defer allocator.free(output);
    const dimensions = try image.inspectMemory(output);
    try std.testing.expectEqual(@as(u32, 1), dimensions.width);
    try std.testing.expectEqual(@as(u32, 1), dimensions.height);
}

test "AI upscale reports unavailable without a backend" {
    const allocator = std.testing.allocator;
    const png = try fixturePng(allocator);
    defer allocator.free(png);
    try std.testing.expectError(
        error.AiUnavailable,
        image.encodeBytesFromMemory(allocator, std.testing.io, png, .{ .width = 1440, .quality = 80, .ai = true }),
    );
}

test "raw AI input below model minimum is rejected" {
    const allocator = std.testing.allocator;
    var raw_input: [4 * 4 * 3]u8 = undefined;
    var raw_width: u32 = 0;
    var raw_height: u32 = 0;
    try std.testing.expectError(
        error.InvalidResize,
        realesrgan.upscale(allocator, std.testing.io, &raw_input, 4, 4, 8, &raw_width, &raw_height),
    );
}

test "AI image conversion repeats safe 32x32 inference" {
    const allocator = std.testing.allocator;
    var raw_input: [32 * 32 * 3]u8 = undefined;
    for (&raw_input, 0..) |*pixel, index| pixel.* = @intCast((index * 5) % 256);

    var raw_width: u32 = 0;
    var raw_height: u32 = 0;
    const first = try realesrgan.upscale(allocator, std.testing.io, &raw_input, 32, 32, 64, &raw_width, &raw_height);
    defer allocator.free(first);
    try std.testing.expectEqual(@as(u32, 64), raw_width);
    try std.testing.expectEqual(@as(u32, 64), raw_height);
    try std.testing.expectEqual(@as(usize, 64 * 64 * 3), first.len);

    raw_width = 0;
    raw_height = 0;
    const second = try realesrgan.upscale(allocator, std.testing.io, &raw_input, 32, 32, 64, &raw_width, &raw_height);
    defer allocator.free(second);
    try std.testing.expectEqual(@as(u32, 64), raw_width);
    try std.testing.expectEqual(@as(u32, 64), raw_height);
    try std.testing.expectEqual(@as(usize, 64 * 64 * 3), second.len);
}

test "tiny AI image conversion uses normal resize below model minimum" {
    const allocator = std.testing.allocator;
    const png = try fixturePng(allocator);
    defer allocator.free(png);
    const jpeg = try image.encodeBytesFromMemory(allocator, std.testing.io, png, .{ .width = 2, .quality = 88, .ai = true });
    defer allocator.free(jpeg);
    try std.testing.expectEqualSlices(u8, "\xff\xd8", jpeg[0..2]);
    try std.testing.expectEqual(image.ImageInfo{ .width = 2, .height = 2 }, try image.inspectMemory(jpeg));
}

test "model config contains only fixed processing controls" {
    var model = main.Model{};
    var effects = main.Effects.init(std.testing.allocator);
    defer effects.deinit();
    effects.executor = .fake;
    main.update(&model, .toggle_ai, &effects);
    main.update(&model, .dir_pdf, &effects);
    try std.testing.expect(model.config.ai);
    try std.testing.expectEqual(protocol.DirMode.pdf, model.config.dir_mode);
    try std.testing.expectEqual(@as(u32, 1440), model.config.width);
}

test "progress displays the current target count" {
    var model = main.Model{};
    var effects = main.Effects.init(std.testing.allocator);
    defer effects.deinit();
    effects.executor = .fake;

    model.processing = true;
    model.process_total = 20;
    model.process_completed = 10;
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), model.progressValue(), 0.0001);
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectEqualStrings("변환 중... 10/20", model.processLabel(arena.allocator()));
}

test "zip memory writer round trips natural first image" {
    const allocator = std.testing.allocator;
    const jpeg = try fixtureJpeg(allocator);
    defer allocator.free(jpeg);
    const entries = [_]zip.ImageEntry{
        .{ .name = "page10.jpg", .bytes = jpeg },
        .{ .name = "notes.txt", .bytes = "ignored" },
        .{ .name = "page2.jpg", .bytes = jpeg },
    };
    const bytes = try zip.createMemory(allocator, &entries);
    defer allocator.free(bytes);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const path = try testPath(&tmp, allocator, "images.zip");
    defer allocator.free(path);
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "images.zip", .data = bytes });

    var archive = try zip.Archive.open(allocator, std.testing.io, path);
    defer archive.deinit();
    const first = archive.firstSupportedImage() orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("page2.jpg", first.name);
    const extracted = try archive.readEntry(first);
    defer allocator.free(extracted);
    try std.testing.expectEqualSlices(u8, jpeg, extracted);
}

test "zip input converts naturally sorted images to a PDF" {
    const allocator = std.testing.allocator;
    const jpeg = try fixtureJpeg(allocator);
    defer allocator.free(jpeg);
    const entries = [_]zip.ImageEntry{
        .{ .name = "page10.jpg", .bytes = jpeg },
        .{ .name = "notes.txt", .bytes = "ignored" },
        .{ .name = "page2.jpg", .bytes = jpeg },
    };
    const archive_bytes = try zip.createMemory(allocator, &entries);
    defer allocator.free(archive_bytes);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const archive_path = try testPath(&tmp, allocator, "images.zip");
    defer allocator.free(archive_path);
    const output_directory = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}", .{tmp.sub_path});
    defer allocator.free(output_directory);
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "images.zip", .data = archive_bytes });

    var progress: ProgressCounter = .{};
    var outputs = try operations.process(allocator, std.testing.io, .{
        .mode = .path,
        .path = output_directory,
        .width = 1,
        .quality = 80,
        .dir_mode = .pdf,
    }, archive_path, progress.reporter());
    defer outputs.deinit();
    try std.testing.expectEqual(@as(usize, 1), outputs.values.items.len);
    try std.testing.expectEqual(@as(usize, 2), progress.value);

    const pdf_path = outputs.values.items[0];
    const expected_pdf_path = try std.fs.path.join(allocator, &.{ output_directory, "images.pdf" });
    defer allocator.free(expected_pdf_path);
    try std.testing.expectEqualStrings(expected_pdf_path, pdf_path);

    try std.testing.expectEqual(@as(u32, 2), try pdf.pageCount(allocator, pdf_path));
}

test "zip writer rejects unsafe names" {
    const allocator = std.testing.allocator;
    const entries = [_]zip.ImageEntry{.{ .name = "../escape.jpg", .bytes = "bytes" }};
    try std.testing.expectError(error.UnsafeArchivePath, zip.createMemory(allocator, &entries));
}

test "zip path limits reject traversal" {
    try std.testing.expect(!zip.entryPathIsSafe("../escape.jpg"));
    try std.testing.expect(!zip.entryPathIsSafe("folder/../../escape.jpg"));
    try std.testing.expect(zip.entryPathIsSafe("folder\\image.jpg"));
}

test "pdf writer creates pages" {
    const allocator = std.testing.allocator;
    const jpeg = try fixtureJpeg(allocator);
    defer allocator.free(jpeg);
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const path = try testPath(&tmp, allocator, "images.pdf");
    defer allocator.free(path);
    var pages = [_]pdf.Page{.{ .bytes = jpeg, .width = 1, .height = 1 }};

    try pdf.createFromJpegs(allocator, std.testing.io, &pages, path);
    try std.testing.expectEqual(@as(u32, 1), try pdf.pageCount(allocator, path));
    var inspected = try operations.inspect(allocator, std.testing.io, path);
    defer operations.freeResponse(allocator, &inspected);
    try std.testing.expectEqual(protocol.Kind.pdf, inspected.kind);
    try std.testing.expectEqual(@as(u32, 1), inspected.count);
    try std.testing.expect(inspected.thumbnail_blob != null);
}

test "pdf input converts XObject images into a new PDF in page order" {
    const allocator = std.testing.allocator;
    const jpeg = try fixtureJpeg(allocator);
    defer allocator.free(jpeg);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const source_path = try testPath(&tmp, allocator, "source.pdf");
    defer allocator.free(source_path);
    const output_directory = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/output", .{tmp.sub_path});
    defer allocator.free(output_directory);
    try tmp.dir.createDirPath(std.testing.io, "output");

    const pages = [_]pdf.Page{
        .{ .bytes = jpeg, .width = 1, .height = 1 },
        .{ .bytes = jpeg, .width = 1, .height = 1 },
    };
    try pdf.createFromJpegs(allocator, std.testing.io, &pages, source_path);

    var progress: ProgressCounter = .{};
    var outputs = try operations.process(allocator, std.testing.io, .{
        .mode = .path,
        .path = output_directory,
        .width = 1,
        .quality = 80,
        .dir_mode = .pdf,
    }, source_path, progress.reporter());
    defer outputs.deinit();

    try std.testing.expectEqual(@as(usize, 1), outputs.values.items.len);
    try std.testing.expectEqual(@as(usize, 2), progress.value);
    try std.testing.expectEqual(@as(u32, 2), try pdf.pageCount(allocator, outputs.values.items[0]));
    try std.testing.expectEqual(@as(u32, 2), try pdf.imageCount(allocator, outputs.values.items[0]));
}

test "pdf input converts Flate image XObjects" {
    const allocator = std.testing.allocator;
    const bytes = try fixtureFlatePdf(allocator);
    defer allocator.free(bytes);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const source_path = try testPath(&tmp, allocator, "source.pdf");
    defer allocator.free(source_path);
    const output_directory = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/output", .{tmp.sub_path});
    defer allocator.free(output_directory);
    try tmp.dir.createDirPath(std.testing.io, "output");
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "source.pdf", .data = bytes });

    var progress: ProgressCounter = .{};
    var outputs = try operations.process(allocator, std.testing.io, .{
        .mode = .path,
        .path = output_directory,
        .width = 1,
        .quality = 80,
        .dir_mode = .pdf,
    }, source_path, progress.reporter());
    defer outputs.deinit();

    try std.testing.expectEqual(@as(usize, 1), outputs.values.items.len);
    try std.testing.expectEqual(@as(usize, 1), progress.value);
    try std.testing.expectEqual(@as(u32, 1), try pdf.pageCount(allocator, outputs.values.items[0]));
}

test "pdf input converts ASCII85 wrapped JPEG image XObjects" {
    const allocator = std.testing.allocator;
    const jpeg = try fixtureJpeg(allocator);
    defer allocator.free(jpeg);
    const bytes = try fixtureAscii85Pdf(allocator, jpeg);
    defer allocator.free(bytes);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const source_path = try testPath(&tmp, allocator, "source.pdf");
    defer allocator.free(source_path);
    const output_directory = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/output", .{tmp.sub_path});
    defer allocator.free(output_directory);
    try tmp.dir.createDirPath(std.testing.io, "output");
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "source.pdf", .data = bytes });

    var progress: ProgressCounter = .{};
    var outputs = try operations.process(allocator, std.testing.io, .{
        .mode = .path,
        .path = output_directory,
        .width = 1,
        .quality = 80,
        .dir_mode = .pdf,
    }, source_path, progress.reporter());
    defer outputs.deinit();

    try std.testing.expectEqual(@as(usize, 1), outputs.values.items.len);
    try std.testing.expectEqual(@as(usize, 1), progress.value);
    try std.testing.expectEqual(@as(u32, 1), try pdf.pageCount(allocator, outputs.values.items[0]));
}

test "pdf input keeps images before and after blank interior pages" {
    const allocator = std.testing.allocator;
    const jpeg = try fixtureJpeg(allocator);
    defer allocator.free(jpeg);
    const bytes = try fixtureBlankInteriorPdf(allocator, jpeg);
    defer allocator.free(bytes);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const source_path = try testPath(&tmp, allocator, "source.pdf");
    defer allocator.free(source_path);
    const output_directory = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/output", .{tmp.sub_path});
    defer allocator.free(output_directory);
    try tmp.dir.createDirPath(std.testing.io, "output");
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "source.pdf", .data = bytes });

    var inspected = try operations.inspect(allocator, std.testing.io, source_path);
    defer operations.freeResponse(allocator, &inspected);
    try std.testing.expectEqual(@as(u32, 4), inspected.count);
    try std.testing.expect(inspected.thumbnail_blob != null);

    var progress: ProgressCounter = .{};
    var outputs = try operations.process(allocator, std.testing.io, .{
        .mode = .path,
        .path = output_directory,
        .width = 1,
        .quality = 80,
        .dir_mode = .pdf,
    }, source_path, progress.reporter());
    defer outputs.deinit();

    try std.testing.expectEqual(@as(usize, 1), outputs.values.items.len);
    try std.testing.expectEqual(@as(usize, 4), progress.value);
    try std.testing.expectEqual(@as(u32, 4), try pdf.pageCount(allocator, outputs.values.items[0]));
}

test "pdf input keeps boundary images inside form XObjects" {
    const allocator = std.testing.allocator;
    const jpeg = try fixtureJpeg(allocator);
    defer allocator.free(jpeg);
    const bytes = try fixtureFormBoundaryPdf(allocator, jpeg);
    defer allocator.free(bytes);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const source_path = try testPath(&tmp, allocator, "source.pdf");
    defer allocator.free(source_path);
    const output_directory = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/output", .{tmp.sub_path});
    defer allocator.free(output_directory);
    try tmp.dir.createDirPath(std.testing.io, "output");
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "source.pdf", .data = bytes });

    var inspected = try operations.inspect(allocator, std.testing.io, source_path);
    defer operations.freeResponse(allocator, &inspected);
    try std.testing.expectEqual(@as(u32, 4), inspected.count);
    try std.testing.expect(inspected.thumbnail_blob != null);

    var progress: ProgressCounter = .{};
    var outputs = try operations.process(allocator, std.testing.io, .{
        .mode = .path,
        .path = output_directory,
        .width = 1,
        .quality = 80,
        .dir_mode = .pdf,
    }, source_path, progress.reporter());
    defer outputs.deinit();

    try std.testing.expectEqual(@as(usize, 1), outputs.values.items.len);
    try std.testing.expectEqual(@as(usize, 4), progress.value);
    try std.testing.expectEqual(@as(u32, 4), try pdf.pageCount(allocator, outputs.values.items[0]));
}

test "pdf input keeps direct resource images without page streams" {
    const allocator = std.testing.allocator;
    const jpeg = try fixtureJpeg(allocator);
    defer allocator.free(jpeg);
    const bytes = try fixtureDirectResourceBoundaryPdf(allocator, jpeg);
    defer allocator.free(bytes);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const source_path = try testPath(&tmp, allocator, "source.pdf");
    defer allocator.free(source_path);
    const output_directory = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/output", .{tmp.sub_path});
    defer allocator.free(output_directory);
    try tmp.dir.createDirPath(std.testing.io, "output");
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "source.pdf", .data = bytes });

    var inspected = try operations.inspect(allocator, std.testing.io, source_path);
    defer operations.freeResponse(allocator, &inspected);
    try std.testing.expectEqual(@as(u32, 4), inspected.count);
    try std.testing.expect(inspected.thumbnail_blob != null);

    var progress: ProgressCounter = .{};
    var outputs = try operations.process(allocator, std.testing.io, .{
        .mode = .path,
        .path = output_directory,
        .width = 1,
        .quality = 80,
        .dir_mode = .pdf,
    }, source_path, progress.reporter());
    defer outputs.deinit();

    try std.testing.expectEqual(@as(usize, 1), outputs.values.items.len);
    try std.testing.expectEqual(@as(usize, 4), progress.value);
    try std.testing.expectEqual(@as(u32, 4), try pdf.pageCount(allocator, outputs.values.items[0]));
}

test "pdf pages use page names for individual and zip output" {
    const allocator = std.testing.allocator;
    const jpeg = try fixtureJpeg(allocator);
    defer allocator.free(jpeg);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const source_path = try testPath(&tmp, allocator, "source.pdf");
    defer allocator.free(source_path);
    const jpg_output_directory = try testPath(&tmp, allocator, "jpg");
    defer allocator.free(jpg_output_directory);
    const zip_output_directory = try testPath(&tmp, allocator, "zip");
    defer allocator.free(zip_output_directory);
    try tmp.dir.createDirPath(std.testing.io, "jpg");
    try tmp.dir.createDirPath(std.testing.io, "zip");

    const pages = [_]pdf.Page{
        .{ .bytes = jpeg, .width = 1, .height = 1 },
        .{ .bytes = jpeg, .width = 1, .height = 1 },
    };
    try pdf.createFromJpegs(allocator, std.testing.io, &pages, source_path);

    var jpg_progress: ProgressCounter = .{};
    var jpg_outputs = try operations.process(allocator, std.testing.io, .{
        .mode = .path,
        .path = jpg_output_directory,
        .width = 1,
        .quality = 80,
    }, source_path, jpg_progress.reporter());
    defer jpg_outputs.deinit();
    try std.testing.expectEqual(@as(usize, 2), jpg_outputs.values.items.len);
    try std.testing.expectEqual(@as(usize, 2), jpg_progress.value);
    try std.testing.expectEqualStrings("1.jpg", std.fs.path.basename(jpg_outputs.values.items[0]));
    try std.testing.expectEqualStrings("2.jpg", std.fs.path.basename(jpg_outputs.values.items[1]));

    var zip_progress: ProgressCounter = .{};
    var zip_outputs = try operations.process(allocator, std.testing.io, .{
        .mode = .path,
        .path = zip_output_directory,
        .width = 1,
        .quality = 80,
        .dir_mode = .zip,
    }, source_path, zip_progress.reporter());
    defer zip_outputs.deinit();
    try std.testing.expectEqual(@as(usize, 1), zip_outputs.values.items.len);
    try std.testing.expectEqual(@as(usize, 2), zip_progress.value);
    var archive = try zip.Archive.open(allocator, std.testing.io, zip_outputs.values.items[0]);
    defer archive.deinit();
    try std.testing.expectEqual(@as(u32, 2), archive.file_count);
    try std.testing.expectEqualStrings("1.jpg", archive.entries[0].name);
    try std.testing.expectEqualStrings("2.jpg", archive.entries[1].name);
}

test "pdf thumbnail reads a Flate encoded RGB image XObject" {
    const allocator = std.testing.allocator;
    const bytes = try fixtureFlatePdf(allocator);
    defer allocator.free(bytes);
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const path = try testPath(&tmp, allocator, "flate.pdf");
    defer allocator.free(path);
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "flate.pdf", .data = bytes });
    const thumbnail = (try pdf.thumbnailBytes(allocator, path)) orelse return error.TestUnexpectedResult;
    defer allocator.free(thumbnail);
    try std.testing.expect(thumbnail.len != 0);
    const dimensions = try image.inspectMemory(thumbnail);
    try std.testing.expectEqual(@as(u32, 1), dimensions.width);
    try std.testing.expectEqual(@as(u32, 1), dimensions.height);
}

test "pdf thumbnail uses the first supported image" {
    const allocator = std.testing.allocator;
    const jpeg = try fixtureJpeg(allocator);
    defer allocator.free(jpeg);
    const bytes = try fixtureMixedPdf(allocator, jpeg);
    defer allocator.free(bytes);
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const path = try testPath(&tmp, allocator, "mixed.pdf");
    defer allocator.free(path);
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "mixed.pdf", .data = bytes });
    const thumbnail = (try pdf.thumbnailBytes(allocator, path)) orelse return error.TestUnexpectedResult;
    defer allocator.free(thumbnail);
    const dimensions = try image.inspectMemory(thumbnail);
    try std.testing.expectEqual(@as(u32, 2), dimensions.width);
    try std.testing.expectEqual(@as(u32, 1), dimensions.height);
    const pixels = [_]u8{ 255, 0, 0, 255, 0, 0 };
    const expected = try image.thumbnailBytesFromRgb(allocator, 2, 1, &pixels);
    defer allocator.free(expected);
    try std.testing.expectEqualSlices(u8, expected, thumbnail);
}

test "pdf thumbnail only uses the first page image XObject" {
    const allocator = std.testing.allocator;
    const jpeg = try fixtureJpeg(allocator);
    defer allocator.free(jpeg);
    const bytes = try fixtureCrossPagePdf(allocator, jpeg);
    defer allocator.free(bytes);
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const path = try testPath(&tmp, allocator, "cross-page.pdf");
    defer allocator.free(path);
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "cross-page.pdf", .data = bytes });
    try std.testing.expectEqual(@as(u32, 2), try pdf.pageCount(allocator, path));
    var inspected = try operations.inspect(allocator, std.testing.io, path);
    defer operations.freeResponse(allocator, &inspected);
    try std.testing.expectEqual(protocol.Kind.pdf, inspected.kind);
    try std.testing.expectEqual(@as(u32, 2), inspected.count);
    try std.testing.expect(inspected.thumbnail_blob == null);
}

test "pdf inspection succeeds without a supported image preview" {
    const allocator = std.testing.allocator;
    const bytes = try fixtureVectorOnlyPdf(allocator);
    defer allocator.free(bytes);
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const path = try testPath(&tmp, allocator, "vector-only.pdf");
    defer allocator.free(path);
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "vector-only.pdf", .data = bytes });
    var inspected = try operations.inspect(allocator, std.testing.io, path);
    defer operations.freeResponse(allocator, &inspected);
    try std.testing.expectEqual(protocol.Kind.pdf, inspected.kind);
    try std.testing.expectEqual(@as(u32, 1), inspected.count);
    try std.testing.expect(inspected.thumbnail_blob == null);
}

test "folder inspection keeps images and ignores nonimage files" {
    const allocator = std.testing.allocator;
    const png = try fixturePng(allocator);
    defer allocator.free(png);
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(std.testing.io, "photos");
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "photos/first.png", .data = png });
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "photos/broken.bmp", .data = "BM" });
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "photos/unsupported.webp", .data = "RIFF0000WEBP" });
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "photos/notes.txt", .data = "ignore" });
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "photos/broken.pdf", .data = "not a pdf" });
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "photos/broken.zip", .data = "not a zip" });
    try tmp.dir.createDirPath(std.testing.io, "photos/empty");
    const path = try testPath(&tmp, allocator, "photos");
    defer allocator.free(path);
    var response = try operations.inspect(allocator, std.testing.io, path);
    defer operations.freeResponse(allocator, &response);
    try std.testing.expectEqual(protocol.Kind.directory, response.kind);
    try std.testing.expectEqual(@as(u32, 1), response.count);
    try std.testing.expectEqual(@as(usize, 1), response.children.len);
    try std.testing.expectEqualStrings("first.png", response.children[0].name);
    try std.testing.expect(response.thumbnail != null);
}

test "folder preview uses the first image in the flattened tree" {
    const allocator = std.testing.allocator;
    const png = try fixturePng(allocator);
    defer allocator.free(png);
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(std.testing.io, "photos/nested");
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "photos/nested/first.png", .data = png });
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "photos/second.png", .data = png });
    const path = try testPath(&tmp, allocator, "photos");
    defer allocator.free(path);
    const first_path = try testPath(&tmp, allocator, "photos/nested/first.png");
    defer allocator.free(first_path);

    var response = try operations.inspect(allocator, std.testing.io, path);
    defer operations.freeResponse(allocator, &response);
    try std.testing.expectEqual(@as(u32, 2), response.count);
    try std.testing.expectEqualStrings(first_path, response.thumbnail.?);
}

test "direct image batches follow PDF and ZIP modes" {
    const allocator = std.testing.allocator;
    const png = try fixturePng(allocator);
    defer allocator.free(png);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(std.testing.io, "pdf");
    try tmp.dir.createDirPath(std.testing.io, "zip");

    const first_path = try testPath(&tmp, allocator, "first.png");
    defer allocator.free(first_path);
    const second_path = try testPath(&tmp, allocator, "second.png");
    defer allocator.free(second_path);
    const pdf_output_directory = try testPath(&tmp, allocator, "pdf");
    defer allocator.free(pdf_output_directory);
    const zip_output_directory = try testPath(&tmp, allocator, "zip");
    defer allocator.free(zip_output_directory);
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "first.png", .data = png });
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "second.png", .data = png });

    const sources = [_]protocol.Source{
        .{ .path = first_path, .name = "first.png", .root = first_path, .kind = .image },
        .{ .path = second_path, .name = "second.png", .root = second_path, .kind = .image },
    };
    var pdf_progress: ProgressCounter = .{};
    var pdf_outputs = try operations.processSources(allocator, std.testing.io, .{
        .mode = .path,
        .path = pdf_output_directory,
        .width = 1,
        .quality = 80,
        .dir_mode = .pdf,
    }, &sources, pdf_progress.reporter());
    defer pdf_outputs.deinit();
    try std.testing.expectEqual(@as(usize, 1), pdf_outputs.values.items.len);
    try std.testing.expectEqual(@as(usize, 2), pdf_progress.value);
    try std.testing.expectEqual(@as(u32, 2), try pdf.pageCount(allocator, pdf_outputs.values.items[0]));

    var zip_progress: ProgressCounter = .{};
    var zip_outputs = try operations.processSources(allocator, std.testing.io, .{
        .mode = .path,
        .path = zip_output_directory,
        .width = 1,
        .quality = 80,
        .dir_mode = .zip,
    }, &sources, zip_progress.reporter());
    defer zip_outputs.deinit();
    try std.testing.expectEqual(@as(usize, 1), zip_outputs.values.items.len);
    try std.testing.expectEqual(@as(usize, 2), zip_progress.value);
    var archive = try zip.Archive.open(allocator, std.testing.io, zip_outputs.values.items[0]);
    defer archive.deinit();
    try std.testing.expectEqual(@as(u32, 2), archive.file_count);
}

test "model combines folders and direct files for PDF and ZIP output" {
    const allocator = std.testing.allocator;
    const png = try fixturePng(allocator);
    defer allocator.free(png);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(std.testing.io, "pdf");
    try tmp.dir.createDirPath(std.testing.io, "zip");
    try tmp.dir.createDirPath(std.testing.io, "folder");
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "folder/inside.png", .data = png });
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "second.png", .data = png });

    const folder_path = try testPath(&tmp, allocator, "folder");
    defer allocator.free(folder_path);
    const second_path = try testPath(&tmp, allocator, "second.png");
    defer allocator.free(second_path);
    const selected = try std.fmt.allocPrint(allocator, "{s}\n{s}", .{ folder_path, second_path });
    defer allocator.free(selected);
    const pdf_output_directory = try testPath(&tmp, allocator, "pdf");
    defer allocator.free(pdf_output_directory);
    const zip_output_directory = try testPath(&tmp, allocator, "zip");
    defer allocator.free(zip_output_directory);

    var pool: main.JobPool = undefined;
    pool.init(allocator, std.testing.io);
    defer pool.deinit();
    var fx = main.Effects.init(allocator);
    defer fx.deinit();
    fx.executor = .fake;
    fx.fake_instant_image_bytes = png;

    var model = main.Model{ .job_pool = &pool };
    main.update(&model, .{ .dialog_ready = .{ .paths = selected, .count = 2 } }, &fx);

    var steps: usize = 0;
    while ((model.inspecting or model.thumbnail_pending != 0) and steps < 1000) : (steps += 1) {
        if (fx.takeMsg()) |message| {
            main.update(&model, message, &fx);
        } else {
            try std.Io.sleep(std.testing.io, std.Io.Duration.fromMilliseconds(1), .awake);
        }
    }
    try std.testing.expect(steps < 1000);
    try std.testing.expectEqual(@as(usize, 2), model.root_count);

    main.Model.copyPath(&model.output_storage, &model.output_len, pdf_output_directory);
    model.config.mode = .path;
    model.config.width = 1;
    model.config.quality = 80;
    model.config.dir_mode = .pdf;
    main.update(&model, .process, &fx);
    try std.testing.expectEqual(@as(usize, 2), model.process_total);
    try std.testing.expectEqual(@as(usize, 2), model.process_source_count);

    steps = 0;
    while (model.processing and steps < 1000) : (steps += 1) {
        if (fx.takeMsg()) |message| {
            main.update(&model, message, &fx);
        } else {
            try std.Io.sleep(std.testing.io, std.Io.Duration.fromMilliseconds(1), .awake);
        }
    }
    try std.testing.expect(steps < 1000);
    try std.testing.expect(!model.processing);
    try std.testing.expectEqual(@as(usize, 1), model.output_count);
    try std.testing.expectEqual(@as(usize, 2), model.process_completed);
    try std.testing.expectEqualStrings("folder.pdf", std.fs.path.basename(model.output_last_storage[0..model.output_last_len]));
    try std.testing.expectEqual(@as(u32, 2), try pdf.pageCount(allocator, model.output_last_storage[0..model.output_last_len]));

    main.Model.copyPath(&model.output_storage, &model.output_len, zip_output_directory);
    model.config.dir_mode = .zip;
    main.update(&model, .process, &fx);

    steps = 0;
    while (model.processing and steps < 1000) : (steps += 1) {
        if (fx.takeMsg()) |message| {
            main.update(&model, message, &fx);
        } else {
            try std.Io.sleep(std.testing.io, std.Io.Duration.fromMilliseconds(1), .awake);
        }
    }
    try std.testing.expect(steps < 1000);
    try std.testing.expect(!model.processing);
    try std.testing.expectEqual(@as(usize, 1), model.output_count);
    try std.testing.expectEqualStrings("folder.zip", std.fs.path.basename(model.output_last_storage[0..model.output_last_len]));
    var archive = try zip.Archive.open(allocator, std.testing.io, model.output_last_storage[0..model.output_last_len]);
    defer archive.deinit();
    try std.testing.expectEqual(@as(u32, 2), archive.file_count);
}

test "model rejects a PDF mixed with multiple selected files" {
    var model = main.Model{};
    var fx = main.Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    main.update(&model, .{ .dialog_ready = .{ .paths = "/tmp/source.pdf\n/tmp/image.png", .count = 2 } }, &fx);

    try std.testing.expectEqual(@as(usize, 0), model.root_count);
    try std.testing.expectEqualStrings("PDF는 한 번에 하나만 선택할 수 있습니다", model.errorText());
}

test "folder with 16 or more images completes inspection and processing" {
    const allocator = std.testing.allocator;
    const png = try fixturePng(allocator);
    defer allocator.free(png);
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(std.testing.io, "photos");
    var pool: main.JobPool = undefined;
    pool.init(allocator, std.testing.io);
    defer pool.deinit();
    const image_count = @max(@as(usize, 16), pool.parallelism + 1);
    for (0..image_count) |index| {
        const name = try std.fmt.allocPrint(allocator, "photos/image{d:0>2}.png", .{index});
        defer allocator.free(name);
        try tmp.dir.writeFile(std.testing.io, .{ .sub_path = name, .data = png });
    }
    const path = try testPath(&tmp, allocator, "photos");
    defer allocator.free(path);
    const output_directory = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}", .{tmp.sub_path});
    defer allocator.free(output_directory);
    const direct_output_directory = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/direct", .{tmp.sub_path});
    defer allocator.free(direct_output_directory);
    const pdf_output_directory = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/pdf", .{tmp.sub_path});
    defer allocator.free(pdf_output_directory);
    const zip_output_directory = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/zip", .{tmp.sub_path});
    defer allocator.free(zip_output_directory);
    try tmp.dir.createDirPath(std.testing.io, "direct");
    try tmp.dir.createDirPath(std.testing.io, "pdf");
    try tmp.dir.createDirPath(std.testing.io, "zip");

    var inspected = try operations.inspect(allocator, std.testing.io, path);
    defer operations.freeResponse(allocator, &inspected);
    try std.testing.expectEqual(protocol.Kind.directory, inspected.kind);
    try std.testing.expectEqual(@as(u32, @intCast(image_count)), inspected.count);
    try std.testing.expectEqual(image_count, inspected.children.len);
    var direct_progress: ProgressCounter = .{};
    var direct_outputs = try operations.process(allocator, std.testing.io, .{
        .mode = .path,
        .path = direct_output_directory,
        .width = 1,
        .quality = 80,
        .dir_mode = .none,
    }, path, direct_progress.reporter());
    defer direct_outputs.deinit();
    try std.testing.expectEqual(image_count, direct_outputs.values.items.len);
    try std.testing.expectEqual(image_count, direct_progress.value);
    var pdf_progress: ProgressCounter = .{};
    var pdf_outputs = try operations.process(allocator, std.testing.io, .{
        .mode = .path,
        .path = pdf_output_directory,
        .width = 1,
        .quality = 80,
        .dir_mode = .pdf,
    }, path, pdf_progress.reporter());
    defer pdf_outputs.deinit();
    try std.testing.expectEqual(@as(usize, 1), pdf_outputs.values.items.len);
    try std.testing.expectEqual(image_count, pdf_progress.value);
    try std.testing.expectEqual(@as(u32, @intCast(image_count)), try pdf.pageCount(allocator, pdf_outputs.values.items[0]));
    var zip_progress: ProgressCounter = .{};
    var zip_outputs = try operations.process(allocator, std.testing.io, .{
        .mode = .path,
        .path = zip_output_directory,
        .width = 1,
        .quality = 80,
        .dir_mode = .zip,
    }, path, zip_progress.reporter());
    defer zip_outputs.deinit();
    try std.testing.expectEqual(@as(usize, 1), zip_outputs.values.items.len);
    try std.testing.expectEqual(image_count, zip_progress.value);
    var archive = try zip.Archive.open(allocator, std.testing.io, zip_outputs.values.items[0]);
    defer archive.deinit();
    try std.testing.expectEqual(image_count, archive.file_count);

    var fx = main.Effects.init(allocator);
    defer fx.deinit();
    fx.executor = .fake;
    var model = main.Model{ .job_pool = &pool };
    main.update(&model, .{ .dialog_ready = .{ .paths = path, .count = 1 } }, &fx);

    var steps: usize = 0;
    while (model.inspecting and steps < 1000) : (steps += 1) {
        if (fx.takeMsg()) |message| {
            main.update(&model, message, &fx);
        } else {
            try std.Io.sleep(std.testing.io, std.Io.Duration.fromMilliseconds(1), .awake);
        }
    }
    try std.testing.expect(steps < 1000);
    try std.testing.expectEqual(@as(usize, 1), model.root_count);
    try std.testing.expectEqual(image_count + 1, model.item_count);
    try std.testing.expectEqual(@as(u32, @intCast(image_count)), model.items[0].count);
    try std.testing.expect(!model.inspecting);
    try std.testing.expectEqual(@as(usize, 1), model.thumbnail_pending);
    for (model.items[1..model.item_count]) |item| try std.testing.expectEqual(@as(u64, 0), item.thumbnail_id);
    main.Model.copyPath(&model.output_storage, &model.output_len, output_directory);
    try std.testing.expect(model.canProcess());

    model.config.mode = .path;
    model.config.width = 1;
    model.config.quality = 80;
    main.update(&model, .process, &fx);
    try std.testing.expectEqual(image_count, model.process_total);
    steps = 0;
    while (model.processing and steps < 1000) : (steps += 1) {
        if (fx.takeMsg()) |message| {
            main.update(&model, message, &fx);
        } else {
            try std.Io.sleep(std.testing.io, std.Io.Duration.fromMilliseconds(1), .awake);
        }
    }
    try std.testing.expect(steps < 1000);
    try std.testing.expectEqual(image_count, model.output_count);
    try std.testing.expectEqual(image_count, model.process_completed);
    try std.testing.expect(!model.processing);
}

test "dialog and drop replace inspected roots and their trees" {
    const allocator = std.testing.allocator;
    const png = try fixturePng(allocator);
    defer allocator.free(png);
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(std.testing.io, "folder");
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "folder/inside.png", .data = png });
    const folder_path = try testPath(&tmp, allocator, "folder");
    defer allocator.free(folder_path);
    const image_path = try testPath(&tmp, allocator, "single.png");
    defer allocator.free(image_path);
    const output_directory = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}", .{tmp.sub_path});
    defer allocator.free(output_directory);
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "single.png", .data = png });

    var pool: main.JobPool = undefined;
    pool.init(allocator, std.testing.io);
    defer pool.deinit();
    var fx = main.Effects.init(allocator);
    defer fx.deinit();
    fx.executor = .fake;
    fx.fake_instant_image_bytes = png;
    var model = main.Model{ .job_pool = &pool };
    model.dialog = .files;
    main.update(&model, .{ .dialog_ready = .{ .paths = folder_path, .count = 1 } }, &fx);

    var steps: usize = 0;
    while ((model.inspecting or model.thumbnail_pending != 0) and steps < 1000) : (steps += 1) {
        if (fx.takeMsg()) |message| {
            main.update(&model, message, &fx);
        } else {
            try std.Io.sleep(std.testing.io, std.Io.Duration.fromMilliseconds(1), .awake);
        }
    }
    try std.testing.expect(steps < 1000);
    try std.testing.expectEqual(@as(usize, 1), model.root_count);
    try std.testing.expectEqual(@as(usize, 2), model.item_count);
    try std.testing.expect(model.items[0].thumbnail().len != 0);
    try std.testing.expect(model.items[1].thumbnail().len != 0);
    try std.testing.expectEqual(@as(u32, 1), model.items[0].count);
    try std.testing.expectEqual(protocol.Kind.image, model.items[1].kind);

    main.update(&model, .{ .dropped = .{ .paths = &.{image_path} } }, &fx);
    steps = 0;
    while ((model.inspecting or model.thumbnail_pending != 0) and steps < 1000) : (steps += 1) {
        if (fx.takeMsg()) |message| {
            main.update(&model, message, &fx);
        } else {
            try std.Io.sleep(std.testing.io, std.Io.Duration.fromMilliseconds(1), .awake);
        }
    }
    try std.testing.expect(steps < 1000);
    try std.testing.expectEqual(@as(usize, 1), model.root_count);
    try std.testing.expectEqual(@as(usize, 1), model.item_count);
    try std.testing.expectEqual(protocol.Kind.image, model.items[0].kind);
    try std.testing.expectEqualStrings(image_path, model.items[0].path());

    main.Model.copyPath(&model.output_storage, &model.output_len, output_directory);
    model.config.mode = .path;
    model.config.width = 1;
    model.config.quality = 80;
    main.update(&model, .process, &fx);
    steps = 0;
    while ((model.processing or model.thumbnail_pending != 0) and steps < 1000) : (steps += 1) {
        if (fx.takeMsg()) |message| {
            main.update(&model, message, &fx);
        } else {
            try std.Io.sleep(std.testing.io, std.Io.Duration.fromMilliseconds(1), .awake);
        }
    }
    try std.testing.expect(steps < 1000);
    try std.testing.expectEqual(@as(usize, 1), model.output_count);
    try std.testing.expect(!model.processing);

    main.update(&model, .{ .remove_file = 0 }, &fx);
    try std.testing.expectEqual(@as(usize, 0), model.root_count);
    try std.testing.expectEqual(@as(usize, 0), model.item_count);
    try std.testing.expectEqual(@as(usize, 0), model.thumbnail_pending);
}
