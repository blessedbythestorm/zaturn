const std = @import("std");

pub fn UnboundedChannel(comptime T: type) type {
    return struct {
        allocator: std.mem.Allocator = undefined,

        front: ?*Node = null,
        back: ?*Node = null,
        len: usize = 0,
        max: usize = 1000,

        mutex: std.Thread.Mutex,
        not_empty: std.Thread.Condition,
        not_full: std.Thread.Condition,

        closed: bool = false,

        const Self = @This();

        pub const Node = struct {
            prev: ?*Node = null,
            next: ?*Node = null,
            value: T,
        };

        pub fn create() Self {
            return .{
                .mutex = std.Thread.Mutex{},
                .not_empty = std.Thread.Condition{},
                .not_full = std.Thread.Condition{},
            };
        }

        pub fn init(self: *Self, allocator: std.mem.Allocator) void {
            self.allocator = allocator;
        }

        pub fn deinit(self: *Self) void {
            _ = self; // autofix
        }

        pub fn send_priority(self: *Self, value: T) !void {
            self.mutex.lock();
            defer self.mutex.unlock();

            while (self.len >= self.max) {
                self.not_full.wait(&self.mutex);
            }

            const new_node = try self.allocator.create(Node);
            new_node.next = null;
            new_node.prev = null;
            new_node.value = value;

            if (self.len == 0) {
                self.front = new_node;
                self.back = new_node;
            } else if (self.front) |front| {
                front.next = new_node;
                new_node.prev = front;
                self.front = new_node;
            }

            self.len += 1;

            self.not_empty.signal();
        }

        pub fn send(self: *Self, value: T) !void {
            self.mutex.lock();
            defer self.mutex.unlock();

            while (self.len >= self.max) {
                self.not_full.wait(&self.mutex);
            }

            const new_node = try self.allocator.create(Node);
            new_node.next = null;
            new_node.prev = null;
            new_node.value = value;

            if (self.len == 0) {
                self.front = new_node;
                self.back = new_node;
            } else if (self.back) |back| {
                back.prev = new_node;
                new_node.next = back;
                self.back = new_node;
            }

            self.len += 1;

            self.not_empty.signal();
        }

        pub fn recv(self: *Self) ?T {
            self.mutex.lock();
            defer self.mutex.unlock();

            while (self.len == 0) {
                self.not_empty.wait(&self.mutex);
            }

            const value = self.front.?.value;

            if (self.len == 1) {
                self.allocator.destroy(self.front.?);
                self.front = null;
                self.back = null;
            } else if (self.front) |front| {
                self.front = front.prev;
                self.allocator.destroy(front);
                self.front.?.next = null;
            }

            self.len -= 1;
            self.not_full.signal();

            return value;
        }

        pub fn unwind(self: *Self) ?T {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.len == 0) {
                return null;
            }

            const value = self.front.?.value;

            var node = self.front;
            while (node) |current_node| {
                const next = current_node.prev;
                self.allocator.destroy(current_node);
                node = next;
            }

            self.front = null;
            self.back = null;

            self.len = 0;
            self.not_full.signal();

            return value;
        }

        pub fn flush(self: *Self) ?*Node {
            self.mutex.lock();
            defer self.mutex.unlock();

            const detached = self.front;
            // Reset the channel's queue.
            self.front = null;
            self.back = null;
            self.len = 0;
            self.not_full.signal();
            return detached;
        }
    };
}
