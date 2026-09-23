const std = @import("std");
const native_sdk = @import("native_sdk");

fn ffmpegPrefix(b: *std.Build, target: std.Build.ResolvedTarget) []const u8 {
    return b.option([]const u8, "ffmpeg-prefix", "FFmpeg development prefix") orelse switch (target.result.os.tag) {
        .macos => if (target.result.cpu.arch == .aarch64) "/opt/homebrew" else "/usr/local",
        .windows => "C:/vcpkg/installed/x64-windows",
        else => "/usr",
    };
}

fn addFfmpegPackageStep(b: *std.Build, ffmpeg_prefix: []const u8) void {
    const package_top = b.top_level_steps.get("package") orelse return;
    const stage = switch (b.graph.host.result.os.tag) {
        .macos => blk: {
            const run = b.addSystemCommand(&.{"bash"});
            run.addFileArg(b.path("scripts/bundle-ffmpeg-macos.sh"));
            run.addArg(b.pathFromRoot("zig-out/package/furball.app"));
            run.addArg(ffmpeg_prefix);
            break :blk run;
        },
        .windows => blk: {
            const run = b.addSystemCommand(&.{ "powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File" });
            run.addFileArg(b.path("scripts/bundle-ffmpeg-windows.ps1"));
            run.addArg(b.pathFromRoot("zig-out/package/windows"));
            run.addArg(ffmpeg_prefix);
            break :blk run;
        },
        else => return,
    };
    for (package_top.step.dependencies.items) |dependency| {
        stage.step.dependOn(dependency);
    }
    package_top.step.dependencies.clearRetainingCapacity();
    package_top.step.dependOn(&stage.step);
    stage.has_side_effects = true;
}

fn addNcnnPackageStep(
    b: *std.Build,
    library: []const u8,
    molten_vk_prefix: []const u8,
    glslang_prefix: []const u8,
    spirv_tools_prefix: []const u8,
    ncnn_license: std.Build.LazyPath,
) void {
    const package_top = b.top_level_steps.get("package") orelse return;
    const stage = b.addSystemCommand(&.{"bash"});
    stage.addFileArg(b.path("scripts/bundle-ncnn-macos.sh"));
    stage.addArg(b.pathFromRoot("zig-out/package/furball.app"));
    stage.addArg(library);
    stage.addArg(molten_vk_prefix);
    stage.addArg(glslang_prefix);
    stage.addArg(spirv_tools_prefix);
    stage.addFileArg(ncnn_license);
    for (package_top.step.dependencies.items) |dependency| {
        stage.step.dependOn(dependency);
    }
    package_top.step.dependencies.clearRetainingCapacity();
    package_top.step.dependOn(&stage.step);
    stage.has_side_effects = true;
}

