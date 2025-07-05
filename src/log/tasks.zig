const std = @import("std");
const Allocator = std.mem.Allocator;

const Task = @import("zaturn-core").Task;

pub const LogLevel = enum {
    Debug,
    Warn,
    Error,
};

pub const LogTasks = enum {
    Log,
    IMLog,
    Benchmark,
    SubBenchmark,
    Submit,
};

pub const Benchmark = struct {
    context: []const u8,
    thread_id: u32,
    start: i128,

    pub fn to_task(self: *const Benchmark) Task {
        return Task.to_task(self);
    }

    pub fn name() []const u8 {
        return "Benchmark";
    }
};

pub const SubBenchmark = struct {
    context: []const u8,
    sub_context: []const u8,
    thread_id: u32,
    start: i128,

    pub fn to_task(self: *const SubBenchmark) Task {
        return Task.to_task(self);
    }

    pub fn name() []const u8 {
        return "SubBenchmark";
    }
};

pub const Log = struct {
    level: LogLevel,
    message: []const u8,
    context: []const u8,
    thread_id: u32,

    pub fn to_task(self: *const Log) Task {
        return Task.to_task(self);
    }

    pub fn deinit(self: *const Log, alloc: Allocator) void {
        // std.debug.print("{s}: Log deinit\n", .{self.context});
        alloc.free(self.message);
        return;
    }

    pub fn name() []const u8 {
        return "Log";
    }
};

pub const IMLog = struct {
    level: LogLevel,
    message: []const u8,
    context: []const u8,
    thread_id: u32,

    pub fn to_task(self: *const IMLog) Task {
        return Task.to_task(self);
    }

    pub fn deinit(self: *const IMLog, alloc: Allocator) void {
        // std.debug.print("{s}: IMLog deinit\n", .{self.context});
        alloc.free(self.message);
        return;
    }

    pub fn name() []const u8 {
        return "IMLog";
    }
};

pub const Submit = struct {
    context: []const u8,
    thread_id: u32,
    end: i128,

    pub fn to_task(self: *const Submit) Task {
        return Task.to_task(self);
    }

    pub fn name() []const u8 {
        return "Submit";
    }
};
