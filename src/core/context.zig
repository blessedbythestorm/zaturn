const std = @import("std");
const Thread = std.Thread;

const ContextTasks = @import("task.zig").ContextTasks;
const Future = @import("future.zig").Future;
const RequestClearPendingTasks = @import("task.zig").RequestClearPendingTasks;
const RequestShutdown = @import("task.zig").RequestShutdown;
const Task = @import("task.zig").Task;
const UnboundedChannel = @import("channel.zig").UnboundedChannel;

pub const Context = struct {
    name: []const u8,
    ptr: *anyopaque,
    allocator: std.mem.Allocator,
    vtable: VTable,

    thread: Thread,

    futures_allocator: std.mem.Allocator,
    futures_mutex: std.Thread.Mutex,

    tasks_allocator: std.mem.Allocator,
    tasks_mutex: std.Thread.Mutex,

    channel: UnboundedChannel(struct { Task, *Future }),

    should_shutdown: bool = false,
    initialized: bool = false,

    const VTable = struct {
        run_init: *const fn (*anyopaque) anyerror!void,
        run_task: *const fn (*anyopaque, *const Task, *Future) anyerror!void,
        run_deinit: *const fn (*anyopaque) anyerror!void,
    };

    pub fn init(self: *Context, comptime T: type, name: []const u8, ptr: *T, allocator: std.mem.Allocator) void {
        const ptr_info = @typeInfo(*T);

        const Generated = struct {
            pub fn run_init(pointer: *anyopaque) anyerror!void {
                const ptr_self: *T = @ptrCast(@alignCast(pointer));
                return ptr_info.pointer.child.run_init(ptr_self);
            }

            pub fn run_task(pointer: *anyopaque, task: *const Task, fut: *Future) anyerror!void {
                const ptr_self: *T = @ptrCast(@alignCast(pointer));
                return ptr_info.pointer.child.run_task(ptr_self, task, fut);
            }

            pub fn run_deinit(pointer: *anyopaque) anyerror!void {
                const ptr_self: *T = @ptrCast(@alignCast(pointer));
                return ptr_info.pointer.child.run_deinit(ptr_self);
            }
        };

        self.name = name;
        self.ptr = ptr;
        self.allocator = allocator;

        self.tasks_allocator = self.allocator;
        self.tasks_mutex = std.Thread.Mutex{};

        self.futures_allocator = self.allocator;
        self.futures_mutex = std.Thread.Mutex{};

        self.vtable = .{
            .run_init = Generated.run_init,
            .run_task = Generated.run_task,
            .run_deinit = Generated.run_deinit,
        };

        self.thread = undefined;

        self.channel = UnboundedChannel(struct { Task, *Future }).create();
        self.channel.init(allocator);

        self.initialized = true;
    }

    pub fn deinit(self: *Context) void {
        std.debug.assert(self.initialized);

        self.clear_pending_tasks();
        self.channel.deinit();

        self.initialized = false;
    }

    pub fn create_task(self: *Context, comptime T: type, init_data: T) Task {
        self.tasks_mutex.lock();
        defer self.tasks_mutex.unlock();

        if (!@hasDecl(T, "to_task")) @compileError("Task type missing 'to_task' method");
        if (!@hasDecl(T, "name")) @compileError("Task type missing 'name' method");

        const task = self.tasks_allocator.create(T) catch |err| {
            std.log.err("Failed to create task: {}", .{err});
            return undefined;
        };

        task.* = init_data;

        return task.to_task();
    }

    pub inline fn send_task(self: *Context, comptime T: type, init_data: T) *Future {
        self.futures_mutex.lock();
        defer self.futures_mutex.unlock();

        const task = self.create_task(T, init_data);
        const fut = Future.create(self.futures_allocator);
        self.channel.send(.{ task, fut }) catch |err| {
            std.log.err("Failed to send task: {}", .{err});
            return undefined;
        };

        return fut;
    }

    pub fn send(self: *Context, task: Task) *Future {
        self.futures_mutex.lock();
        defer self.futures_mutex.unlock();

        const fut = Future.create(self.futures_allocator);

        self.channel.send(.{ task, fut }) catch |err| {
            std.log.err("Failed to send task: {}", .{err});
            return undefined;
        };

        return fut;
    }

    pub fn send_priority(self: *Context, task: Task) *Future {
        self.futures_mutex.lock();
        defer self.futures_mutex.unlock();

        const fut = Future.create(self.futures_allocator);

        self.channel.send_priority(.{ task, fut }) catch |err| {
            std.log.err("Failed to send task: {}", .{err});
            return undefined;
        };

        return fut;
    }

    pub fn start(self: *Context) *Future {
        const fut = Future.create(self.futures_allocator);

        self.thread = Thread.spawn(.{}, thread_worker, .{ self, fut }) catch |err| {
            std.log.err("Failed to spawn thread: {}", .{err});
            @panic("Failed to spawn thread");
        };

        return fut;
    }

    pub fn request_shutdown(self: *Context) *Future {
        const shutdown_task = self.tasks_allocator.create(RequestShutdown) catch |err| {
            std.log.err("Failed to create shutdown task: {}", .{err});
            @panic("Failed to create shutdown task");
        };

        return self.send_priority(shutdown_task.to_task());
    }

    pub fn request_shutdown_relaxed(self: *Context) *Future {
        const shutdown_task = self.tasks_allocator.create(RequestShutdown) catch |err| {
            std.log.err("Failed to create shutdown task: {}", .{err});
            @panic("Failed to create shutdown task");
        };

        return self.send(shutdown_task.to_task());
    }

    pub fn request_clear_pending_tasks(self: *Context) *Future {
        const clear_tasks_task = self.tasks_allocator.create(RequestClearPendingTasks) catch |err| {
            std.log.err("Failed to create clear tasks task: {}", .{err});
            @panic("Failed to create clear tasks task");
        };

        return self.send_priority(clear_tasks_task.to_task());
    }

    fn clear_pending_tasks(self: *Context) void {
        var detached = self.channel.flush();
        while (detached) |current_node| {
            const task: Task, const fut: *Future = current_node.value;
            task.destroy(self.tasks_allocator);
            self.futures_allocator.destroy(fut);

            const next = current_node.prev;
            self.channel.allocator.destroy(current_node);
            detached = next;
        }
    }

    pub fn run_context_task(self: *Context, task: *const Task, fut: *Future) !bool {
        const task_entry = std.meta.stringToEnum(ContextTasks, task.name()) orelse return false;

        switch (task_entry) {
            ContextTasks.RequestShutdown => {
                self.should_shutdown = true;

                try fut.resolve(void, {});
                return true;
            },
            ContextTasks.RequestClearPendingTasks => {
                self.clear_pending_tasks();
                try fut.resolve(void, {});
                return true;
            },
        }

        return false;
    }

    pub fn thread_worker(self: *Context, ctx_fut: *Future) !void {
        try self.vtable.run_init(self.ptr);

        try ctx_fut.resolve(void, {});

        while (!self.should_shutdown) {
            if (self.channel.recv()) |message| {
                const task: Task, const task_fut: *Future = message;
                defer task.destroy(self.tasks_allocator);

                if (try self.run_context_task(&task, task_fut)) {
                    continue;
                }

                self.vtable.run_task(self.ptr, &task, task_fut) catch |err| {
                    std.log.err("Error running task: {}", .{err});
                };
            }
        }

        try self.vtable.run_deinit(self.ptr);
    }

    pub fn join(self: *Context) void {
        self.thread.join();
    }
};
