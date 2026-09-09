const std = @import("std");

const c = @import("ffmpeg");

const Frame = c.AVFrame;
const Packet = c.AVPacket;
const CodecContext = c.AVCodecContext;
const FormatContext = c.AVFormatContext;
const Stream = c.AVStream;
const Codec = c.AVCodec;
const SwsContext = c.SwsContext;

pub const Processor = struct {
    allocator: std.mem.Allocator,
    io: std.Io,

    pub fn convertMp4ToGif(self: Processor, source: []const u8, destination: []const u8) !void {
        if (source.len == 0 or destination.len == 0 or
            std.mem.indexOfScalar(u8, source, 0) != null or
            std.mem.indexOfScalar(u8, destination, 0) != null) return error.InvalidPath;

        const source_stat = std.Io.Dir.cwd().statFile(self.io, source, .{ .follow_symlinks = false }) catch return error.SourceNotFound;
        if (source_stat.kind == .sym_link or source_stat.kind != .file) return error.InvalidVideoSource;

        const source_z = try self.allocator.dupeZ(u8, source);
        defer self.allocator.free(source_z);
        const destination_z = try self.allocator.dupeZ(u8, destination);
        defer self.allocator.free(destination_z);

        var input: [*c]FormatContext = null;
        defer if (input != null) c.avformat_close_input(&input);
        if (c.avformat_open_input(&input, source_z.ptr, null, null) < 0 or input == null) return error.Ffmpeg;
        if (c.avformat_find_stream_info(input, null) < 0) return error.Ffmpeg;

        var decoder_codec: [*c]const Codec = null;
        const video_index = c.av_find_best_stream(input, c.AVMEDIA_TYPE_VIDEO, -1, -1, &decoder_codec, 0);
        if (video_index < 0 or decoder_codec == null) return error.UnsupportedVideo;
        const input_stream: [*c]Stream = input.*.streams[@intCast(video_index)];
        if (input_stream == null or input_stream.*.codecpar == null) return error.Ffmpeg;

        var decoder: [*c]CodecContext = null;
        defer if (decoder != null) c.avcodec_free_context(&decoder);
        decoder = c.avcodec_alloc_context3(decoder_codec);
        if (decoder == null) return error.OutOfMemory;
        if (c.avcodec_parameters_to_context(decoder, input_stream.*.codecpar) < 0) return error.Ffmpeg;
        if (c.avcodec_open2(decoder, decoder_codec, null) < 0) return error.Ffmpeg;
        if (decoder.*.width <= 0 or decoder.*.height <= 0) return error.InvalidVideo;

        const encoder_codec: [*c]const Codec = c.avcodec_find_encoder(@intCast(c.AV_CODEC_ID_GIF));
        if (encoder_codec == null) return error.GifEncoderUnavailable;

        var output: [*c]FormatContext = null;
        defer {
            if (output != null) {
                if (output.*.pb != null) _ = c.avio_closep(&output.*.pb);
                c.avformat_free_context(output);
            }
        }
        const gif_format = "gif";
        if (c.avformat_alloc_output_context2(&output, null, gif_format, destination_z.ptr) < 0 or output == null) return error.Ffmpeg;

        const output_stream: [*c]Stream = c.avformat_new_stream(output, null);
        if (output_stream == null or output_stream.*.codecpar == null) return error.OutOfMemory;

        var encoder: [*c]CodecContext = null;
        defer if (encoder != null) c.avcodec_free_context(&encoder);
        encoder = c.avcodec_alloc_context3(encoder_codec);
        if (encoder == null) return error.OutOfMemory;
        encoder.*.codec_id = @intCast(c.AV_CODEC_ID_GIF);
        encoder.*.codec_type = c.AVMEDIA_TYPE_VIDEO;
        encoder.*.width = decoder.*.width;
        encoder.*.height = decoder.*.height;
        encoder.*.pix_fmt = @intCast(c.AV_PIX_FMT_RGB8);
        encoder.*.time_base = validTimeBase(input_stream.*.time_base) orelse .{ .num = 1, .den = 25 };
        encoder.*.framerate = c.av_guess_frame_rate(input, input_stream, null);
        if (validTimeBase(encoder.*.framerate) == null) encoder.*.framerate = .{ .num = 25, .den = 1 };
        encoder.*.gop_size = 12;
        encoder.*.max_b_frames = 0;
        if (c.avcodec_open2(encoder, encoder_codec, null) < 0) return error.Ffmpeg;

        output_stream.*.time_base = encoder.*.time_base;
        if (c.avcodec_parameters_from_context(output_stream.*.codecpar, encoder) < 0) return error.Ffmpeg;
        if ((output.*.oformat.*.flags & c.AVFMT_NOFILE) == 0 and
            c.avio_open(&output.*.pb, destination_z.ptr, c.AVIO_FLAG_WRITE) < 0) return error.OutputOpenFailed;
        if (c.avformat_write_header(output, null) < 0) return error.Ffmpeg;

        var packet: [*c]Packet = c.av_packet_alloc();
        defer if (packet != null) c.av_packet_free(&packet);
        var decoded: [*c]Frame = c.av_frame_alloc();
        defer if (decoded != null) c.av_frame_free(&decoded);
        var converted: [*c]Frame = c.av_frame_alloc();
        defer if (converted != null) c.av_frame_free(&converted);
        if (packet == null or decoded == null or converted == null) return error.OutOfMemory;

        var scaler: [*c]SwsContext = null;
        defer if (scaler != null) c.sws_freeContext(scaler);
        var next_timestamp: i64 = 0;
        var wrote_frame = false;
        while (true) {
            const read_result = c.av_read_frame(input, packet);
            if (read_result == c.AVERROR_EOF) break;
            if (read_result < 0) return error.Ffmpeg;
            if (packet.*.stream_index == video_index) {
                const send_result = c.avcodec_send_packet(decoder, packet);
                c.av_packet_unref(packet);
                if (send_result < 0) return error.Ffmpeg;
                try receiveFrames(
                    output,
                    output_stream,
                    decoder,
                    encoder,
                    decoded,
                    converted,
                    &scaler,
                    input_stream.*.time_base,
                    encoder.*.framerate,
                    &next_timestamp,
                    &wrote_frame,
                );
            } else {
                c.av_packet_unref(packet);
            }
        }

        if (c.avcodec_send_packet(decoder, null) < 0) return error.Ffmpeg;
        try receiveFrames(
            output,
            output_stream,
            decoder,
            encoder,
            decoded,
            converted,
            &scaler,
            input_stream.*.time_base,
            encoder.*.framerate,
            &next_timestamp,
            &wrote_frame,
        );
        if (!wrote_frame) return error.InvalidVideo;
        try writeEncodedFrames(output, output_stream, encoder, null);
        if (c.av_write_trailer(output) < 0) return error.Ffmpeg;
    }
};

