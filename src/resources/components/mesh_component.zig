const za = @import("zalgebra");

const Component = @import("component.zig");
const Mesh = @import("assets/mesh.zig");

const MeshComponent = struct {
    mesh: *Mesh,
    transform: za.Mat4,

    pub fn to_component(self: *MeshComponent) Component {
        return Component.create(self);
    }

    pub fn init(self: *MeshComponent) void {
        _ = self; // autofix
    }

    pub fn deinit(self: *MeshComponent) void {
        _ = self; // autofix
    }

    pub fn tick(self: *MeshComponent, delta: f32) void {
        _ = delta; // autofix
        _ = self; // autofix
    }
};