fn addRawLibraries(b: *std.Build, app: native_sdk.AppArtifacts, ffmpeg_prefix: []const u8) void {
    const target = app.exe.root_module.resolved_target.?;
    const optimize = app.exe.root_module.optimize.?;
    const arch = target.result.cpu.arch;
    var mods = [2]*std.Build.Module{ app.exe.root_module, app.tests.root_module };
    const mod_count: usize = if (mods[0] == mods[1]) 1 else 2;
    for (mods[0..mod_count]) |module| module.link_libcpp = true;

    // mozjpeg
    const mozjpeg_dep = b.dependency("mozjpeg", .{});
    {
        const mod = b.addTranslateC(.{
            .root_source_file = b.path("libs/mozjpeg/mozjpeg.h"),
            .target = target,
            .optimize = optimize,
        });
        mod.addIncludePath(mozjpeg_dep.path("."));
        mod.addIncludePath(b.path("libs/mozjpeg"));

        for (mods[0..mod_count]) |module| {
            module.addImport("mozjpeg", mod.createModule());
            module.addIncludePath(mozjpeg_dep.path("."));
            module.addIncludePath(b.path("libs/mozjpeg"));
            module.addCSourceFiles(.{
                .root = mozjpeg_dep.path("."),
                .files = &.{
                    "jcapimin.c", "jcapistd.c", "jcarith.c",  "jccoefct.c",
                    "jccolor.c",  "jcdctmgr.c", "jcext.c",    "jchuff.c",
                    "jcicc.c",    "jcinit.c",   "jcmainct.c", "jcmarker.c",
                    "jcmaster.c", "jcomapi.c",  "jcparam.c",  "jcphuff.c",
                    "jcprepct.c", "jcsample.c", "jctrans.c",
                    "jdapimin.c", "jdapistd.c", "jdarith.c",  "jdatadst.c",
                    "jdatasrc.c", "jdcoefct.c", "jdcolor.c",  "jddctmgr.c",
                    "jdhuff.c",   "jdicc.c",    "jdinput.c",  "jdmainct.c",
                    "jdmarker.c", "jdmaster.c", "jdmerge.c",  "jdphuff.c",
                    "jdpostct.c", "jdsample.c", "jdtrans.c",  "jerror.c",
                    "jfdctflt.c", "jfdctfst.c", "jfdctint.c", "jidctflt.c",
                    "jidctfst.c", "jidctint.c", "jidctred.c", "jmemmgr.c",
                    "jmemnobs.c", "jquant1.c",  "jquant2.c",  "jsimd_none.c",
                    "jutils.c",   "jaricom.c",
                },
                .flags = &.{"-DMEM_SRCDST_SUPPORTED"}
            });
        }
    }

    // stb_image
    {
        const dep = b.dependency("stb", .{});
        const mod = b.addTranslateC(.{
            .root_source_file = b.path("libs/stb.h"),
            .target = target,
            .optimize = optimize,
        });
        mod.addIncludePath(dep.path("."));
        mod.addIncludePath(mozjpeg_dep.path("."));

        for (mods[0..mod_count]) |module| {
            module.addImport("stb", mod.createModule());
            module.addIncludePath(dep.path("."));
            module.addCSourceFile(.{
                .file = b.path("libs/stb_impl.c"),
                .flags = &.{"-std=c99"},
            });
        }
    }

    {
        const dep = b.dependency("libwebp", .{});
        const mod = b.addTranslateC(.{
            .root_source_file = dep.path("src/webp/decode.h"),
            .target = target,
            .optimize = optimize,
        });
        mod.addIncludePath(dep.path("."));

        for (mods[0..mod_count]) |module| {
            module.addImport("webp", mod.createModule());
            module.addIncludePath(dep.path("."));
            module.addCSourceFiles(.{
                .root = dep.path("src"),
                .files = &.{
                    "dec/alpha_dec.c",                "dec/buffer_dec.c",      "dec/frame_dec.c",        "dec/idec_dec.c",
                    "dec/io_dec.c",                   "dec/quant_dec.c",       "dec/tree_dec.c",         "dec/vp8_dec.c",
                    "dec/vp8l_dec.c",                 "dec/webp_dec.c",        "dsp/alpha_processing.c", "dsp/cpu.c",
                    "dsp/dec.c",                      "dsp/dec_clip_tables.c", "dsp/filters.c",          "dsp/lossless.c",
                    "dsp/rescaler.c",                 "dsp/upsampling.c",      "dsp/yuv.c",              "utils/bit_reader_utils.c",
                    "utils/color_cache_utils.c",      "utils/filters_utils.c", "utils/huffman_utils.c",  "utils/palette.c",
                    "utils/quant_levels_dec_utils.c", "utils/random_utils.c",  "utils/rescaler_utils.c", "utils/thread_utils.c",
                    "utils/utils.c",
                },
                .flags = &.{"-std=c99"},
            });
            if (arch == .aarch64 or arch == .arm) {
                module.addCSourceFiles(.{
                    .root = dep.path("src"),
                    .files = &.{
                        "dsp/alpha_processing_neon.c", "dsp/dec_neon.c",      "dsp/filters_neon.c",
                        "dsp/lossless_neon.c",         "dsp/rescaler_neon.c", "dsp/upsampling_neon.c",
                        "dsp/yuv_neon.c",
                    },
                    .flags = &.{"-std=c99"},
                });
            } else if (arch == .x86_64 or arch == .x86) {
                module.addCSourceFiles(.{
                    .root = dep.path("src"),
                    .files = &.{
                        "dsp/alpha_processing_sse2.c", "dsp/dec_sse2.c",               "dsp/filters_sse2.c",
                        "dsp/lossless_sse2.c",         "dsp/rescaler_sse2.c",          "dsp/upsampling_sse2.c",
                        "dsp/yuv_sse2.c",              "dsp/alpha_processing_sse41.c", "dsp/dec_sse41.c",
                        "dsp/lossless_sse41.c",        "dsp/upsampling_sse41.c",       "dsp/yuv_sse41.c",
                        "dsp/lossless_avx2.c",
                    },
                    .flags = &.{"-std=c99"},
                });
            }
        }
    }

    // miniz
    {
        const dep = b.dependency("miniz", .{});
        const mod = b.addTranslateC(.{
            .root_source_file = dep.path("miniz.h"),
            .target = target,
            .optimize = optimize,
        });
        mod.addIncludePath(dep.path("."));

        const miniz_export = b.addConfigHeader(.{ .include_path = "miniz_export.h" }, .{});
        miniz_export.addValue("MINIZ_EXPORT", void, {});
        mod.addConfigHeader(miniz_export);

        for (mods[0..mod_count]) |module| {
            module.addImport("miniz", mod.createModule());
            module.addIncludePath(dep.path("."));
            module.addConfigHeader(miniz_export);
            module.addCSourceFiles(.{ .root = dep.path("."), .files = &.{ "miniz.c", "miniz_tdef.c", "miniz_tinfl.c", "miniz_zip.c" }, .flags = &.{"-std=c90"} });
        }
    }

    // pdfio
    {
        const dep = b.dependency("pdfio", .{});
        const ttf_dep = b.dependency("ttf", .{});

        const mod = b.addTranslateC(.{
            .root_source_file = dep.path("pdfio.h"),
            .target = target,
            .optimize = optimize,
        });
        mod.addIncludePath(dep.path("."));
        mod.addIncludePath(ttf_dep.path("."));
        // use miniz zlib compatitable layer
        mod.addIncludePath(b.path("libs/zlib"));

        for (mods[0..mod_count]) |module| {
            module.addImport("pdfio", mod.createModule());
            module.addIncludePath(dep.path("."));
            module.addIncludePath(ttf_dep.path("."));
            module.addIncludePath(b.path("libs/zlib"));
            module.addCSourceFiles(.{ .root = ttf_dep.path("."), .files = &.{ "ttf-cache.c", "ttf-file.c" }, .flags = &.{} });
            module.addCSourceFiles(.{ .root = dep.path("."), .files = &.{
                "pdfio-aes.c",     "pdfio-array.c",  "pdfio-common.c", "pdfio-crypto.c",
                "pdfio-content.c", "pdfio-dict.c",   "pdfio-file.c",   "pdfio-lzw.c",
                "pdfio-md5.c",     "pdfio-object.c", "pdfio-page.c",   "pdfio-rc4.c",
                "pdfio-sha256.c",  "pdfio-stream.c", "pdfio-string.c", "pdfio-token.c",
                "pdfio-value.c",
            }, .flags = &.{"-DPDFIO_STATIC"} });
        }
    }

    // ncnn (for real-esrgan)
    {
        const dep = b.dependency("ncnn", .{});
        const mod = b.addTranslateC(.{
            .root_source_file = b.path("libs/ncnn/ncnn_c_api.h"),
            .target = target,
            .optimize = optimize,
        });
        mod.addIncludePath(b.path("libs/ncnn"));
        mod.addIncludePath(dep.path("src"));
        if (target.result.os.tag != .windows) mod.linkSystemLibrary("pthread", .{});

        for (mods[0..mod_count]) |module| {
            module.addImport("ncnn", mod.createModule());
            module.addIncludePath(dep.path("src"));
            module.addIncludePath(b.path("libs/ncnn"));
            if (target.result.os.tag != .macos) {
                if (target.result.cpu.arch == .aarch64 or target.result.cpu.arch == .arm) {
                    module.addIncludePath(dep.path("src/layer"));
                    module.addCSourceFiles(.{
                        .root = dep.path("src"),
                        .files = &.{
                            "layer/arm/binaryop_arm.cpp",
                            "layer/arm/cast_arm.cpp",
                            "layer/arm/convolution_arm.cpp",
                            "layer/arm/interp_arm.cpp",
                            "layer/arm/padding_arm.cpp",
                            "layer/arm/packing_arm.cpp",
                            "layer/arm/pixelshuffle_arm.cpp",
                            "layer/arm/prelu_arm.cpp",
                            "layer/arm/scale_arm.cpp",
                        },
                        .flags = &.{ "-std=c++11", "-fopenmp", "-O3" },
                    });
                }
                module.addCSourceFiles(.{
                    .root = dep.path("src"),
                    .files = &.{
                        "allocator.cpp", "blob.cpp", "c_api.cpp", "cpu.cpp", "datareader.cpp", "expression.cpp",
                        "gpu.cpp", "layer.cpp", "mat.cpp", "mat_pixel.cpp", "mat_pixel_resize.cpp", "modelbin.cpp",
                        "net.cpp", "option.cpp", "paramdict.cpp", "simpleomp.cpp",
                        "layer/binaryop.cpp", "layer/cast.cpp", "layer/convolution.cpp", "layer/input.cpp", "layer/interp.cpp",
                        "layer/padding.cpp", "layer/pixelshuffle.cpp", "layer/prelu.cpp", "layer/scale.cpp", "layer/split.cpp",
                        "layer/packing.cpp",
                    },
                    .flags = &.{ "-std=c++11", "-fopenmp", "-O3" },
                });
            }
        }

        if (target.result.os.tag == .macos) {
            const molten_vk_prefix = b.option([]const u8, "molten-vk-prefix", "MoltenVK Homebrew prefix") orelse switch (target.result.cpu.arch) {
                .aarch64 => "/opt/homebrew/opt/molten-vk",
                else => "/usr/local/opt/molten-vk",
            };
            const glslang_prefix = b.option([]const u8, "glslang-prefix", "glslang Homebrew prefix") orelse switch (target.result.cpu.arch) {
                .aarch64 => "/opt/homebrew/opt/glslang",
                else => "/usr/local/opt/glslang",
            };
            const spirv_tools_prefix = b.option([]const u8, "spirv-tools-prefix", "SPIRV-Tools Homebrew prefix") orelse switch (target.result.cpu.arch) {
                .aarch64 => "/opt/homebrew/opt/spirv-tools",
                else => "/usr/local/opt/spirv-tools",
            };
            const ncnn_build = b.addSystemCommand(&.{"bash"});
            ncnn_build.addFileArg(b.path("scripts/build-ncnn-vulkan-macos.sh"));
            ncnn_build.addDirectoryArg(dep.path("."));
            ncnn_build.addArg(molten_vk_prefix);
            ncnn_build.addArg(glslang_prefix);
            const library_path = b.pathFromRoot("zig-out/deps/ncnn-vulkan/libncnn.dylib");
            ncnn_build.addArg(library_path);
            ncnn_build.has_side_effects = true;

            const library_dir = std.fs.path.dirname(library_path) orelse @panic("ncnn library output has no parent directory");
            for (mods[0..mod_count]) |module| {
                module.addObjectFile(.{ .cwd_relative = library_path });
                module.addRPathSpecial(library_dir);
                module.linkFramework("Metal", .{});
                module.linkFramework("Foundation", .{});
                module.linkFramework("QuartzCore", .{});
                module.linkFramework("CoreGraphics", .{});
                module.linkFramework("IOSurface", .{});
                module.linkFramework("AppKit", .{});
                module.linkFramework("IOKit", .{});
            }
            app.exe.step.dependOn(&ncnn_build.step);
            app.tests.step.dependOn(&ncnn_build.step);
            addNcnnPackageStep(b, library_path, molten_vk_prefix, glslang_prefix, spirv_tools_prefix, dep.path("LICENSE.txt"));
        }
    }

    // ffmpeg
    {
        const mod = b.addTranslateC(.{
            .root_source_file = b.path("libs/ffmpeg.h"),
            .target = target,
            .optimize = optimize,
        });
        mod.addSystemIncludePath(.{ .cwd_relative = b.pathJoin(&.{ ffmpeg_prefix, "include" }) });

        for (mods[0..mod_count]) |module| {
            module.addImport("ffmpeg", mod.createModule());
            module.addSystemIncludePath(.{ .cwd_relative = b.pathJoin(&.{ ffmpeg_prefix, "include" }) });
            if (target.result.os.tag == .macos) {
                module.addRPathSpecial("@loader_path/../Frameworks");
                inline for (&.{ "libavformat.dylib", "libavcodec.dylib", "libswscale.dylib", "libavutil.dylib" }) |name| {
                    module.addObjectFile(.{ .cwd_relative = b.pathJoin(&.{ ffmpeg_prefix, "lib", name }) });
                }
            } else {
                module.addLibraryPath(.{ .cwd_relative = b.pathJoin(&.{ ffmpeg_prefix, "lib" }) });
                module.linkSystemLibrary("avformat", .{ .use_pkg_config = .no, .preferred_link_mode = .dynamic });
                module.linkSystemLibrary("avcodec", .{ .use_pkg_config = .no, .preferred_link_mode = .dynamic });
                module.linkSystemLibrary("swscale", .{ .use_pkg_config = .no, .preferred_link_mode = .dynamic });
                module.linkSystemLibrary("avutil", .{ .use_pkg_config = .no, .preferred_link_mode = .dynamic });
            }
        }
    }
}

