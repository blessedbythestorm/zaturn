const std = @import("std");

const core = @import("zaturn-core");
const Context = core.Context;
const Task = core.Task;
const Future = core.Future;
const FutureResult = core.FutureResult;
const log = @import("zaturn-log");
const res = @import("zaturn-resources");
const sdl = @import("sdl3");
const SDLWindow = sdl.video.Window;

const api = @import("api.zig");
const wnd = @import("_window.zig");
pub const WndTasks = wnd.WndTasks;
const Update = wnd.Update;
const RequestSurface = wnd.RequestSurface;

pub const Window = struct {
    allocator: std.mem.Allocator,
    window: sdl.video.Window = undefined,

    pub fn set_hook(mod: *core.Module) void {
        api.mod = mod;
    }

    pub fn run_init(self: *Window) !void {
        log.bench("window-init");

        try sdl.init(.{ .video = true });
        self.window = try sdl.video.Window.init("Zaturn", 800, 600, .{ .vulkan = true });

        log.debug("window-init",
            \\window = {*}
        , .{&self.window});
        log.submit("window-init");
    }

    pub fn run_deinit(self: *Window) !void {
        log.bench("window-shutdown");

        self.window.deinit();
        sdl.quit(.{ .video = true });

        log.submit("window-shutdown");
    }

    pub inline fn run_task(self: *Window, task: *const Task, fut: *Future) !void {
        const task_entry = std.meta.stringToEnum(WndTasks, task.name()) orelse return error.InvalidTask;

        switch (task_entry) {
            .Update => {
                const update_task: *const Update = @ptrCast(@alignCast(task.ptr));
                defer self.allocator.destroy(update_task);

                while (sdl.events.poll()) |event| {
                    switch (event) {
                        .quit => {
                            return try fut.resolve(bool, true);
                        },
                        .key_down => {
                            if (event.key_down.key) |key| {
                                switch (key) {
                                    sdl.keycode.Keycode.r => {
                                        try res.request_app_reload();
                                    },
                                    sdl.keycode.Keycode.escape => {
                                        return try fut.resolve(bool, true);
                                    },
                                    else => {},
                                }
                            }
                        },
                        else => {},
                    }
                }
                return try fut.resolve(bool, false);
            },
            WndTasks.RequestExtensions => {
                return try fut.resolve([]const [*:0]const u8, get_vk_window_extensions());
            },
            WndTasks.RequestProcAddress => {
                return try fut.resolve(*const anyopaque, get_vk_proc_address());
            },
            WndTasks.RequestSurface => {
                const request_surface_task: *const RequestSurface = @ptrCast(@alignCast(task.ptr));
                return try fut.resolve(usize, self.create_vk_surface(request_surface_task.vk_instance));
            },
        }
    }

    fn get_vk_proc_address() *const anyopaque {
        const loader = sdl.vulkan.getVkGetInstanceProcAddr() catch |err| {
            log.err("vulkan-init", "Failed to get Vulkan instance proc address: {}", .{err});
            return undefined;
        };
        return loader;
    }

    fn get_vk_window_extensions() []const [*:0]const u8 {
        const exts = sdl.vulkan.getInstanceExtensions() catch |err| {
            log.err("vulkan-init", "Failed to get Vulkan instance extensions: {}", .{err});
            return &[_][*:0]const u8{};
        };
        return exts;
    }

    fn create_vk_surface(self: *Window, instance: usize) usize {
        const vk_instance: sdl.vulkan.Instance = @ptrFromInt(instance);
        const surface = sdl.vulkan.Surface.init(self.window, vk_instance, null) catch |err| {
            log.err("vulkan-init", "Failed to create Vulkan surface: {}", .{err});
            return undefined;
        };
        const vk_surface: usize = @intFromPtr(surface.surface);
        return vk_surface;
    }
};
