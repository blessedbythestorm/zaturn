const core = @import("zaturn-core");
const Task = core.Task;
const Context = core.Context;
const sdl = @import("sdl3");

const tasks = @import("tasks.zig");
const RequestExtensions = tasks.RequestExtensions;
const RequestProcAddress = tasks.RequestProcAddress;
const RequestSurface = tasks.RequestSurface;
const wnd = @import("window.zig");

pub var mod: ?*core.Module = null;

pub fn set_hook(hook: *core.Module) void {
    mod = hook;
}

pub fn request_extensions() [][*:0]const u8 {
    const m = mod.?;

    return m.context.send_task(RequestExtensions, .{})
        .wait_query([][*:0]const u8);
}

pub fn request_proc_address() *const anyopaque {
    const m = mod.?;

    return m.context.send_task(RequestProcAddress, .{})
        .wait_query(*const anyopaque);
}

pub fn request_surface(instance: usize) usize {
    const m = mod.?;

    return m.context.send_task(RequestSurface, .{ .vk_instance = instance })
        .wait_query(usize);
}
