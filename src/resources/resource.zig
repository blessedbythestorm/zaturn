const ShaderResource = struct {};

const TextureResource = struct {};

const MeshResource = struct {};

const GpuResource = union(enum) {
    Shader: ShaderResource,
    Texture: TextureResource,
    Mesh: MeshResource,
};

const ResourceState = enum {
    CPU_Memory,
    GPU_Memory,
    Unloaded,
};

const Resource = struct {
    ptr: *anyopaque,
    state: ResourceState,
    vtable: VTable,

    const VTable = struct {};

    pub fn init() Resource {}
};
