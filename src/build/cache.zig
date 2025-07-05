const std = @import("std");
const builtin = @import("builtin");

const GLTF = @import("zgltf");
const ziggy = @import("ziggy");
const Map = ziggy.dynamic.Map;

const res = @import("../resources/_resources.zig");
const files = res.files;

const CacheSource = struct {
    source: []const u8,
    modified: i64,
    type: Asset,
};

const CacheSources = struct {
    sources: Map(CacheSource),
};

var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
var chosen_alloc: ?std.mem.Allocator = null;
var is_debug = true;

pub fn init() void {
    chosen_alloc, is_debug = gpa: {
        if (builtin.os.tag == .wasi) break :gpa .{ std.heap.wasm_allocator, false };
        break :gpa switch (builtin.mode) {
            .Debug, .ReleaseSafe => .{ debug_allocator.allocator(), true },
            .ReleaseFast, .ReleaseSmall => .{ std.heap.smp_allocator, false },
        };
    };
}

pub fn deinit() void {
    if (is_debug) {
        _ = debug_allocator.deinit();
    }
}

pub fn clear(root_dir: std.fs.Dir) !void {
    const start_clear_cache_time = std.time.nanoTimestamp();

    var arena = std.heap.ArenaAllocator.init(chosen_alloc.?);
    defer arena.deinit();

    const allocator = arena.allocator();

    var cache_dir = try files.cacheDir(allocator, root_dir);

    const cache_dir_path = try cache_dir.realpathAlloc(allocator, ".");
    const cache_sources_path = try std.fs.path.join(allocator, &[_][]const u8{ cache_dir_path, "sources.zgy" });

    cache_dir.close();

    try std.fs.cwd().deleteTree(cache_dir_path);
    try std.fs.cwd().makeDir(cache_dir_path);

    const cache_sources = CacheSources{
        .sources = .{},
    };

    var write_file = try cache_dir.createFile(cache_sources_path, .{ .truncate = true });
    defer write_file.close();

    try ziggy.stringify(cache_sources, .{ .whitespace = .space_4 }, write_file.writer());

    const end_clear_cache_time = @as(f128, @floatFromInt(std.time.nanoTimestamp() - start_clear_cache_time)) / 1_000_000.0;
    std.debug.print("Cache clear took: {d:6.3} ms\n", .{end_clear_cache_time});
}

pub fn build(root_dir: std.fs.Dir) !void {
    const start_cache_time = std.time.nanoTimestamp();

    var arena = std.heap.ArenaAllocator.init(chosen_alloc.?);
    defer arena.deinit();

    const allocator = arena.allocator();

    var cache_dir = try files.cacheDir(allocator, root_dir);
    defer cache_dir.close();

    const cache_dir_path = try cache_dir.realpathAlloc(allocator, ".");

    std.debug.print("Cache dir path: {s}\n", .{cache_dir_path});

    const cache_sources_path = try std.fs.path.join(allocator, &[_][]const u8{ cache_dir_path, "sources.zgy" });

    std.debug.print("Cache sources path: {s}\n", .{cache_sources_path});

    var cache_sources = try files.readZiggy(CacheSources, allocator, cache_sources_path);

    var resources_dir = try files.resourcesDir(allocator, root_dir);
    defer resources_dir.close();

    try walk_resources(allocator, &resources_dir, &cache_sources);

    var write_file = try cache_dir.createFile(cache_sources_path, .{ .truncate = true });
    defer write_file.close();

    try ziggy.stringify(cache_sources, .{ .whitespace = .space_4 }, write_file.writer());

    const end_cache_time = @as(f128, @floatFromInt(std.time.nanoTimestamp() - start_cache_time)) / 1_000_000.0;
    std.debug.print("Cache took: {d:6.3} ms\n", .{end_cache_time});
}

fn hashPath(path: []const u8) u64 {
    var hasher = std.hash.Wyhash.init(0);
    hasher.update(path);
    return hasher.final();
}

