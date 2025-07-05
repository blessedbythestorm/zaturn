const std = @import("std");

const core = @import("zaturn-core");
const Context = core.Context;
const Task = core.Task;
const Future = core.Future;
const FutureResult = core.FutureResult;
const log = @import("zaturn-log");
const vk = @import("vulkan-zig");
const wnd = @import("zaturn-window");

const gpu = @import("_gpu.zig");
const GpuTasks = gpu.GpuTasks;
const Render = gpu.Render;
const vkctx = @import("vk_context.zig");
const VKContext = vkctx.VKContext;

pub const Gpu = struct {
    allocator: std.mem.Allocator,
    vkctx: *vkctx.VKContext = undefined,

    pub fn create(allocator: std.mem.Allocator) *Gpu {
        const gpu_mod = allocator.create(Gpu) catch |err| {
            log.err("gpu-init", "Failed to create GPU module: {}", .{err});
            @panic("Failed to create GPU module");
        };
        gpu_mod.* = .{ .allocator = allocator };
        return gpu_mod;
    }

    pub fn run_init(self: *Gpu) !void {
        log.bench("vulkan-init");
        defer log.submit("vulkan-init");

        self.vkctx = vkctx.VKContext.init(self.allocator) catch |err| {
            log.err("vulkan-init", "Failed to initialize Vulkan context: {}", .{err});
            @panic("Failed to initialize Vulkan context");
        };
    }

    pub fn run_deinit(self: *Gpu) !void {
        log.bench("vulkan-shutdown");
        defer log.submit("vulkan-shutdown");

        self.vkctx.deinit();
        self.allocator.destroy(self.vkctx);
    }

    pub inline fn run_task(_: *Gpu, task: *const Task, fut: *Future) !void {
        _ = std.meta.stringToEnum(GpuTasks, task.name()) orelse return error.InvalidTask;

        try fut.resolve(void, {});
    }
};
