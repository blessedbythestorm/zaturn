const Allocator = @import("std").mem.Allocator;

const Task = @import("zaturn-core").Task;

pub const GpuTasks = enum { Render };

pub const Render = struct {
    pub fn to_task(self: *const Render) Task {
        return Task.to_task(self);
    }

    pub fn name() []const u8 {
        return "Render";
    }
};
