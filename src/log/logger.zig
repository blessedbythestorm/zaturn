const std = @import("std");
const Thread = std.Thread;

const core = @import("zaturn-core");
const Context = core.Context;
const Task = core.Task;
const Future = core.Future;
const FutureResult = core.FutureResult;
const Buffer = core.Buffer;
const String = core.String;
const tasks = @import("zaturn-log");
const LogTasks = tasks.LogTasks;
const LogLevel = tasks.LogLevel;
const Submit = tasks.Submit;
const Benchmark = tasks.Benchmark;
const Log = tasks.Log;
const IMLog = tasks.IMLog;

const api = @import("api.zig");

pub const Logger = struct {
    allocator: std.mem.Allocator,

    thread_colors: std.AutoHashMap(u32, []const u8) = undefined,
    buffers: std.StringHashMap(Buffer) = undefined,
    benchmarks: std.StringHashMap(i128) = undefined,

    next_thread_color: u32 = 32,
    message_color: []const u8 = "\u{001b}[0;0m",
    error_color: []const u8 = "\u{001b}[31m",
    warn_color: []const u8 = "\u{001b}[33m",

    disabled: bool = false,

    pub fn set_hook(mod: *core.Module) void {
        api.mod = mod;
    }

    pub fn run_init(self: *Logger) !void {
        self.buffers = std.StringHashMap(Buffer).init(self.allocator);
        try self.buffers.ensureTotalCapacity(128);

        self.benchmarks = std.StringHashMap(i128).init(self.allocator);
        try self.benchmarks.ensureTotalCapacity(128);

        self.thread_colors = std.AutoHashMap(u32, []const u8).init(self.allocator);
        try self.thread_colors.ensureTotalCapacity(16);
        return;
    }

    pub fn run_deinit(self: *Logger) void {
        var color_iter = self.thread_colors.valueIterator();
        while (color_iter.next()) |color| {
            self.allocator.free(color.*);
        }

        var buffer_iter = self.buffers.valueIterator();
        while (buffer_iter.next()) |buffer| {
            buffer.clear();
        }

        self.buffers.deinit();
        self.benchmarks.deinit();
        self.thread_colors.deinit();
        return;
    }

    pub inline fn run_task(self: *Logger, task: *const Task, fut: *Future) !void {
        if (self.disabled) {
            return try fut.resolve(void, {});
        }

        const task_entry = std.meta.stringToEnum(LogTasks, task.name()) orelse
            return error.InvalidTask;

        switch (task_entry) {
            LogTasks.Benchmark => {
                const benchmark_task: *const Benchmark = @ptrCast(@alignCast(task.ptr));
                try self.add_benchmark(benchmark_task);
            },
            LogTasks.SubBenchmark => {
                // const subbenchmark_task: *const SubBenchmark = @ptrCast(@alignCast(task.ptr));
                // try self.add_subbenchmark(subbenchmark_task);
            },
            LogTasks.Log => {
                const log_task: *const Log = @ptrCast(@alignCast(task.ptr));
                try self.append_log(log_task);
            },
            LogTasks.IMLog => {
                const log_task: *const IMLog = @ptrCast(@alignCast(task.ptr));
                try self.immediate_log(log_task);
            },
            LogTasks.Submit => {
                const submit_task: *const Submit = @ptrCast(@alignCast(task.ptr));
                try self.submit(submit_task);
            },
        }

        try fut.resolve(void, {});
    }

    fn add_benchmark(self: *Logger, benchmark: *const Benchmark) !void {
        if (!self.benchmarks.contains(benchmark.context)) {
            try self.benchmarks.put(benchmark.context, benchmark.start);
        }
    }

    fn append_log(self: *Logger, log_task: *const Log) !void {
        if (self.buffers.getPtr(log_task.context)) |buffer| {
            try buffer.append(try self.get_message_color(log_task.level));
            try buffer.append(log_task.message);
            try buffer.append("\n");
        } else {
            try self.buffers.put(log_task.context, Buffer.initEmpty());

            if (self.buffers.getPtr(log_task.context)) |buffer| {
                try buffer.append(try self.get_message_color(log_task.level));
                try buffer.append(log_task.message);
                try buffer.append("\n");
            }
        }
    }

    fn immediate_log(self: *Logger, log_task: *const IMLog) !void {
        var fmt_str = try String.initWithFmt(
            self.allocator,
            "{s}{d}: {s}: \n{s}{s}\n",
            .{
                try self.get_thread_color(log_task.thread_id),
                log_task.thread_id,
                log_task.context,
                try self.get_message_color(log_task.level),
                log_task.message,
            },
        );
        defer fmt_str.deinit();

        try fmt_str.print();
    }

    fn submit(self: *Logger, submit_task: *const Submit) !void {
        const thread_color = try self.get_thread_color(submit_task.thread_id);

        var fmt_str = try String.initWithFmt(
            self.allocator,
            "{s}{d}: {s}: \n",
            .{
                thread_color,
                submit_task.thread_id,
                submit_task.context,
            },
        );
        defer fmt_str.deinit();

        if (self.consume_context_buffer(submit_task)) |context_buffer| {
            try fmt_str.append(context_buffer.src());
        }

        if (self.consume_context_benchmark(submit_task)) |elapsed_ms| {
            if (elapsed_ms < 1000.0) {
                try fmt_str.appendFmt("{s}Took: {d:6.3} ms\n", .{ thread_color, elapsed_ms });
            } else {
                const seconds: f128 = elapsed_ms / 1000.0;

                if (seconds < 60.0) {
                    try fmt_str.appendFmt("{s}Took: {d:6.3} s\n", .{ thread_color, seconds });
                } else {
                    const minutes: f128 = seconds / 60.0;
                    try fmt_str.appendFmt("{s}Took: {d:6.3} min\n", .{ thread_color, minutes });
                }
            }
        }

        try fmt_str.append("===================================\n");
        try fmt_str.print();
    }

    fn consume_context_buffer(self: *Logger, submit_task: *const Submit) ?Buffer {
        if (self.buffers.get(submit_task.context)) |context_buffer| {
            const buff = context_buffer;

            _ = self.buffers.remove(submit_task.context);

            return buff;
        }

        return null;
    }

    fn consume_context_benchmark(self: *Logger, submit_task: *const Submit) ?f128 {
        if (self.benchmarks.get(submit_task.context)) |start| {
            const elapsed_ms = @as(f128, @floatFromInt(submit_task.end - start)) / 1_000_000.0;

            _ = self.benchmarks.remove(submit_task.context);

            return elapsed_ms;
        }

        return null;
    }

    fn get_thread_color(self: *Logger, thread_id: u32) ![]const u8 {
        if (self.thread_colors.get(thread_id)) |color| {
            return color;
        } else {
            const color = try std.fmt.allocPrint(self.allocator, "\u{001b}[1;{d}m", .{self.next_thread_color});
            try self.thread_colors.put(thread_id, color);
            self.next_thread_color += 1;
            return color;
        }
    }

    fn get_message_color(self: *Logger, level: LogLevel) ![]const u8 {
        switch (level) {
            LogLevel.Error => return self.error_color,
            LogLevel.Warn => return self.warn_color,
            LogLevel.Debug => return self.message_color,
        }
    }
};
