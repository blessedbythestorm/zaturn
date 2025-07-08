const std = @import("std");
const builtin = @import("builtin");

const Buffer = @import("zaturn-core").Buffer;
const GLTF = @import("zgltf").GLTF;
const ziggy = @import("ziggy");

const retry_count = 10;
const retry_interval = std.time.ns_per_ms * 100;

pub fn readZiggy(comptime T: type, allocator: std.mem.Allocator, path: []const u8) !T {
    const data = try readToStringSentinel(allocator, path);
    defer allocator.free(data);

    var diag: ziggy.Diagnostic = .{ .path = null };
    defer diag.deinit(allocator);

    const value = ziggy.parseLeaky(T, allocator, data, .{ .diagnostic = &diag });

    if (diag.errors.items.len > 0) {
        std.debug.print("{}", .{diag});
        return error.ZiggyParseError;
    }

    return try value;
}

pub fn readGltf(allocator: std.mem.Allocator, path: []const u8) !GLTF {
    const data = try readToString(allocator, path);
    defer allocator.free(data);

    var gltf = GLTF.init(allocator);

    try gltf.parse(data);

    return gltf;
}

pub fn readToStringSentinel(allocator: std.mem.Allocator, path: []const u8) ![:0]const u8 {
    const file = try std.fs.openFileAbsolute(path, .{ .mode = .read_only });
    defer file.close();

    return try file.readToEndAllocOptions(
        allocator,
        std.math.maxInt(usize),
        null,
        std.mem.Alignment.@"1",
        0,
    );
}

pub fn readToString(allocator: std.mem.Allocator, path: []const u8) ![]align(4) const u8 {
    const file = try std.fs.openFileAbsolute(path, .{ .mode = .read_only });
    defer file.close();

    return try file.readToEndAllocOptions(
        allocator,
        std.math.maxInt(usize),
        null,
        std.mem.Alignment.@"4",
        null,
    );
}

pub fn rename(dir: *std.fs.Dir, old_name: []const u8, new_name: []const u8) void {
    var tries: u32 = 0;
    while (tries < retry_count) : (tries += 1) {
        if (dir.rename(old_name, new_name)) |_| {
            break;
        } else |err| {
            std.time.sleep(retry_interval);
            std.debug.print("Error renaming file: {}\n", .{err});
        }
    }
}

pub fn delete(dir: *std.fs.Dir, file_name: []const u8) void {
    var tries: u32 = 0;
    while (tries < retry_count) : (tries += 1) {
        if (dir.deleteFile(file_name)) |_| {
            break;
        } else |err| {
            std.time.sleep(retry_interval);
            std.debug.print("Error deleting app.lib: {}\n", .{err});
        }
    }
}

pub fn binDir(allocator: std.mem.Allocator) !std.fs.Dir {
    const exe_path = try std.fs.selfExePathAlloc(allocator);
    defer allocator.free(exe_path);

    const exe_dir_path = std.fs.path.dirname(exe_path).?;
    return try std.fs.openDirAbsolute(exe_dir_path, .{});
}

pub fn binLibDir(allocator: std.mem.Allocator) !std.fs.Dir {
    const exe_path = try std.fs.selfExePathAlloc(allocator);
    defer allocator.free(exe_path);

    const exe_dir_path = std.fs.path.dirname(exe_path).?;

    const lib_dir_path = try std.fs.path.join(allocator, &[_][]const u8{ exe_dir_path, "..", "lib" });
    defer allocator.free(lib_dir_path);

    return try std.fs.openDirAbsolute(lib_dir_path, .{});
}

pub fn resourcesDir(allocator: std.mem.Allocator, root_dir: std.fs.Dir) !std.fs.Dir {
    const cwd_path = try root_dir.realpathAlloc(allocator, ".");
    defer allocator.free(cwd_path);

    const resources_path = if (builtin.mode == .Debug)
        try std.fs.path.join(allocator, &[_][]const u8{ cwd_path, "resources" })
    else
        try std.fs.path.join(allocator, &[_][]const u8{ cwd_path, "zig-out/bin/resources" });

    defer allocator.free(resources_path);

    return try std.fs.openDirAbsolute(resources_path, .{ .iterate = true });
}

pub fn cacheDir(allocator: std.mem.Allocator, root_dir: std.fs.Dir) !std.fs.Dir {
    const cwd_path = try root_dir.realpathAlloc(allocator, ".");
    defer allocator.free(cwd_path);

    const cache_path = if (builtin.mode == .Debug)
        try std.fs.path.join(allocator, &[_][]const u8{ cwd_path, ".zat-cache" })
    else
        try std.fs.path.join(allocator, &[_][]const u8{ cwd_path, "zig-out/bin/.zat-cache" });

    defer allocator.free(cache_path);

    std.debug.print("Cache path: {s}\n", .{cache_path});
    return try std.fs.openDirAbsolute(cache_path, .{});
}

pub fn filesWithExtension(
    allocator: std.mem.Allocator,
    directory: []const u8,
    extensions: []const []const u8,
    recursive: bool,
) !std.ArrayList([]u8) {
    var result = std.ArrayList([]u8).init(allocator);
    errdefer {
        for (result.items) |path| {
            allocator.free(path);
        }
        result.deinit();
    }

    var dir = try std.fs.cwd().openDir(directory, .{ .iterate = true });
    defer dir.close();

    var dir_iterator = dir.walk();

    while (try dir_iterator.next()) |entry| {
        if (entry.kind != .file) continue;

        if (!recursive and entry.path.len > 0 and std.mem.indexOf(u8, entry.path, std.fs.path.sep_str) != null) {
            continue;
        }

        for (extensions) |ext| {
            if (std.mem.endsWith(u8, entry.basename, ext)) {
                const full_path = try std.fs.path.join(allocator, &[_][]const u8{ directory, entry.path });
                try result.append(full_path);
                break;
            }
        }
    }

    return result;
}
