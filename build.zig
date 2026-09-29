const std = @import("std");
const AppArtifacts = struct { exe: *std.Build.Step.Compile, tests: *std.Build.Step.Compile };

fn ffmpegPrefix(b: *std.Build, target: std.Build.ResolvedTarget) []const u8 {
    return b.option([]const u8, "ffmpeg-prefix", "FFmpeg development prefix") orelse switch (target.result.os.tag) {
        .macos => if (target.result.cpu.arch == .aarch64) "/opt/homebrew" else "/usr/local",
        .windows => "C:/vcpkg/installed/x64-windows",
        else => "/usr",
    };
}

fn addRawLibraries(b: *std.Build, app: AppArtifacts, ffmpeg_prefix: []const u8) void {
    const target = app.exe.root_module.resolved_target.?;
    const optimize = app.exe.root_module.optimize.?;
    const arch = target.result.cpu.arch;
    var mods = [2]*std.Build.Module{ app.exe.root_module, app.tests.root_module };
    const mod_count: usize = if (mods[0] == mods[1]) 1 else 2;
    const sysroot = b.sysroot orelse "/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk";
    if (target.result.os.tag == .macos) {
        for (mods[0..mod_count]) |module| {
            module.addCSourceFile(.{ .file = b.path("libs/macos_window.m"), .flags = &.{"-fobjc-arc"} });
            module.linkFramework("AppKit", .{});
        }
    }
    for (mods[0..mod_count]) |module| {
        module.addObjectFile(.{ .cwd_relative = b.pathJoin(&.{ sysroot, "usr/lib/libc++.tbd" }) });
        module.addFrameworkPath(.{ .cwd_relative = b.pathJoin(&.{ sysroot, "System/Library/Frameworks" }) });
    }

    // sdl
    {
        const sdl_dep = b.dependency("sdl", .{
            .target = target,
            .optimize = optimize,
            //.preferred_linkage = .static,
            //.strip = null,
            //.sanitize_c = null,
            //.pic = null,
            //.lto = null,
            //.emscripten_pthreads = false,
            //.system_include_path = null,
            //.system_framework_path = null,
            //.library_path = null,
        });
        const sdl_lib = sdl_dep.artifact("SDL3");

        const lib = b.addTranslateC(.{
            .root_source_file = b.path("libs/sdl.h"),
            .target = target,
            .optimize = optimize,
        });
        const ttf_dep = b.dependency("sdl_ttf", .{});
        const ft_dep = b.dependency("freetype", .{
            .target = target,
            .optimize = optimize,
        });
        const ttf_lib = b.addLibrary(.{
            .name = "SDL3_ttf",
            .linkage = .static,
            .root_module = b.createModule(.{
                .target = target,
                .optimize = optimize,
                .link_libc = true,
            }),
        });
        ttf_lib.root_module.linkLibrary(ft_dep.artifact("freetype"));
        ttf_lib.root_module.addIncludePath(sdl_dep.path("include"));
        ttf_lib.root_module.addIncludePath(ttf_dep.path("include"));
        ttf_lib.root_module.addIncludePath(ttf_dep.path("src"));
        ttf_lib.root_module.addIncludePath(ft_dep.path("include"));
        ttf_lib.root_module.addCSourceFiles(.{
            .root = ttf_dep.path("src"),
            .files = &.{
                "SDL_hashtable.c",
                "SDL_hashtable_ttf.c",
                "SDL_gl_textengine.c",
                "SDL_gpu_textengine.c",
                "SDL_renderer_textengine.c",
                "SDL_surface_textengine.c",
                "SDL_ttf.c",
            },
            .flags = &.{"-DSDL_BUILDING_TTF"},
        });
        lib.addIncludePath(sdl_dep.path("include"));
        lib.addIncludePath(ttf_dep.path("include"));
        const sdl_mod = lib.createModule();

        for (mods[0..mod_count]) |module| {
            module.linkLibrary(sdl_lib);
            module.linkLibrary(ttf_lib);
            module.addImport("sdl", sdl_mod);
        }
    }

    // clay
    {
        const dep = b.dependency("clay", .{});
        const mod = b.addTranslateC(.{
            .root_source_file = b.path("libs/clay.h"),
            .target = target,
            .optimize = optimize,
        });
        mod.addIncludePath(dep.path("."));
        const impl = b.addWriteFiles().add("clay_impl.c", "#include <clay.h>\n");

        var modules = [2]*std.Build.Module{ app.exe.root_module, app.tests.root_module };
        const module_count: usize = if (modules[0] == modules[1]) 1 else 2;
        for (modules[0..module_count]) |module| {
            module.link_libc = true;
            module.addIncludePath(dep.path("."));
            module.addIncludePath(b.path("libs"));
            module.addImport("clay", mod.createModule());
            module.addCSourceFile(.{
                .file = impl,
                .flags = &.{"-DCLAY_IMPLEMENTATION"},
            });
        }
    }

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
            module.addCSourceFiles(.{ .root = mozjpeg_dep.path("."), .files = &.{
                "jcapimin.c", "jcapistd.c", "jcarith.c",    "jccoefct.c",
                "jccolor.c",  "jcdctmgr.c", "jcext.c",      "jchuff.c",
                "jcicc.c",    "jcinit.c",   "jcmainct.c",   "jcmarker.c",
                "jcmaster.c", "jcomapi.c",  "jcparam.c",    "jcphuff.c",
                "jcprepct.c", "jcsample.c", "jctrans.c",    "jdapimin.c",
                "jdapistd.c", "jdarith.c",  "jdatadst.c",   "jdatasrc.c",
                "jdcoefct.c", "jdcolor.c",  "jddctmgr.c",   "jdhuff.c",
                "jdicc.c",    "jdinput.c",  "jdmainct.c",   "jdmarker.c",
                "jdmaster.c", "jdmerge.c",  "jdphuff.c",    "jdpostct.c",
                "jdsample.c", "jdtrans.c",  "jerror.c",     "jfdctflt.c",
                "jfdctfst.c", "jfdctint.c", "jidctflt.c",   "jidctfst.c",
                "jidctint.c", "jidctred.c", "jmemmgr.c",    "jmemnobs.c",
                "jquant1.c",  "jquant2.c",  "jsimd_none.c", "jutils.c",
                "jaricom.c",
            }, .flags = &.{"-DMEM_SRCDST_SUPPORTED"} });
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
                .flags = &.{ "-std=c99", "-DSTBIR_NO_SIMD" },
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

    {
        const mod = b.addTranslateC(.{
            .root_source_file = b.path("libs/coreml/coreml_bridge.h"),
            .target = target,
            .optimize = optimize,
        });

        for (mods[0..mod_count]) |module| {
            module.addImport("coreml", mod.createModule());
            if (target.result.os.tag == .macos) {
                module.addCSourceFile(.{ .file = b.path("libs/coreml/coreml_bridge.m"), .flags = &.{"-fobjc-arc"} });
                module.linkFramework("CoreML", .{});
                module.linkFramework("CoreVideo", .{});
                module.linkFramework("Foundation", .{});
            } else {
                module.addCSourceFile(.{ .file = b.path("libs/coreml/coreml_stub.c") });
            }
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
    if (b.sysroot == null) b.sysroot = "/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk";
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .strip = optimize != .Debug,
    });
    const exe = b.addExecutable(.{ .name = "furball", .root_module = module });
    const tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    }) });
    const app = AppArtifacts{ .exe = exe, .tests = tests };
    const ffmpeg_prefix = ffmpegPrefix(b, target);
    addRawLibraries(b, app, ffmpeg_prefix);
    b.installArtifact(exe);
    const test_step = b.step("test", "Run tests");
    const test_filter = b.option([]const u8, "test-filter", "Run only tests whose names contain this text");
    tests.filters = if (test_filter) |filter| b.dupeStrings(&.{filter}) else &.{};
    test_step.dependOn(&b.addRunArtifact(tests).step);
    const run = b.addRunArtifact(exe);
    if (b.args) |args| run.addArgs(args);
    b.step("run", "Run Furball").dependOn(&run.step);

    const package = b.step("package", "Package Furball for distribution");
    switch (target.result.os.tag) {
        .macos => {
            const command = b.addSystemCommand(&.{"bash"});
            command.addFileArg(b.path("scripts/package-macos.sh"));
            command.addFileArg(exe.getEmittedBin());
            command.addArg(b.getInstallPath(.prefix, "package"));
            command.addArg(ffmpeg_prefix);
            package.dependOn(&command.step);
        },
        .windows => {
            const command = b.addSystemCommand(&.{"powershell.exe"});
            command.addArgs(&.{ "-NoProfile", "-ExecutionPolicy", "Bypass", "-File" });
            command.addFileArg(b.path("scripts/package-windows.ps1"));
            command.addFileArg(exe.getEmittedBin());
            command.addArg(b.getInstallPath(.prefix, "package"));
            command.addArg(ffmpeg_prefix);
            package.dependOn(&command.step);
        },
        else => package.dependOn(&b.addFail("The package step supports macOS and Windows").step),
    }
}
