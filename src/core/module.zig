const std = @import("std");

const core = @import("zaturn-core");
const Context = core.Context;
const Task = core.Task;
const Future = core.Future;

pub const Modules = struct {
    allocator: std.mem.Allocator,
    modules: std.ArrayList(*Module),
    unmanaged_modules: std.ArrayList(*Module),

    pub fn init(allocator: std.mem.Allocator) *Modules {
        const modules = allocator.create(Modules) catch {
            @panic("Error creating modules");
        };

        modules.* = .{
            .allocator = allocator,
            .modules = std.ArrayList(*Module).init(allocator),
            .unmanaged_modules = std.ArrayList(*Module).init(allocator),
        };

        return modules;
    }

    pub fn add_unmanaged(self: *Modules, comptime T: type) void {
        const mod = Module.create(self.allocator);

        mod.init_with(T, @typeName(T)) catch {
            @panic("Error creating module");
        };

        self.unmanaged_modules.append(mod) catch {
            @panic("Error creating module");
        };
    }

    pub fn add(self: *Modules, comptime T: type) void {
        const mod = Module.create(self.allocator);

        mod.init_with(T, @typeName(T)) catch {
            @panic("Error creating module");
        };

        self.modules.append(mod) catch {
            @panic("Error creating module");
        };
    }

    pub fn get_managed(self: *Modules) []*Module {
        return self.modules.items;
    }

    pub fn context(self: *Modules, comptime T: type) *Context {
        for (self.modules.items) |mod| {
            if (std.mem.eql(u8, mod.context.name, @typeName(T))) {
                return mod.context;
            }
        }

        for (self.unmanaged_modules.items) |mod| {
            if (std.mem.eql(u8, mod.context.name, @typeName(T))) {
                return mod.context;
            }
        }

        @panic("Module not found");
    }

    pub fn module(self: *Modules, comptime T: type) *Module {
        for (self.modules.items) |mod| {
            if (std.mem.eql(u8, mod.context.name, @typeName(T))) {
                return mod;
            }
        }

        for (self.unmanaged_modules.items) |mod| {
            if (std.mem.eql(u8, mod.context.name, @typeName(T))) {
                return mod;
            }
        }

        @panic("Module not found");
    }

    pub fn get(self: *Modules, comptime T: type) *T {
        for (self.modules.items) |mod| {
            if (std.mem.eql(u8, mod.context.name, @typeName(T))) {
                return @ptrCast(@alignCast(mod.mod));
            }
        }

        for (self.unmanaged_modules.items) |mod| {
            if (std.mem.eql(u8, mod.context.name, @typeName(T))) {
                return @ptrCast(@alignCast(mod.mod));
            }
        }

        @panic("Module not found");
    }

    pub fn deinit(self: *Modules) void {
        for (self.modules.items) |mod| {
            mod.deinit();
            self.allocator.destroy(mod);
        }
        self.modules.deinit();

        for (self.unmanaged_modules.items) |mod| {
            mod.deinit();
            self.allocator.destroy(mod);
        }
        self.unmanaged_modules.deinit();

        self.allocator.destroy(self);
    }
};

pub const Module = struct {
    allocator: std.mem.Allocator,
    context: *Context = undefined,
    mod: *anyopaque = undefined,
    vtable: VTable = undefined,
    init: bool = false,

    const VTable = struct {
        fn_destroy: *const fn (pointer: *anyopaque, alloc: std.mem.Allocator) void,
    };

    pub fn create(allocator: std.mem.Allocator) *Module {
        const mod: *Module = allocator.create(Module) catch |err| {
            std.log.err("Failed to create module: {}", .{err});
            @panic("Error creating module");
        };

        mod.* = .{
            .allocator = allocator,
            .context = undefined,
            .mod = undefined,
            .vtable = undefined,
            .init = false,
        };

        return mod;
    }

    pub fn init_with(self: *Module, comptime T: type, name: []const u8) !void {
        const Generated = struct {
            pub fn destroy(pointer: *anyopaque, alloc: std.mem.Allocator) void {
                const ptr_self: *T = @ptrCast(@alignCast(pointer));
                alloc.destroy(ptr_self);
            }
        };

        const mod: *T = self.allocator.create(T) catch |err| {
            std.log.err("Failed to create module: {}", .{err});
            @panic("Error creating module");
        };

        mod.* = .{ .allocator = self.allocator };

        if (@hasDecl(T, "set_hook")) {
            T.set_hook(self);
        }

        self.mod = mod;

        self.context = self.allocator.create(Context) catch |err| {
            std.log.err("Failed to create context: {}", .{err});
            @panic("Error creating context");
        };

        self.context.init(T, name, @ptrCast(@alignCast(self.mod)), self.allocator);

        self.vtable = .{
            .fn_destroy = Generated.destroy,
        };

        self.init = true;
    }

    pub fn deinit(self: *Module) void {
        self.context.deinit();

        self.allocator.destroy(self.context);
        self.vtable.fn_destroy(self.mod, self.allocator);

        self.init = false;
    }
};
