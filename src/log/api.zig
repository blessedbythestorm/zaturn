const std = @import("std");
const Thread = std.Thread;

const core = @import("zaturn-core");

const log = @import("logger.zig");
const log_tasks = @import("tasks.zig");
const Benchmark = log_tasks.Benchmark;
const SubBenchmark = log_tasks.SubBenchmark;
const Log = log_tasks.Log;
const IMLog = log_tasks.IMLog;
const Submit = log_tasks.Submit;
const LogLevel = log_tasks.LogLevel;

pub export var mod: *core.Module = undefined;

pub fn set_hook(hook: *core.Module) void {
    mod = hook;
}

pub fn bench(comptime context: []const u8) void {
    const log_mod = mod;

    log_mod.context.send_task(Benchmark, .{
        .context = context,
        .thread_id = Thread.getCurrentId(),
        .start = std.time.nanoTimestamp(),
    }).detach();
}

pub fn sub_bench(comptime context: []const u8, comptime sub_context: []const u8) void {
    const log_mod = mod;

    log_mod.context.send_task(SubBenchmark, .{
        .context = context,
        .sub_context = sub_context,
        .thread_id = Thread.getCurrentId(),
        .start = std.time.nanoTimestamp(),
    }).detach();
}

pub fn debug(comptime context: []const u8, comptime fmt: []const u8, args: anytype) void {
    const log_mod = mod;

    const message = std.fmt.allocPrint(log_mod.context.tasks_allocator, fmt, args) catch |fmt_err| {
        std.log.err("Failed to format debug message: {}", .{fmt_err});
        return;
    };

    log_mod.context.send_task(Log, .{
        .level = LogLevel.Debug,
        .context = context,
        .thread_id = Thread.getCurrentId(),
        .message = message,
    }).detach();
}

pub fn im_debug(comptime context: []const u8, comptime fmt: []const u8, args: anytype) void {
    const log_mod = mod;

    const message = std.fmt.allocPrint(log_mod.context.tasks_allocator, fmt, args) catch |fmt_err| {
        std.log.err("Failed to format debug message: {}", .{fmt_err});
        return;
    };

    log_mod.context.send_task(IMLog, .{
        .level = LogLevel.Debug,
        .context = context,
        .thread_id = Thread.getCurrentId(),
        .message = message,
    }).detach();
}

pub fn im_warn(comptime context: []const u8, comptime fmt: []const u8, args: anytype) void {
    const log_mod = mod;

    const message = std.fmt.allocPrint(log_mod.context.tasks_allocator, fmt, args) catch |fmt_err| {
        std.log.err("Failed to format warn message: {}", .{fmt_err});
        return;
    };

    log_mod.context.send_task(IMLog, .{
        .level = LogLevel.Warn,
        .context = context,
        .thread_id = Thread.getCurrentId(),
        .message = message,
    }).detach();
}

pub fn im_err(comptime context: []const u8, comptime fmt: []const u8, args: anytype) void {
    const log_mod = mod;

    const message = std.fmt.allocPrint(log_mod.context.tasks_allocator, fmt, args) catch |fmt_err| {
        std.log.err("Failed to format error message: {}", .{fmt_err});
        return;
    };

    log_mod.context.send_task(IMLog, .{
        .level = LogLevel.Error,
        .context = context,
        .thread_id = Thread.getCurrentId(),
        .message = message,
    }).detach();
}

pub fn err(comptime context: []const u8, comptime fmt: []const u8, args: anytype) void {
    const log_mod = mod;

    const message = std.fmt.allocPrint(log_mod.context.tasks_allocator, fmt, args) catch |fmt_err| {
        std.log.err("Failed to format error message: {}", .{fmt_err});
        return;
    };

    log_mod.context.send_task(Log, .{
        .level = LogLevel.Error,
        .context = context,
        .thread_id = Thread.getCurrentId(),
        .message = message,
    }).detach();
}

pub fn warn(comptime context: []const u8, comptime fmt: []const u8, args: anytype) void {
    const log_mod = mod;

    const message = std.fmt.allocPrint(log_mod.context.tasks_allocator, fmt, args) catch |fmt_err| {
        std.log.err("Failed to format warn message: {}", .{fmt_err});
        return;
    };

    log_mod.context.send_task(IMLog, .{
        .level = LogLevel.Warn,
        .context = context,
        .thread_id = Thread.getCurrentId(),
        .message = message,
    }).detach();
}

pub fn submit(comptime context: []const u8) void {
    const log_mod = mod;
    log_mod.context.send_task(Submit, .{
        .context = context,
        .thread_id = Thread.getCurrentId(),
        .end = std.time.nanoTimestamp(),
    }).detach();
}
