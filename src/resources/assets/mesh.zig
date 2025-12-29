const std = @import("std");

const Asset = @import("asset.zig").Asset;

pub const Mesh = struct {
    data: ?[]align(std.mem.page_size) u8,

    hash: []const u8,
    name: []const u8,
    vertices: []f32,
    indices: []u32,
    normals: []f32,
    uvs: []f32,

    const MeshHeader = packed struct {
        magic: [4]u8 = "MESH".*,
        version: u32 = 1,

        vertex_count: u32,
        index_count: u32,

        name_length: u32,
        name_offset: u64,

        vertices_offset: u64,
        indices_offset: u64,
        normals_offset: u64,
        uvs_offset: u64,

        total_size: u64,

        reserved: [16]u8 = std.mem.zeroes([16]u8),
    };

    pub fn to_asset(self: *Mesh) Asset {
        return Asset.create(self);
    }

    pub fn cache(self: *Mesh, writer: std.fs.File.Writer) !void {
        try writer.writeAll(self.name);
        try writer.writeAll(self.vertices);
        try writer.writeAll(self.indices);
        try writer.writeAll(self.normals);
        try writer.writeAll(self.uvs);
    }

    pub fn load(self: *Mesh, reader: std.fs.File.Reader) !void {
        const header = try reader.read(MeshHeader);
        if (std.mem.eql(u8, header.magic, "MESH")) |magic| {
            self.hash = magic;
        } else {
            return error.InvalidMagic;
        }

        self.name = try reader.readSlice(u8, header.name_length);
        self.vertices = try reader.readSlice(f32, header.vertex_count);
        self.indices = try reader.readSlice(u32, header.index_count);
        self.normals = try reader.readSlice(f32, header.vertex_count);
        self.uvs = try reader.readSlice(f32, header.vertex_count);

        self.data = try std.heap.page_allocator.alloc(u8, @intCast(header.total_size));
    }

    pub fn unload(self: *Mesh) void {
        if (self.data) |data| {
            std.mem.set(u8, data, 0);
            self.data = null;
        }
    }
};
