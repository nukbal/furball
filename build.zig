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

fn addRawLibraries(b: *std.Build, app: native_sdk.AppArtifacts, ffmpeg_prefix: []const u8) void {
    const target = app.exe.root_module.resolved_target.?;
    const optimize = app.exe.root_module.optimize.?;
    const mods = [2]*std.Build.Module{ app.exe.root_module, app.tests.root_module };
    mods[0].link_libcpp = true;
    mods[1].link_libcpp = true;

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

        for (mods) |module| {
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

        for (mods) |module| {
            module.addImport("stb", mod.createModule());
            module.addIncludePath(dep.path("."));
            module.addCSourceFile(.{
                .file = b.path("libs/stb_impl.c"),
                .flags = &.{"-std=c99"},
            });
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

        for (mods) |module| {
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

        for (mods) |module| {
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

        for (mods) |module| {
            module.addImport("ncnn", mod.createModule());
            module.addIncludePath(dep.path("src"));
            module.addIncludePath(b.path("libs/ncnn"));
            module.addCSourceFiles(.{
                .root = dep.path("src"),
                .files = &.{
                    "allocator.cpp", "blob.cpp", "c_api.cpp", "cpu.cpp", "datareader.cpp", "expression.cpp",
                    "gpu.cpp", "layer.cpp", "mat.cpp", "mat_pixel.cpp", "mat_pixel_resize.cpp", "modelbin.cpp",
                    "net.cpp", "option.cpp", "paramdict.cpp", "simpleomp.cpp",
                    "layer/binaryop.cpp", "layer/cast.cpp", "layer/convolution.cpp", "layer/input.cpp", "layer/interp.cpp",
                    "layer/padding.cpp", "layer/pixelshuffle.cpp", "layer/prelu.cpp", "layer/scale.cpp", "layer/split.cpp",
                },
                .flags = switch (target.result.os.tag) {
                    .macos => &.{ "-std=c++11", "-Xpreprocessor", "-fopenmp" },
                    else => &.{ "-std=c++11", "-fopenmp" },
                },
            });
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

        for (mods) |module| {
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
