const std = @import("std");
const builtin = @import("builtin");

pub const core = @import("zaturn-core");
const Module = core.Module;

pub const gpu = @import("zaturn-gpu");
const Gpu = gpu.Gpu;

pub const log = @import("zaturn-log");
pub const Logger = log.Logger;

const IMLog = log.IMLog;
const LogLevel = log.LogLevel;

const res = @import("zaturn-resources");
const Resources = res.Resources;
pub const wnd = @import("zaturn-window");
const Window = wnd.Window;

const Engine = struct {
    allocator: std.mem.Allocator,
    modules: *core.Modules,
    version: []const u8 = "0.0.1",

    pub fn init(allocator: std.mem.Allocator) *Engine {
        const engine = allocator.create(Engine) catch |err| {
            std.log.err("Failed to create engine: {}", .{err});
            @panic("Failed to create engine");
        };

        engine.* = .{
            .allocator = allocator,
            .modules = core.Modules.init(allocator),
        };

        return engine;
    }

    pub fn add_managed_module(self: *Engine, comptime T: type) void {
        try self.modules.add_managed(T) catch |err| {
            std.log.err("Failed to add managed module: {}", .{err});
            @panic("Failed to add managed module");
        };
    }

    pub fn add_unmanaged_module(self: *Engine, comptime T: type) !void {
        try self.modules.add_unmanaged(T) catch |err| {
            std.log.err("Failed to add unmanaged module: {}", .{err});
            @panic("Failed to add unmanaged module");
        };
    }

    pub fn start_module(self: *Engine, comptime T: type) !*core.Future {
        const mod = self.modules.context(T);
        if (mod == null) {
            return error.ModuleNotFound;
        }
        return mod.start();
    }

    pub fn deinit(self: *Engine) void {
        self.modules.deinit();
        self.allocator.destroy(self);
    }
};

pub const ZaturnApp = struct {
    shared_lib: std.DynLib,
    hook: *const fn (*core.Modules) callconv(.C) void = undefined,
    init: *const fn (*core.Modules) callconv(.C) void = undefined,
    tick: *const fn (*core.Modules, f128) callconv(.C) void = undefined,
    shutdown: *const fn (*core.Modules) callconv(.C) void = undefined,
};

pub fn load_app_shared() !ZaturnApp {
    var shared_lib = std.DynLib.open("app.dll") catch return error.FailedToLoadGame;
    const hook_fn = shared_lib.lookup(*const fn (*core.Modules) callconv(.C) void, "app_hook") orelse return error.GameHookNotFound;
    const init_fn = shared_lib.lookup(*const fn (*core.Modules) callconv(.C) void, "app_init") orelse return error.GameInitNotFound;
    const tick_fn = shared_lib.lookup(*const fn (*core.Modules, f128) callconv(.C) void, "app_tick") orelse return error.GameTickNotFound;
    const shutdown_fn = shared_lib.lookup(*const fn (*core.Modules) callconv(.C) void, "app_shutdown") orelse return error.GameShutdownNotFound;

    return ZaturnApp{
        .shared_lib = shared_lib,
        .hook = hook_fn,
        .init = init_fn,
        .tick = tick_fn,
        .shutdown = shutdown_fn,
    };
}

var debug_allocator: std.heap.DebugAllocator(.{ .thread_safe = true, .stack_trace_frames = 15 }) = .init;

pub fn main() !void {
    try init();
}

