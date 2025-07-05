const za = @import("zalgebra");

const RootComponent = struct {
    transform: za.Mat4,

    pub fn init(self: *RootComponent) void {
        self.transform = za.Mat4.identity();
    }

    pub fn deinit(self: *RootComponent) void {
        _ = self; // autofix
    }

    pub fn tick(self: *RootComponent, delta: f32) void {
        _ = delta; // autofix
        _ = self; // autofix
    }
};
