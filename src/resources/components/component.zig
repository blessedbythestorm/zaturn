const std = @import("std");

pub const Component = struct {
    allocator: std.mem.Allocator,
    ptr: *anyopaque,
    vtable: VTable,
    children: std.ArrayList(*Component),

    const VTable = struct {
        init: *const fn (*anyopaque) void,
        deinit: *const fn (*anyopaque) void,
        tick: *const fn (*anyopaque, f32) void,
    };

    pub fn create(comptime T: type, init_data: T, allocator: *std.mem.Allocator) Component {
        const comp = allocator.create(T) catch unreachable;
        comp.* = init_data;
        return generate_interface(comp);
    }

    pub fn from(ptr: *anyopaque) Component {
        return generate_interface(ptr);
    }

    fn generate_interface(ptr: *anyopaque) Component {
        const T = @Type(ptr);
        const ptr_info = @typeInfo(*anyopaque);

        const Generated = struct {
            pub fn init(pointer: *anyopaque) void {
                const ptr_self: *T = @ptrCast(pointer);
                ptr_info.pointer.child.init(ptr_self);
            }
            pub fn deinit(pointer: *anyopaque) void {
                const ptr_self: *T = @ptrCast(pointer);
                ptr_info.pointer.child.deinit(ptr_self);
            }
            pub fn tick(pointer: *anyopaque, dt: f32) void {
                const ptr_self: *T = @ptrCast(pointer);
                ptr_info.pointer.child.update(ptr_self, dt);
            }
        };

        return Component{
            .ptr = ptr,
            .vtable = VTable{
                .init = Generated.init,
                .deinit = Generated.deinit,
                .tick = Generated.tick,
            },
        };
    }

    pub fn init(self: *Component) void {
        self.vtable.init(self.ptr);
    }

    pub fn deinit(self: *Component) void {
        self.vtable.deinit(self.ptr);
    }

    pub fn tick(self: *Component, dt: f32) void {
        self.vtable.tick(self.ptr, dt);
    }

    pub fn as(self: *Component, comptime T: type) *T {
        return @ptrCast(self.ptr);
    }

    pub fn attach(self: *Component, other: *Component) void {
        self.children.append(other) catch unreachable;
    }
};
