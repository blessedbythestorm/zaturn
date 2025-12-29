const std = @import("std");
const builtin = @import("builtin");

const GLTF = @import("zgltf");
const ziggy = @import("ziggy");
const Map = ziggy.dynamic.Map;
const List = ziggy.dynamic.List;

const res = @import("../src/resources/_resources.zig");
const files = res.files;

const CacheRegistry = struct {
    source_files: Map(FileSource),
    assets: Map(AssetCache),
};

const FileSource = struct {
    type: FileType,
    source: []const u8,
    assets: [][]const u8,
    last_cached: i64,
};

pub const FileType = enum {
    Scene,
    RenderGraph,
    Image,
    GLTF,
    Unsupported,

    pub const ziggy_options = struct {
        pub fn stringify(value: FileType, _: ziggy.serializer.StringifyOptions, _: usize, _: usize, writer: anytype) !void {
            writer.print("@file(\"{s}\")", .{@tagName(value)}) catch |err| {
                std.debug.print("Failed to stringify file type: {}\n", .{err});
                return err;
            };
        }
    };
};

const AssetCache = struct {
    type: AssetType,
    name: []const u8,
    source: []const u8,
    cache: []const u8,
    last_cached: i64,
};

pub const AssetType = union(enum) {
    Mesh,
    Material,
    Image,
    Scene,

    pub const ziggy_options = struct {
        pub fn stringify(value: AssetType, _: ziggy.serializer.StringifyOptions, _: usize, _: usize, writer: anytype) !void {
            writer.print("@asset(\"{s}\")", .{@tagName(value)}) catch |err| {
                std.debug.print("Failed to stringify asset type: {}\n", .{err});
                return err;
            };
        }
    };
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
    const start_clear_cache_time = std.time.Instant.now();

    var arena = std.heap.ArenaAllocator.init(chosen_alloc.?);
    defer arena.deinit();

    const allocator = arena.allocator();

    var cache_dir = files.cacheDir(allocator, root_dir) catch |err| {
        std.debug.print("Failed to open cache directory: {}\n", .{err});
        return error.CacheDirNotFound;
    };

    const cache_dir_path = cache_dir.realpathAlloc(allocator, ".") catch |err| {
        std.debug.print("Failed to get cache directory path: {}\n", .{err});
        return error.CacheDirNotFound;
    };

    const cache_registry_path = std.fs.path.join(allocator, &[_][]const u8{ cache_dir_path, "registry.zgy" }) catch |err| {
        std.debug.print("Failed to create cache sources path: {}\n", .{err});
        return error.CreateCacheSourcesPathFailed;
    };

    const cache_meshes_dir = std.fs.path.join(allocator, &[_][]const u8{ cache_dir_path, "meshes" }) catch |err| {
        std.debug.print("Failed to create cache meshes path: {}\n", .{err});
        return error.CreateCacheMeshesPathFailed;
    };

    const cache_materials_dir = std.fs.path.join(allocator, &[_][]const u8{ cache_dir_path, "materials" }) catch |err| {
        std.debug.print("Failed to create cache materials path: {}\n", .{err});
        return error.CreateCacheMaterialsPathFailed;
    };

    const cache_images_dir = std.fs.path.join(allocator, &[_][]const u8{ cache_dir_path, "images" }) catch |err| {
        std.debug.print("Failed to create cache images path: {}\n", .{err});
        return error.CreateCacheImagesPathFailed;
    };

    const cache_scenes_dir = std.fs.path.join(allocator, &[_][]const u8{ cache_dir_path, "scenes" }) catch |err| {
        std.debug.print("Failed to create cache scenes path: {}\n", .{err});
        return error.CreateCacheScenesPathFailed;
    };

    cache_dir.close();

    std.fs.cwd().deleteTree(cache_dir_path) catch |err| {
        std.debug.print("Failed to clear cache directory: {}\n", .{err});
        return error.ClearCacheFailed;
    };

    std.fs.cwd().makeDir(cache_dir_path) catch |err| {
        std.debug.print("Failed to recreate cache directory: {}\n", .{err});
        return error.RecreateCacheDirFailed;
    };

    std.fs.cwd().makeDir(cache_meshes_dir) catch |err| {
        std.debug.print("Failed to create cache meshes directory: {}\n", .{err});
        return error.CreateCacheMeshesDirFailed;
    };

    std.fs.cwd().makeDir(cache_images_dir) catch |err| {
        std.debug.print("Failed to create cache images directory: {}\n", .{err});
        return error.CreateCacheImagesDirFailed;
    };

    std.fs.cwd().makeDir(cache_scenes_dir) catch |err| {
        std.debug.print("Failed to create cache scenes directory: {}\n", .{err});
        return error.CreateCacheScenesDirFailed;
    };

    std.fs.cwd().makeDir(cache_materials_dir) catch |err| {
        std.debug.print("Failed to create cache materials directory: {}\n", .{err});
        return error.CreateCacheMaterialsDirFailed;
    };

    const cache_registry = CacheRegistry{
        .source_files = .{},
        .assets = .{},
    };

    var write_file = cache_dir.createFile(cache_registry_path, .{ .truncate = true }) catch |err| {
        std.debug.print("Failed to create empty cache sources file: {}\n", .{err});
        return error.CreateCacheSourcesFileFailed;
    };
    defer write_file.close();

    ziggy.stringify(cache_registry, .{ .whitespace = .space_4 }, write_file.writer()) catch |err| {
        std.debug.print("Failed to write empty cache sources: {}\n", .{err});
        return error.WriteCacheSourcesFailed;
    };

    const end_clear_cache_time = @as(f128, @floatFromInt(std.time.nanoTimestamp() - start_clear_cache_time)) / 1_000_000.0;
    std.debug.print("Cache clear took: {d:6.3} ms\n", .{end_clear_cache_time});
}

