const core = @import("zaturn-core");
const Task = core.Task;

const tasks = @import("tasks.zig");
const RequestReload = tasks.RequestReload;

pub var mod: ?*core.Module = null;

pub fn request_app_reload() !void {
    const m = mod.?;

    m.context.send_task(RequestReload, .{})
        .detach();
}
