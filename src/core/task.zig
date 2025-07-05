const std = @import("std");
const Thread = std.Thread;
const assert = std.debug.assert;

pub const Task = struct {
    ptr: *const anyopaque,
    vtable: VTable,

    const VTable = struct {
        fn_name: *const fn () []const u8,
        fn_deinit: ?*const fn (*const anyopaque, std.mem.Allocator) void = null,
        fn_destroy: *const fn (*const anyopaque, std.mem.Allocator) void,
    };

    pub fn to_task(ptr: anytype) Task {
        const T = @TypeOf(ptr);
        const ptr_info = @typeInfo(T);

        const pointedType = @TypeOf(ptr.*);
        const has_deinit = @hasDecl(pointedType, "deinit");

        const Generated = struct {
            pub fn name() []const u8 {
                return ptr_info.pointer.child.name();
            }

            pub fn typename() []const u8 {
                return @typeName(T);
            }

            pub fn deinit(pointer: *const anyopaque, alloc: std.mem.Allocator) void {
                if (has_deinit) {
                    const ptr_self: T = @ptrCast(@alignCast(pointer));
                    ptr_info.pointer.child.deinit(ptr_self, alloc);
                }
            }

            pub fn destroy(pointer: *const anyopaque, alloc: std.mem.Allocator) void {
                const ptr_self: T = @ptrCast(@alignCast(pointer));
                alloc.destroy(ptr_self);
            }
        };

        const deinit_fn = if (has_deinit) Generated.deinit else null;

        return .{
            .ptr = ptr,
            .vtable = .{
                .fn_name = Generated.name,
                .fn_deinit = deinit_fn,
                .fn_destroy = Generated.destroy,
            },
        };
    }

    pub fn name(self: *const Task) []const u8 {
        return self.vtable.fn_name();
    }

    pub fn deinit(self: *const Task, alloc: std.mem.Allocator) void {
        if (self.vtable.fn_deinit) |fn_deinit| {
            fn_deinit(self.ptr, alloc);
        }
    }

    pub fn destroy(self: *const Task, alloc: std.mem.Allocator) void {
        self.deinit(alloc);
        return self.vtable.fn_destroy(self.ptr, alloc);
    }
};

pub const ContextTasks = enum {
    RequestShutdown,
    RequestClearPendingTasks,
};

pub const RequestShutdown = struct {
    pub fn to_task(self: *const RequestShutdown) Task {
        return Task.to_task(self);
    }

    pub fn name() []const u8 {
        return "RequestShutdown";
    }
};

pub const RequestClearPendingTasks = struct {
    pub fn to_task(self: *const RequestClearPendingTasks) Task {
        return Task.to_task(self);
    }

    pub fn name() []const u8 {
        return "RequestClearPendingTasks";
    }
};