pub fn build(root_dir: std.fs.Dir) !void {
    const start_cache_time = std.time.nanoTimestamp();

    var arena = std.heap.ArenaAllocator.init(chosen_alloc.?);
    defer arena.deinit();

    const allocator = arena.allocator();

    var cache_dir = files.cacheDir(allocator, root_dir) catch |err| {
        std.debug.print("Failed to open cache directory: {}\n", .{err});
        return error.CacheDirNotFound;
    };
    defer cache_dir.close();

    const cache_dir_path = cache_dir.realpathAlloc(allocator, ".") catch |err| {
        std.debug.print("Failed to get cache directory path: {}\n", .{err});
        return error.CacheDirNotFound;
    };

    std.debug.print("Cache dir path: {s}\n", .{cache_dir_path});

    const cache_registry_path = std.fs.path.join(allocator, &[_][]const u8{ cache_dir_path, "registry.zgy" }) catch |err| {
        std.debug.print("Failed to create cache registry path: {}\n", .{err});
        return error.CreateCacheSourcesPathFailed;
    };

    std.debug.print("Cache sources path: {s}\n", .{cache_registry_path});

    var cache_registry = files.readZiggy(CacheRegistry, allocator, cache_registry_path) catch |err| {
        std.debug.print("Failed to read cache registry: {}\n", .{err});
        return error.ReadCacheSourcesFailed;
    };

    var resources_dir = files.resourcesDir(allocator, root_dir) catch |err| {
        std.debug.print("Failed to open resources directory: {}\n", .{err});
        return error.ResourcesDirNotFound;
    };
    defer resources_dir.close();

    walkResources(allocator, &resources_dir, cache_dir_path, &cache_registry) catch |err| {
        std.debug.print("Failed to walk resources: {}\n", .{err});
        return error.WalkResourcesFailed;
    };

    var write_file = cache_dir.createFile(cache_registry_path, .{ .truncate = true }) catch |err| {
        std.debug.print("Failed to create cache sources file: {}\n", .{err});
        return error.CreateCacheSourcesFileFailed;
    };
    defer write_file.close();

    ziggy.stringify(cache_registry, .{ .whitespace = .space_4 }, write_file.writer()) catch |err| {
        std.debug.print("Failed to write cache sources: {}\n", .{err});
        return error.WriteCacheSourcesFailed;
    };

    const end_cache_time = @as(f128, @floatFromInt(std.time.nanoTimestamp() - start_cache_time)) / 1_000_000.0;
    std.debug.print("Cache took: {d:6.3} ms\n", .{end_cache_time});
}

fn hashPath(path: []const u8) u64 {
    var hasher = std.hash.Wyhash.init(0);
    hasher.update(path);
    return hasher.final();
}

