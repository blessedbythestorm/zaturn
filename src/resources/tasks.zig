const Task = @import("zaturn-core").Task;

pub const ResourceTasks = enum {
    RequestReload,
    ReloadCheck,
    PrepareReload,
};

pub const RequestReload = struct {
    pub fn to_task(self: *const RequestReload) Task {
        return Task.to_task(self);
    }

    pub fn name() []const u8 {
        return "RequestReload";
    }
};

pub const ReloadCheck = struct {
    pub fn to_task(self: *const ReloadCheck) Task {
        return Task.to_task(self);
    }

    pub fn name() []const u8 {
        return "ReloadCheck";
    }
};

pub const PrepareReload = struct {
    pub fn to_task(self: *const PrepareReload) Task {
        return Task.to_task(self);
    }

    pub fn name() []const u8 {
        return "PrepareReload";
    }
};