pub fn build(b: *std.Build) void {
    const sdk = b.dependency("native_sdk", .{});
    const sdk_cli = b.addRunArtifact(sdk.artifact("native"));
    if (b.args) |args| sdk_cli.addArgs(args);
    b.step("sdk", "Run the Native SDK developer CLI").dependOn(&sdk_cli.step);

    const app = native_sdk.addAppArtifacts(b, sdk, .{
        .name = "furball",
        .main = "src/main.zig",
        .terminal_sessions = false,
    });
    const test_filter = b.option([]const u8, "test-filter", "Run only tests whose names contain this text");
    app.tests.filters = if (test_filter) |filter| b.dupeStrings(&.{filter}) else &.{};
    const ffmpeg_prefix = ffmpegPrefix(b, app.exe.root_module.resolved_target.?);
    addRawLibraries(b, app, ffmpeg_prefix);
    addFfmpegPackageStep(b, ffmpeg_prefix);

    const run = b.addSystemCommand(&.{b.getInstallPath(.bin, app.exe.out_filename)});
    if (b.args) |args| run.addArgs(args);
    run.step.dependOn(b.getInstallStep());
    const run_step = &b.top_level_steps.get("run").?.step;
    run_step.dependencies.clearRetainingCapacity();
    run_step.dependOn(&run.step);
}
