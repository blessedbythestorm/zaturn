const std = @import("std");
const builtin = @import("builtin");

const core = @import("zaturn-core");
const Task = core.Task;
const Future = core.Future;
const log = @import("zaturn-log");
const toml = @import("toml");

const api = @import("api.zig");
const files = @import("files.zig");
const ResourceTasks = @import("tasks.zig").ResourceTasks;
const Scene = @import("scene.zig").Scene;
const Watcher = @import("watcher.zig").Watcher;

pub const Config = struct {
    engine: struct {
        install_dir: []const u8,
        resources_dir: []const u8,
    },
    project: struct {
        resources_dir: []const u8,
        scene: []const u8,
    },
};

pub const Resources = struct {
    allocator: std.mem.Allocator,
    watcher: Watcher = undefined,
    config: Config = undefined,
    active_scene: Scene = undefined,
    is_game_dirty: bool = false,
    is_game_reloaded: bool = false,

    pub fn set_hook(mod: *core.Module) void {
        api.mod = mod;
    }

    pub fn run_init(self: *Resources) !void {
        log.bench("resources-init");

        self.watcher = Watcher.create(self.allocator) catch |err| {
            log.err("Failed to create watcher: {}", .{err});
            @panic("Failed to create watcher");
        };

        const project_path = try std.fs.realpathAlloc(self.allocator, ".");
        defer self.allocator.free(project_path);

        const config_path = try std.fs.path.join(self.allocator, &[_][]const u8{ project_path, "zaturn.toml" });
        defer self.allocator.free(config_path);

        var parser = toml.Parser(Config).init(self.allocator);
        defer parser.deinit();

        const parsed_config = parser.parseFile(config_path) catch |err| {
            log.err("resources-init", "Failed to parse config.toml: {}", .{err});
            @panic("Failed to parse config.toml");
        };
        defer parsed_config.deinit();

        self.config = parsed_config.value;

        self.watcher.add_directory(self.config.project.resources_dir);
        self.watcher.add_directory(self.config.engine.resources_dir);
        self.watcher.start();

        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();

        const scene_path = try std.fs.path.join(self.allocator, &[_][]const u8{ self.config.project.resources_dir, self.config.project.scene });
        defer self.allocator.free(scene_path);

        self.active_scene = try files.readZiggy(Scene, self.allocator, scene_path);

        log.debug("resources-init",
            \\watcher = {?x}
            \\config  = {s}
            \\project = {s}
            \\project = {s}
            \\scene   = {s}
            \\engine  = {s}
            \\engine  = {s}
        , .{
            self.watcher.watcher,
            config_path,
            project_path,
            self.config.project.resources_dir,
            scene_path,
            self.config.engine.install_dir,
            self.config.engine.resources_dir,
        });

        log.submit("resources-init");
    }

    pub fn run_deinit(self: *Resources) !void {
        log.bench("resources-deinit");

        self.watcher.deinit();

        log.submit("resources-deinit");
    }

    pub fn run_task(self: *Resources, task: *const Task, fut: *Future) !void {
        const task_entry: ResourceTasks = std.meta.stringToEnum(ResourceTasks, task.name()) orelse
            return error.InvalidTask;

        switch (task_entry) {
            ResourceTasks.RequestReload => {
                _ = try std.Thread.spawn(.{}, Resources.reload_app, .{self});
                return try fut.resolve(void, {});
            },
            ResourceTasks.ReloadCheck => {
                if (self.is_game_dirty) {
                    self.is_game_dirty = false;
                    return try fut.resolve(bool, true);
                }
                return try fut.resolve(bool, false);
            },
            ResourceTasks.PrepareReload => {
                var bin_dir = try files.binDir(self.allocator);
                defer bin_dir.close();

                var lib_dir = try files.binLibDir(self.allocator);
                defer lib_dir.close();

                files.delete(&bin_dir, "app.dll");
                files.delete(&bin_dir, "app.pdb");
                files.delete(&lib_dir, "app.lib");
                files.rename(&bin_dir, "app_reload.dll", "app.dll");
                files.rename(&bin_dir, "app_reload.pdb", "app.pdb");
                files.rename(&lib_dir, "app_reload.lib", "app.lib");
            },
        }

        try fut.resolve(void, {});
    }

    fn reload_app(self: *Resources) !void {
        const release = if (builtin.mode == .Debug) "-Doptimize=Debug" else "-Doptimize=ReleaseFast";
        var reload_args = [_][]const u8{ "zig", "build", release, "-Dreload" };
        var reload_proc = std.process.Child.init(&reload_args, self.allocator);
        try reload_proc.spawn();
        _ = try reload_proc.wait();
        self.is_game_dirty = true;
    }
};
