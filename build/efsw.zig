const std = @import("std");

pub fn build(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *std.Build.Step.Compile {
    const efsw_source = b.dependency("efsw", .{});

    const lib_efsw_core = b.addStaticLibrary(.{
        .name = "efsw",
        .target = target,
        .optimize = optimize,
    });

    const efsw_source_root = efsw_source.path("src/efsw");

    lib_efsw_core.addIncludePath(efsw_source.path("include"));
    lib_efsw_core.addIncludePath(efsw_source.path("src"));
    lib_efsw_core.addCSourceFiles(.{
        .root = efsw_source_root,
        .files = &.{
            "Debug.cpp",
            "DirectorySnapshot.cpp",
            "DirectorySnapshotDiff.cpp",
            "DirWatcherGeneric.cpp",
            "FileInfo.cpp",
            "FileSystem.cpp",
            "FileWatcher.cpp",
            "FileWatcherCWrapper.cpp",
            "FileWatcherGeneric.cpp",
            "FileWatcherImpl.cpp",
            "Log.cpp",
            "Mutex.cpp",
            "String.cpp",
            "System.cpp",
            "Thread.cpp",
            "Watcher.cpp",
            "WatcherGeneric.cpp",
        },
        .flags = &.{"-std=c++20"},
    });

    lib_efsw_core.addCSourceFiles(.{
        .root = efsw_source_root,
        .files = switch (target.result.os.tag) {
            .windows => &.{
                "platform/win/FileSystemImpl.cpp",
                "platform/win/MutexImpl.cpp",
                "platform/win/SystemImpl.cpp",
                "platform/win/ThreadImpl.cpp",
            },
            else => &.{
                "platform/posix/FileSystemImpl.cpp",
                "platform/posix/MutexImpl.cpp",
                "platform/posix/SystemImpl.cpp",
                "platform/posix/ThreadImpl.cpp",
            },
        },
        .flags = &.{"-std=c++20"},
    });

    lib_efsw_core.addCSourceFiles(.{
        .root = efsw_source_root,
        .files = switch (target.result.os.tag) {
            .macos => &.{
                "FileWatcherFSEvents.cpp",
                "FileWatcherKqueue.cpp",
                "WatcherFSEvents.cpp",
                "WatcherKqueue.cpp",
            },
            .windows => &.{
                "FileWatcherWin32.cpp",
                "WatcherWin32.cpp",
            },
            .linux => &.{
                "FileWatcherInotify.cpp",
                "WatcherInotify.cpp",
            },
            .freebsd => &.{
                "FileWatcherKqueue.cpp",
                "WatcherKqueue.cpp",
            },
            else => &.{},
        },
        .flags = &.{"-std=c++20"},
    });

    if (target.result.os.tag == .macos) {
        lib_efsw_core.linkFramework("CoreFoundation");
        lib_efsw_core.linkFramework("CoreServices");
    }

    if (optimize == .Debug) {
        lib_efsw_core.root_module.addCMacro("DEBUG", "1");
    }

    lib_efsw_core.linkLibC();
    lib_efsw_core.linkLibCpp();
    lib_efsw_core.installHeader(efsw_source.path("include/efsw/efsw.h"), "efsw/efsw.h");

    b.installArtifact(lib_efsw_core);

    return lib_efsw_core;
}