fn validTimeBase(value: c.AVRational) ?c.AVRational {
    if (value.num <= 0 or value.den <= 0) return null;
    return value;
}

fn isAgain(result: c_int) bool {
    return result == c.AVERROR(c.EAGAIN);
}

fn writeEncodedFrames(
    output: [*c]FormatContext,
    output_stream: [*c]Stream,
    encoder: [*c]CodecContext,
    frame: [*c]const Frame,
) !void {
    var packet: [*c]Packet = c.av_packet_alloc();
    defer if (packet != null) c.av_packet_free(&packet);
    if (packet == null) return error.OutOfMemory;
    if (c.avcodec_send_frame(encoder, frame) < 0) return error.Ffmpeg;
    while (true) {
        const result = c.avcodec_receive_packet(encoder, packet);
        if (isAgain(result) or result == c.AVERROR_EOF) return;
        if (result < 0) return error.Ffmpeg;
        c.av_packet_rescale_ts(packet, encoder.*.time_base, output_stream.*.time_base);
        packet.*.stream_index = output_stream.*.index;
        const write_result = c.av_interleaved_write_frame(output, packet);
        c.av_packet_unref(packet);
        if (write_result < 0) return error.Ffmpeg;
    }
}

fn receiveFrames(
    output: [*c]FormatContext,
    output_stream: [*c]Stream,
    decoder: [*c]CodecContext,
    encoder: [*c]CodecContext,
    decoded: [*c]Frame,
    converted: [*c]Frame,
    scaler: *[*c]SwsContext,
    input_time_base: c.AVRational,
    frame_rate: c.AVRational,
    next_timestamp: *i64,
    wrote_frame: *bool,
) !void {
    const frame_duration = @max(@as(i64, 1), c.av_rescale_q(1, c.av_inv_q(frame_rate), input_time_base));
    while (true) {
        const result = c.avcodec_receive_frame(decoder, decoded);
        if (isAgain(result) or result == c.AVERROR_EOF) return;
        if (result < 0) return error.Ffmpeg;

        var timestamp = decoded.*.best_effort_timestamp;
        if (timestamp == c.AV_NOPTS_VALUE or timestamp < next_timestamp.*) timestamp = next_timestamp.*;
        next_timestamp.* = timestamp + frame_duration;
        try convertAndWrite(output, output_stream, encoder, decoded, converted, scaler, timestamp);
        wrote_frame.* = true;
        c.av_frame_unref(decoded);
    }
}

fn convertAndWrite(
    output: [*c]FormatContext,
    output_stream: [*c]Stream,
    encoder: [*c]CodecContext,
    decoded: [*c]Frame,
    converted: [*c]Frame,
    scaler: *[*c]SwsContext,
    timestamp: i64,
) !void {
    scaler.* = c.sws_getCachedContext(
        scaler.*,
        decoded.*.width,
        decoded.*.height,
        @intCast(decoded.*.format),
        encoder.*.width,
        encoder.*.height,
        encoder.*.pix_fmt,
        c.SWS_BILINEAR,
        null,
        null,
        null,
    );
    if (scaler.* == null) return error.Ffmpeg;

    const encoder_format: c_int = @intCast(encoder.*.pix_fmt);
    if (converted.*.width != encoder.*.width or converted.*.height != encoder.*.height or converted.*.format != encoder_format) {
        c.av_frame_unref(converted);
        converted.*.format = encoder_format;
        converted.*.width = encoder.*.width;
        converted.*.height = encoder.*.height;
        if (c.av_frame_get_buffer(converted, 1) < 0) return error.OutOfMemory;
    }
    if (c.av_frame_make_writable(converted) < 0) return error.Ffmpeg;
    const rows = c.sws_scale(
        scaler.*,
        @ptrCast(&decoded.*.data),
        @ptrCast(&decoded.*.linesize),
        0,
        decoded.*.height,
        @ptrCast(&converted.*.data),
        @ptrCast(&converted.*.linesize),
    );
    if (rows != encoder.*.height) return error.Ffmpeg;
    converted.*.pts = timestamp;
    try writeEncodedFrames(output, output_stream, encoder, converted);
}

test "video rejects paths containing nul bytes" {
    const processor = Processor{ .allocator = std.testing.allocator, .io = std.testing.io };
    try std.testing.expectError(error.InvalidPath, processor.convertMp4ToGif("clip\x00.mp4", "clip.gif"));
    try std.testing.expectError(error.InvalidPath, processor.convertMp4ToGif("clip.mp4", "clip\x00.gif"));
}
