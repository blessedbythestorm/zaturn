const std = @import("std");

const core = @import("zaturn-core");
const za = core.zalgebra;
const yaml = @import("yaml");
const ziggy = @import("ziggy");

const Component = @import("components/component.zig").Component;
const files = @import("files.zig");
const Resource = @import("resource.zig").Resource;

pub const SceneNode = struct {
    name: []const u8,
    type: []const u8,
    children: []SceneNode,
};

pub const Scene = struct {
    root: SceneNode,
};
