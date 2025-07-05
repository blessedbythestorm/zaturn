const std = @import("std");
const fs = std.fs;

const log = @import("zaturn-log");

pub const c = @cImport({
    @cInclude("efsw/efsw.h");
});

pub const WatchEvent = enum {
    Created,
    Moved,
    Modified,
    Deleted,
};

pub const Watcher = struct {
    allocator: std.mem.Allocator,
    watcher: c.efsw_watcher,

    pub fn create(allocator: std.mem.Allocator) !Watcher {
        return Watcher{
            .allocator = allocator,
            .watcher = c.efsw_create(@intFromBool(true)),
        };
    }

    pub fn deinit(self: *Watcher) void {
        c.efsw_release(self.watcher);
    }

    pub fn start(self: *Watcher) void {
        c.efsw_watch(self.watcher);
    }

    pub fn add_directory(self: *Watcher, path: []const u8) void {
        const path_buf = self.allocator.dupeZ(u8, path) catch return;
        defer self.allocator.free(path_buf);
        _ = c.efsw_addwatch(self.watcher, path_buf, Watcher.detect_changes, 1, self);
    }

    pub fn callback(_: *Watcher) void {}

    pub fn detect_changes(watcher: c.efsw_watcher, id: c.efsw_watchid, dir_path: [*c]const u8, filename: [*c]const u8, action: c.enum_efsw_action, old_filename: [*c]const u8, user_data: ?*anyopaque) callconv(.c) void {
        _ = id; // autofix
        _ = old_filename; // autofix
        _ = watcher; // autofix

        const self: *Watcher = @ptrCast(@alignCast(user_data));

        const Action = enum(c_uint) {
            Created = c.EFSW_ADD,
            Moved = c.EFSW_MOVED,
            Modified = c.EFSW_MODIFIED,
            Deleted = c.EFSW_DELETE,
        };

        const act: Action = @enumFromInt(action);

        switch (act) {
            Action.Created => {
                log.im_debug("res-watch", "Watcher detected creation: {s}{s}", .{ dir_path, filename });
            },
            Action.Moved => {
                log.im_debug("res-watch", "Watcher detected move: {s}{s}", .{ dir_path, filename });
            },
            Action.Modified => {
                log.im_debug("res-watch", "Watcher detected modification: {s}{s}", .{ dir_path, filename });
            },
            Action.Deleted => {
                log.im_debug("res-watch", "Watcher detected deletion: {s}{s}", .{ dir_path, filename });
            },
        }

        self.callback();
    }
};