fn validatePath(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    if (!std.fs.path.isAbsolute(path)) {
        return error.InvalidPath;
    }

    var out = try allocator.alloc(u8, path.len);

    for (path, 0..) |c, i| {
        if (c == '/') {
            out[i] = '\\';
        } else {
            out[i] = c;
        }
    }

    return out;
}

fn walk_resources(
    allocator: std.mem.Allocator,
    resources_dir: *std.fs.Dir,
    cache_sources: *CacheSources,
) !void {
    var resource_walker = try resources_dir.walk(allocator);
    defer resource_walker.deinit();

    while (try resource_walker.next()) |entry| {
        switch (entry.kind) {
            .file => {
                const curr_dir_path = try resources_dir.realpathAlloc(allocator, ".");
                const file_path = try std.fs.path.join(allocator, &[_][]const u8{ curr_dir_path, entry.path });

                cache_file(allocator, file_path, cache_sources) catch |err| {
                    std.debug.print("Cache {}: {s}\n", .{ err, file_path });
                    continue;
                };
            },
            else => {},
        }
    }
}

pub fn cache_file(allocator: std.mem.Allocator, file_path: []const u8, cache_sources: *CacheSources) !void {
    const file_stat = try std.fs.cwd().statFile(file_path);
    const modified = file_stat.mtime;

    const path_hash = hashPath(file_path);
    const hash_str = try std.fmt.allocPrint(allocator, "{x}", .{path_hash});

    if (cache_sources.sources.fields.getPtr(hash_str)) |cache_source| {
        const file_modified: i64 = @intCast(modified);
        if (cache_source.modified <= file_modified) {
            return error.CacheUpToDate;
        }
    }

    const file = try std.fs.openFileAbsolute(file_path, .{ .mode = .read_only });
    defer file.close();

    const asset_type = get_asset_type(file_path);

    switch (asset_type) {
        .Image => {},
        .GLTF => {
            const data = try files.readToString(allocator, file_path);
            defer allocator.free(data);

            var gltf = GLTF.init(allocator);
            defer gltf.deinit();

            try gltf.parse(data);

            const base_path = std.fs.path.dirname(file_path) orelse ".";

            for (gltf.data.images.items) |image| {
                const image_path_raw = try std.fs.path.join(allocator, &[_][]const u8{ base_path, image.uri.? });
                const image_path = try validatePath(allocator, image_path_raw);

                try cache_file(allocator, image_path, cache_sources);
            }
        },
        else => {
            return error.UnsupportedAssetType;
        },
    }

    try cache_sources.sources.fields.put(allocator, hash_str, .{
        .source = file_path,
        .modified = @intCast(modified),
        .type = asset_type,
    });

    std.debug.print("Cached {s}: {s}\n", .{ hash_str, file_path });
}

pub const Asset = enum {
    Image,
    GLTF,
    Unsupported,

    pub const ziggy_options = struct {
        pub fn stringify(value: Asset, _: ziggy.serializer.StringifyOptions, _: usize, _: usize, writer: anytype) !void {
            try writer.print("@asset(\"{s}\")", .{@tagName(value)});
        }
    };
};

fn get_asset_type(file_path: []const u8) Asset {
    const ext = get_file_extension(file_path);
    if (std.mem.eql(u8, ext, ".png") or std.mem.eql(u8, ext, ".jpg") or std.mem.eql(u8, ext, ".jpeg") or std.mem.eql(u8, ext, ".hdr")) {
        return Asset.Image;
    } else if (std.mem.eql(u8, ext, ".gltf")) {
        return Asset.GLTF;
    }
    return Asset.Unsupported;
}

fn get_file_extension(file_path: []const u8) []const u8 {
    var i: usize = file_path.len;
    while (i > 0) : (i -= 1) {
        if (file_path[i - 1] == '.') {
            return file_path[i - 1 ..];
        }
        if (file_path[i - 1] == '/' or file_path[i - 1] == '\\') {
            break;
        }
    }
    return "";
}