fn randomHash() u64 {
    const timestamp = std.time.nanoTimestamp();
    var hasher = std.hash.Wyhash.init(@intCast(timestamp));
    hasher.update("random_seed");
    return hasher.final();
}

fn hash(allocator: std.mem.Allocator, val: ?[]const u8) ![]const u8 {
    const hash_value = if (val) |value|
        hashPath(value)
    else
        randomHash();

    return std.fmt.allocPrint(allocator, "{x}", .{hash_value}) catch |err| {
        std.debug.print("Failed to hash: {}\n", .{err});
        return err;
    };
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

fn walkResources(
    allocator: std.mem.Allocator,
    resources_dir: *std.fs.Dir,
    cache_dir_path: []const u8,
    cache_registry: *CacheRegistry,
) !void {
    var resource_walker = resources_dir.walk(allocator) catch |err| {
        std.debug.print("Failed to create resource walker: {}\n", .{err});
        return err;
    };
    defer resource_walker.deinit();

    while (try resource_walker.next()) |entry| {
        switch (entry.kind) {
            .file => {
                const curr_dir_path = resources_dir.realpathAlloc(allocator, ".") catch |err| {
                    std.debug.print("Failed to get current directory path: {}\n", .{err});
                    continue;
                };
                defer allocator.free(curr_dir_path);

                const file_path = std.fs.path.join(allocator, &[_][]const u8{ curr_dir_path, entry.path }) catch |err| {
                    std.debug.print("Failed to join path: {}\n", .{err});
                    continue;
                };

                cacheFile(allocator, cache_dir_path, file_path, cache_registry) catch |err| {
                    std.debug.print("Cache {}: {s}\n", .{ err, file_path });
                    continue;
                };
            },
            else => {},
        }
    }
}

pub fn cacheFile(allocator: std.mem.Allocator, cache_dir_path: []const u8, file_path: []const u8, cache_registry: *CacheRegistry) !void {
    const file_stat = std.fs.cwd().statFile(file_path) catch |err| {
        std.debug.print("Failed to stat file: {}\n", .{err});
        return error.FileStatFailed;
    };

    const modified = file_stat.mtime;

    const path_hash = hash(allocator, file_path) catch |err| {
        std.debug.print("Failed to hash file path: {}\n", .{err});
        return error.HashFailed;
    };

    // Check if the file is already cached and up to date
    if (cache_registry.source_files.fields.getPtr(path_hash)) |cache_source| {
        const file_modified: i64 = @intCast(modified);
        if (cache_source.last_cached <= file_modified) {
            return error.FileCacheUpToDate;
        } else {
            // If the file is cached but outdated, we need to update it
            // remove all assets associated with this file
            for (cache_source.assets) |asset_hash| {
                _ = cache_registry.assets.fields.orderedRemove(asset_hash);
            }
        }
    }

    const file = std.fs.openFileAbsolute(file_path, .{ .mode = .read_only }) catch |err| {
        std.debug.print("Failed to open file: {}\n", .{err});
        return error.FileOpenFailed;
    };
    defer file.close();

    const file_type = getFileType(file_path);

    var assets = std.ArrayList([]const u8).init(allocator);

    switch (file_type) {
        .Scene => {
            const cache_path = std.fs.path.join(allocator, &[_][]const u8{ cache_dir_path, "scenes", path_hash }) catch |err| {
                std.debug.print("Failed to create cache path for scene: {}\n", .{err});
                return error.CreateImageCachePathFailed;
            };

            cache_registry.assets.fields.put(allocator, path_hash, .{
                .type = .Scene,
                .name = getFileName(file_path),
                .source = file_path,
                .cache = cache_path,
                .last_cached = @intCast(modified),
            }) catch |err| {
                std.debug.print("Failed to cache image: {}\n", .{err});
                return error.ImageCacheFailed;
            };
        },
        .Image => {
            const cache_path = std.fs.path.join(allocator, &[_][]const u8{ cache_dir_path, "images", path_hash }) catch |err| {
                std.debug.print("Failed to create cache path for image: {}\n", .{err});
                return error.CreateImageCachePathFailed;
            };

            if (cache_registry.assets.fields.getPtr(path_hash)) |existing_asset| {
                if (!std.mem.eql(u8, existing_asset.source, file_path)) {
                    return error.ImageCachedFromAnotherSource;
                } else {
                    existing_asset.last_cached = @intCast(modified);
                    return error.ImageCacheUpToDate;
                }
            } else {
                cache_registry.assets.fields.put(allocator, path_hash, .{
                    .type = .Image,
                    .name = getFileName(file_path),
                    .source = file_path,
                    .cache = cache_path,
                    .last_cached = @intCast(modified),
                }) catch |err| {
                    std.debug.print("Failed to cache image: {}\n", .{err});
                    return error.ImageCacheFailed;
                };
            }
        },
        .GLTF => {
            const gltf_file_data = files.readToString(allocator, file_path) catch |err| {
                std.debug.print("Failed to read GLTF file: {}\n", .{err});
                return error.GLTFReadFailed;
            };
            defer allocator.free(gltf_file_data);

            var gltf = GLTF.init(allocator);
            defer gltf.deinit();

            gltf.parse(gltf_file_data) catch |err| {
                std.debug.print("Failed to parse GLTF file: {}\n", .{err});
                return error.GLTFParseFailed;
            };

            const base_path = std.fs.path.dirname(file_path) orelse return error.InvalidPath;

            var buffers_data = std.ArrayList([]align(4) const u8).init(allocator);

            for (gltf.data.buffers.items) |buffer_info| {
                const buffer_uri = buffer_info.uri orelse {
                    std.debug.print("Buffer URI is null in GLTF file: {s}\n", .{file_path});
                    continue;
                };

                const buffer_path_raw = std.fs.path.join(allocator, &[_][]const u8{ base_path, buffer_uri }) catch |err| {
                    std.debug.print("Failed to create buffer path: {}\n", .{err});
                    continue;
                };

                const buffer_path = validatePath(allocator, buffer_path_raw) catch |err| {
                    std.debug.print("Failed to validate buffer path: {}\n", .{err});
                    continue;
                };
                defer allocator.free(buffer_path);

                const buffer = file.readToEndAllocOptions(
                    allocator,
                    std.math.maxInt(usize),
                    null,
                    std.mem.Alignment.@"4",
                    null,
                ) catch |err| {
                    std.debug.print("Failed to read buffer data from {s}: {}\n", .{ buffer_path, err });
                    continue;
                };

                buffers_data.append(buffer) catch |err| {
                    std.debug.print("Failed to append buffer data: {}\n", .{err});
                    continue;
                };

                std.debug.print("Loaded buffer: {s} ({} bytes)\n", .{ buffer_uri, buffer.len });
            }

            for (gltf.data.images.items) |image| {
                const image_uri = image.uri orelse continue;

                const image_path_raw = std.fs.path.join(allocator, &[_][]const u8{ base_path, image_uri }) catch |err| {
                    std.debug.print("Failed to create image path: {}\n", .{err});
                    continue;
                };

                const image_path = validatePath(allocator, image_path_raw) catch |err| {
                    std.debug.print("Failed to validate image path: {}\n", .{err});
                    continue;
                };

                const image_hash = hash(allocator, image_path) catch |err| {
                    std.debug.print("Failed to hash image path: {}\n", .{err});
                    continue;
                };

                const cache_path = std.fs.path.join(allocator, &[_][]const u8{ cache_dir_path, "images", image_hash }) catch |err| {
                    std.debug.print("Failed to create cache path for image: {}\n", .{err});
                    continue;
                };

                assets.append(image_hash) catch |err| {
                    std.debug.print("Failed to append image hash to assets: {}\n", .{err});
                    continue;
                };

                if (cache_registry.assets.fields.getPtr(image_hash)) |existing_asset| {
                    if (!std.mem.eql(u8, existing_asset.source, image_path)) {
                        std.debug.print("Updating existing image asset source from {s} to {s}\n", .{ existing_asset.source, path_hash });
                        existing_asset.source = path_hash;
                        existing_asset.last_cached = @intCast(modified);
                    }
                }

                cache_registry.assets.fields.put(allocator, image_hash, .{
                    .type = .Image,
                    .name = getFileName(image_path_raw),
                    .source = path_hash,
                    .cache = cache_path,
                    .last_cached = @intCast(modified),
                }) catch |err| {
                    std.debug.print("Failed to cache image: {}\n", .{err});
                    continue;
                };
            }

            for (gltf.data.materials.items) |material| {
                const material_hash = hash(allocator, material.name) catch |err| {
                    std.debug.print("Failed to hash material name: {}\n", .{err});
                    continue;
                };

                const cache_path = std.fs.path.join(allocator, &[_][]const u8{ cache_dir_path, "materials", material_hash }) catch |err| {
                    std.debug.print("Failed to create cache path for material: {}\n", .{err});
                    continue;
                };

                assets.append(material_hash) catch |err| {
                    std.debug.print("Failed to append image hash to assets: {}\n", .{err});
                    continue;
                };

                cache_registry.assets.fields.put(allocator, material_hash, .{
                    .type = .Material,
                    .name = material.name,
                    .source = path_hash,
                    .cache = cache_path,
                    .last_cached = @intCast(modified),
                }) catch |err| {
                    std.debug.print("Failed to cache material: {}\n", .{err});
                    continue;
                };
            }

            for (gltf.data.meshes.items) |mesh| {
                const mesh_hash = hash(allocator, mesh.name) catch |err| {
                    std.debug.print("Failed to hash mesh name: {}\n", .{err});
                    continue;
                };

                const cache_path = std.fs.path.join(allocator, &[_][]const u8{ cache_dir_path, "meshes", mesh_hash }) catch |err| {
                    std.debug.print("Failed to create cache path for mesh: {}\n", .{err});
                    continue;
                };

                assets.append(mesh_hash) catch |err| {
                    std.debug.print("Failed to append mesh hash to assets: {}\n", .{err});
                    continue;
                };

                cache_registry.assets.fields.put(allocator, mesh_hash, .{
                    .type = .Mesh,
                    .name = mesh.name,
                    .source = path_hash,
                    .cache = cache_path,
                    .last_cached = @intCast(modified),
                }) catch |err| {
                    std.debug.print("Failed to cache mesh: {}\n", .{err});
                    continue;
                };
            }

            cache_registry.source_files.fields.put(allocator, path_hash, .{
                .type = .GLTF,
                .source = file_path,
                .assets = assets.items,
                .last_cached = @intCast(modified),
            }) catch |err| {
                std.debug.print("Failed to cache GLTF file: {}\n", .{err});
                return error.GLTFCacheFailed;
            };
        },
        else => {
            return error.UnsupportedAssetType;
        },
    }

    std.debug.print("Cached {s}: {s}\n", .{ path_hash, file_path });
}

const ExtensionInfo = struct { pattern: []const u8, file_type: FileType, is_suffix: bool };

const EXTENSIONS = [_]ExtensionInfo{
    .{ .pattern = ".scene.zgy", .file_type = .Scene, .is_suffix = true },
    .{ .pattern = ".rg.zgy", .file_type = .RenderGraph, .is_suffix = true },

    // Simple extensions (check as exact match)
    .{ .pattern = ".png", .file_type = .Image, .is_suffix = false },
    .{ .pattern = ".jpg", .file_type = .Image, .is_suffix = false },
    .{ .pattern = ".jpeg", .file_type = .Image, .is_suffix = false },
    .{ .pattern = ".hdr", .file_type = .Image, .is_suffix = false },
    .{ .pattern = ".gltf", .file_type = .GLTF, .is_suffix = false },
};

fn getFileType(file_path: []const u8) FileType {
    inline for (EXTENSIONS) |ext| {
        if (ext.is_suffix and std.mem.endsWith(u8, file_path, ext.pattern)) {
            return ext.file_type;
        }
    }

    const simple_ext = getFileExtension(file_path);
    inline for (EXTENSIONS) |ext| {
        if (!ext.is_suffix and std.mem.eql(u8, simple_ext, ext.pattern)) {
            return ext.file_type;
        }
    }

    return .Unsupported;
}

fn getFileName(file_path: []const u8) []const u8 {
    const basename = std.fs.path.basename(file_path);

    inline for (EXTENSIONS) |ext| {
        if (ext.is_suffix and std.mem.endsWith(u8, basename, ext.pattern)) {
            return basename[0 .. basename.len - ext.pattern.len];
        }
    }

    return std.fs.path.stem(basename);
}

fn getFileExtension(file_path: []const u8) []const u8 {
    const last_dot = std.mem.lastIndexOf(u8, file_path, ".") orelse return "";
    return file_path[last_dot..];
}