pub fn init() !void {
    const allocator, const is_debug = gpa: {
        if (builtin.os.tag == .wasi) break :gpa .{ std.heap.wasm_allocator, false };
        break :gpa switch (builtin.mode) {
            .Debug, .ReleaseSafe => .{ debug_allocator.allocator(), true },
            .ReleaseFast, .ReleaseSmall => .{ std.heap.smp_allocator, false },
        };
    };

    defer if (is_debug) {
        _ = debug_allocator.deinit();
    };

    const engine = Engine.init(allocator);
    defer engine.deinit();

    engine.modules.add_unmanaged(Logger);
    engine.modules
        .context(Logger)
        .start()
        .wait_ignore();

    log.bench("zaturn-init");

    log.im_debug("zaturn",
        \\
        \\    ________     __  ___________  ____  ____   _______   _____  ___
        \\   /"       )   /""\("     _   ")("  _||_ " | /"      \ (\"   \|"  \
        \\  (:   \___/   /    \)__/  \\__/ |   (  ) : ||:        ||.\\   \    |
        \\   \___  \    /' /\  \  \\_ /    (:  |  | . )|_____/   )|: \.   \\  |
        \\     __/  \\  //  __'  \|.  |     \\ \__/ //  //      / |.  \    \. |
        \\   /" \   :)/   /  \\  \\:  |     /\\ __ //\ |:  __   \ |    \    \ |
        \\  (_______/(___/    \___)\__|    (__________)|__|  \___) \___|\____\)
        \\
        \\  v{s}
        \\  blessedbythestorm
        \\
    , .{engine.version});

    var app = try load_app_shared();
    defer app.shared_lib.close();

    engine.modules.add(Resources);
    engine.modules.add(Window);
    engine.modules.add(Gpu);

    app.hook(engine.modules);

    var context_startups = [_]?*core.Future{
        engine.modules.context(Resources).start(),
        engine.modules.context(Window).start(),
        engine.modules.context(Gpu).start(),
    };

    core.Futures.create(&context_startups)
        .wait_ignore();

    app.init(engine.modules);

    log.submit("zaturn-init");

    log.bench("zaturn-runtime");
    {
        var last_time: i128 = std.time.nanoTimestamp();
        var is_app_dirty = false;
        var shutdown = false;
        while (!shutdown) {
            // log.bench("zaturn-runtime-frame");

            const now = std.time.nanoTimestamp();
            const delta: f128 = @as(f128, @floatFromInt(now)) - @as(f128, @floatFromInt(last_time)) / std.time.ns_per_s;
            last_time = now;

            app.tick(engine.modules, delta);

            const wnd_update = engine.modules
                .context(Window)
                .send_task(wnd.Update, .{});

            const gpu_render = engine.modules
                .context(Gpu)
                .send_task(gpu.Render, .{});

            const app_check = engine.modules
                .context(Resources)
                .send_task(res.ReloadCheck, .{});

            var frame_tasks = [_]?*core.Future{
                wnd_update,
                gpu_render,
                app_check,
            };

            const frame_results = core.Futures
                .create(&frame_tasks)
                .wait();

            shutdown = frame_results
                .query_single(bool, 0);

            is_app_dirty = frame_results
                .query_single(bool, 2);

            frame_results.discard();

            if (is_app_dirty) {
                engine.modules
                    .context(Logger)
                    .request_clear_pending_tasks()
                    .detach();

                app.shared_lib.close();

                engine.modules
                    .context(Resources)
                    .send_task(res.PrepareReload, .{})
                    .wait_ignore();

                app = try load_app_shared();
                app.hook(engine.modules);
            }

            // log.submit("zaturn-runtime-frame");
        }

        log.submit("zaturn-runtime");
    }

    engine
        .modules
        .context(Logger)
        .request_clear_pending_tasks()
        .wait_ignore();

    log.bench("zaturn-shutdown");
    {
        app.shutdown(engine.modules);

        for (engine.modules.get_managed()) |module| {
            module.context.request_shutdown()
                .detach();

            log.debug("zaturn-shutdown", "shutdown = {s}", .{module.context.name});
        }

        for (engine.modules.get_managed()) |module| {
            module.context.join();

            log.debug("zaturn-shutdown", "joined   = {s}", .{module.context.name});
        }

        log.submit("zaturn-shutdown");
    }

    engine.modules.context(Logger)
        .request_shutdown_relaxed()
        .wait_ignore();

    engine.modules.context(Logger)
        .join();
}
