const std = @import("std");

pub const Futures = struct {
    futures: []?*Future,

    pub inline fn create(futs: []?*Future) Futures {
        return Futures{ .futures = futs };
    }

    pub fn wait(self: *const Futures) *const Futures {
        for (self.futures) |fut| {
            fut.?.awaited.store(true, std.builtin.AtomicOrder.seq_cst);
            fut.?.resolve_sem.post();
        }

        for (self.futures) |fut| {
            fut.?.await_sem.wait();
        }

        return self;
    }

    pub fn wait_ignore(self: *const Futures) void {
        for (self.futures) |fut| {
            fut.?.awaited.store(true, std.builtin.AtomicOrder.seq_cst);
            fut.?.resolve_sem.post();
        }

        for (self.futures) |fut| {
            fut.?.await_sem.wait();
            fut.?.ignore();
        }
    }

    pub inline fn query_single(self: *const Futures, comptime T: type, index: usize) T {
        const res = self.futures[index].?.query(T);
        self.futures[index] = null;
        return res;
    }

    pub inline fn discard(self: *const Futures) void {
        for (self.futures) |maybe_fut| {
            if (maybe_fut) |fut| {
                fut.ignore();
            }
        }
    }
};

pub const Future = struct {
    pub const FutureState = enum {
        Pending,
        Resolved,
        Rejected,
        Queried,
    };

    allocator: std.mem.Allocator,
    state: FutureState,

    await_sem: std.Thread.Semaphore,
    resolve_sem: std.Thread.Semaphore,
    awaited: std.atomic.Value(bool),

    result_ptr: ?*const anyopaque,
    fn_deinit_result: ?*const fn (*const anyopaque, *std.mem.Allocator) void,

    pub fn create(allocator: std.mem.Allocator) *Future {
        const fut = allocator.create(Future) catch |err| {
            std.log.err("Failed to create future: {}", .{err});
            std.process.exit(0);
        };

        fut.* = .{
            .allocator = allocator,
            .state = FutureState.Pending,
            .result_ptr = null,
            .await_sem = std.Thread.Semaphore{},
            .resolve_sem = std.Thread.Semaphore{},
            .fn_deinit_result = null,
            .awaited = std.atomic.Value(bool).init(false),
        };

        return fut;
    }

    pub fn detach(self: *Future) void {
        self.awaited.store(false, std.builtin.AtomicOrder.seq_cst);
        self.resolve_sem.post();
    }

    pub fn wait(self: *Future) *Future {
        self.awaited.store(true, std.builtin.AtomicOrder.seq_cst);
        self.resolve_sem.post();

        self.await_sem.wait();

        return self;
    }

    pub fn wait_query(self: *Future, comptime T: type) T {
        self.awaited.store(true, std.builtin.AtomicOrder.seq_cst);
        self.resolve_sem.post();

        self.await_sem.wait();

        return self.query(T);
    }

    pub fn wait_ignore(self: *Future) void {
        self.awaited.store(true, std.builtin.AtomicOrder.seq_cst);
        self.resolve_sem.post();

        self.await_sem.wait();

        self.ignore();
    }

    pub fn query(self: *Future, comptime T: type) T {
        if (T == void) {
            self.allocator.destroy(self);
            return {};
        } else {
            const value_ptr = self.result_ptr.?;
            const typed_ptr: *const T = @ptrCast(@alignCast(value_ptr));
            const value = typed_ptr.*;

            if (self.fn_deinit_result) |fn_deinit_result| {
                fn_deinit_result(value_ptr, &self.allocator);
            }

            self.allocator.destroy(self);
            return value;
        }
    }

    pub fn ignore(self: *Future) void {
        if (self.result_ptr) |result_ptr| {
            if (self.fn_deinit_result) |fn_deinit_result| {
                fn_deinit_result(result_ptr, &self.allocator);
            }
        } else {
            std.log.warn("Ignoring unresolved future", .{});
        }

        self.allocator.destroy(self);
    }

    pub fn resolve(self: *Future, comptime T: type, value: T) !void {
        const Generated = struct {
            pub fn deinit(pointer: *const anyopaque, allocator: *std.mem.Allocator) void {
                if (T == void) {
                    return;
                } else {
                    const data_ptr: *const T = @ptrCast(@alignCast(pointer));
                    allocator.destroy(data_ptr);
                }
            }
        };

        self.resolve_sem.wait();

        const is_awaited = self.awaited.load(std.builtin.AtomicOrder.seq_cst);

        if (is_awaited) {
            if (T == void) {
                self.state = FutureState.Resolved;
                self.result_ptr = undefined;
                self.fn_deinit_result = Generated.deinit;
                self.await_sem.post();
            } else {
                const mem = try self.allocator.create(T);
                mem.* = value;
                self.result_ptr = @ptrCast(mem);
                self.state = FutureState.Resolved;
                self.fn_deinit_result = Generated.deinit;
                self.await_sem.post();
            }
        } else {
            self.state = FutureState.Resolved;
            self.allocator.destroy(self);
        }
    }
};
