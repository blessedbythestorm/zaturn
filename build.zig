const std = @import("std");

pub fn build(b: *std.Build) void { // $ls root_id 1
    const start_build_time = std.time.nanoTimestamp();

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const superzig = b.dependency("superzig", .{
        .target = target,
        .optimize = optimize,
    });

    const zalgebra = b.dependency("zalgebra", .{
        .target = target,
        .optimize = optimize,
    });

    const zaturn_core = b.addModule("zaturn-core", .{
        .root_source_file = b.path("src/core/_core.zig"),
        .target = target,
        .optimize = optimize,
    });

    zaturn_core.addImport("io", superzig.module("io"));
    zaturn_core.addImport("zalgebra", zalgebra.module("zalgebra"));
    zaturn_core.addImport("zaturn-core", zaturn_core);

    const zaturn_log = b.addModule("zaturn-log", .{
        .root_source_file = b.path("src/log/_log.zig"),
        .target = target,
        .optimize = optimize,
    });

    zaturn_log.addImport("zaturn-log", zaturn_log);
    zaturn_log.addImport("zaturn-core", zaturn_core);

    const ziggy = b.dependency("ziggy", .{
        .target = target,
        .optimize = optimize,
    });

    const toml = b.dependency("toml", .{
        .target = target,
        .optimize = optimize,
    });

    const yaml = b.dependency("yaml", .{
        .target = target,
        .optimize = optimize,
    });

    const zgltf = b.dependency("zgltf", .{
        .target = target,
        .optimize = optimize,
    });

    const efsw_build = @import("build/efsw.zig");
    const efsw = efsw_build.build(b, target, optimize);

    const zaturn_resources = b.addModule("zaturn-resources", .{
        .root_source_file = b.path("src/resources/_resources.zig"),
        .target = target,
        .optimize = optimize,
    });

    zaturn_resources.addImport("zaturn-core", zaturn_core);
    zaturn_resources.addImport("zaturn-log", zaturn_log);
    zaturn_resources.addImport("toml", toml.module("zig-toml"));
    zaturn_resources.addImport("zgltf", zgltf.module("zgltf"));
    zaturn_resources.addImport("yaml", yaml.module("root"));
    zaturn_resources.addImport("ziggy", ziggy.module("ziggy"));
    zaturn_resources.addIncludePath(.{ .cwd_relative = b.pathJoin(&.{ b.install_path, "include" }) });
    zaturn_resources.linkLibrary(efsw);

    const zsdl = b.dependency("sdl3", .{
        .target = target,
        .optimize = optimize,
        .ext_image = false,
    });

    const zaturn_window = b.addModule("zaturn-window", .{
        .root_source_file = b.path("src/window/_window.zig"),
        .target = target,
        .optimize = optimize,
    });

    zaturn_window.addImport("zaturn-window", zaturn_window);
    zaturn_window.addImport("zaturn-core", zaturn_core);
    zaturn_window.addImport("zaturn-log", zaturn_log);
    zaturn_window.addImport("zaturn-resources", zaturn_resources);
    zaturn_window.addImport("sdl3", zsdl.module("sdl3"));

    const vulkan = b.dependency("vulkan_zig", .{
        .registry = b.dependency("vulkan_headers", .{})
            .path("registry/vk.xml"),
    });

    const lib_vulkan = switch (target.result.os.tag) {
        .windows => "vulkan-1",
        else => "vulkan",
    };

    const zaturn_gpu = b.addModule("zaturn-gpu", .{
        .root_source_file = b.path("src/gpu/_gpu.zig"),
        .target = target,
        .optimize = optimize,
    });

    zaturn_gpu.addImport("zaturn-gpu", zaturn_gpu);
    zaturn_gpu.addImport("zaturn-core", zaturn_core);
    zaturn_gpu.addImport("zaturn-log", zaturn_log);
    zaturn_gpu.addImport("zaturn-window", zaturn_window);
    zaturn_gpu.addImport("zaturn-resources", zaturn_resources);
    zaturn_gpu.addImport("vulkan-zig", vulkan.module("vulkan-zig"));

    const libs_path = switch (target.result.os.tag) {
        .windows => "lib/win64",
        .linux => "lib/linux",
        .macos => "lib/macos",
        else => "vulkan",
    };

    zaturn_gpu.addLibraryPath(b.path(libs_path));
    zaturn_gpu.linkSystemLibrary(lib_vulkan, .{});

    const zaturn_root = b.addModule("zaturn", .{
        .root_source_file = b.path("src/zaturn.zig"),
        .target = target,
        .optimize = optimize,
    });

    zaturn_root.addImport("zaturn-core", zaturn_core);
    zaturn_root.addImport("zaturn-log", zaturn_log);
    zaturn_root.addImport("zaturn-window", zaturn_window);
    zaturn_root.addImport("zaturn-resources", zaturn_resources);
    zaturn_root.addImport("zaturn-gpu", zaturn_gpu);

    const zaturn_exe = b.addExecutable(.{
        .name = "zaturn",
        .root_module = zaturn_root,
    });

    b.installArtifact(zaturn_exe);

    const clear_cache = b.option(bool, "clean", "Clear asset cache") orelse false;
    const cache = @import("build/cache.zig");

    cache.init();
    defer cache.deinit();

    if (clear_cache) {
        cache.clear(std.fs.cwd()) catch |err| {
            std.log.err("Error clearing cache: {}\n", .{err});
            @panic("Error clearing cache");
        };
    }

    // Build asset cache
    cache.build(std.fs.cwd()) catch |err| {
        std.log.err("Error building cache: {}\n", .{err});
        @panic("Error building cache");
    };

    // Check executable
    const lib_check = b.addExecutable(.{
        .name = "zaturn",
        .root_module = zaturn_root,
    });

    const check = b.step("check", "Check if Zaturn compiles");
    check.dependOn(&lib_check.step);

    const end_build_time = @as(f128, @floatFromInt(std.time.nanoTimestamp() - start_build_time)) / 1_000_000.0;
    std.debug.print("Build took: {d:6.3} ms\n", .{end_build_time});
}
