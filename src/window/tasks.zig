const Allocator = @import("std").mem.Allocator;

const Task = @import("zaturn-core").Task;

pub const WndTasks = enum {
    Update,
    RequestExtensions,
    RequestProcAddress,
    RequestSurface,
};

pub const Update = struct {
    pub fn to_task(self: *const Update) Task {
        return Task.to_task(self);
    }

    pub fn name() []const u8 {
        return "Update";
    }
};

pub const RequestExtensions = struct {
    pub fn to_task(self: *const RequestExtensions) Task {
        return Task.to_task(self);
    }

    pub fn name() []const u8 {
        return "RequestExtensions";
    }
};

pub const RequestProcAddress = struct {
    pub fn to_task(self: *const RequestProcAddress) Task {
        return Task.to_task(self);
    }

    pub fn name() []const u8 {
        return "RequestProcAddress";
    }
};

pub const RequestSurface = struct {
    vk_instance: usize,

    pub fn to_task(self: *const RequestSurface) Task {
        return Task.to_task(self);
    }

    pub fn name() []const u8 {
        return "RequestSurface";
    }
};
