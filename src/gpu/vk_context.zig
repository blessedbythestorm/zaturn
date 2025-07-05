const std = @import("std");

const log = @import("zaturn-log");
const vk = @import("vulkan-zig");
const BaseLoader = vk.BaseWrapper;
const InstanceLoader = vk.InstanceWrapper;
const DeviceLoader = vk.DeviceWrapper;
const Instance = vk.InstanceProxy;
const Device = vk.DeviceProxy;
const CommandBuffer = vk.CommandBufferProxy;
const wnd = @import("zaturn-window");

const vkctx_api: []const vk.ApiInfo = &.{
    vk.features.version_1_0,
    vk.features.version_1_1,
    vk.features.version_1_2,
    vk.features.version_1_3,
    vk.features.version_1_4,
    vk.extensions.ext_debug_utils,
    vk.extensions.khr_surface,
    vk.extensions.khr_swapchain,
};

const instance_extensions_info: []const vk.ApiInfo = &.{
    vk.extensions.ext_debug_utils,
};

const device_extensions_info: []const vk.ApiInfo = &.{
    vk.extensions.khr_swapchain,
};

pub extern fn vkGetInstanceProcAddr(
    instance: vk.Instance,
    p_name: [*:0]const u8,
) callconv(vk.vulkan_call_conv) vk.PfnVoidFunction;

pub const VKContext = struct {
    allocator: std.mem.Allocator,
    vkb: BaseLoader,
    vki: *InstanceLoader,
    vkd: *DeviceLoader,

    instance: Instance = undefined,
    debug: vk.DebugUtilsMessengerEXT = undefined,
    device: Device = undefined,
    surface: vk.SurfaceKHR = undefined,

    pub fn init(allocator: std.mem.Allocator) !*VKContext {
        const ctx = allocator.create(VKContext) catch |err| {
            log.err("vulkan-init", "Failed to allocate VKContext: {}", .{err});
            return error.VulkanContext;
        };

        ctx.* = .{
            .allocator = allocator,
            .vkb = BaseLoader.load(vkGetInstanceProcAddr),
            .vki = try allocator.create(InstanceLoader),
            .vkd = try allocator.create(DeviceLoader),
        };

        try ctx.create_instance();
        try ctx.create_device();

        return ctx;
    }

    pub fn deinit(self: *VKContext) void {
        self.device.deviceWaitIdle() catch |err| {
            log.err("vulkan-shutdown", "Failed to wait for device idle: {}", .{err});
        };

        self.device.destroyDevice(null);
        self.instance.destroySurfaceKHR(self.surface, null);
        self.instance.destroyDebugUtilsMessengerEXT(self.debug, null);
        self.instance.destroyInstance(null);

        self.allocator.destroy(self.vkd);
        self.allocator.destroy(self.vki);
    }

    fn create_instance(self: *VKContext) !void {
        const debug_info = vk.DebugUtilsMessengerCreateInfoEXT{
            .message_severity = vk.DebugUtilsMessageSeverityFlagsEXT{
                .verbose_bit_ext = false,
                .info_bit_ext = false,
                .warning_bit_ext = true,
                .error_bit_ext = true,
            },
            .message_type = vk.DebugUtilsMessageTypeFlagsEXT{
                .general_bit_ext = true,
                .validation_bit_ext = true,
                .performance_bit_ext = true,
            },
            .pfn_user_callback = &vk_debug,
            .p_user_data = null,
            .p_next = null,
        };

        const app_info = vk.ApplicationInfo{
            .p_engine_name = "zaturn",
            .engine_version = @bitCast(vk.makeApiVersion(0, 0, 0, 1)),
            .p_application_name = "zatvis",
            .application_version = @bitCast(vk.makeApiVersion(0, 0, 0, 1)),
            .api_version = @bitCast(vk.API_VERSION_1_4),
            .p_next = &debug_info,
        };

        const instance_exts = self.get_instance_extensions() catch |err| {
            log.err("vulkan-init", "Failed to get instance extensions: {}", .{err});
            return error.VulkanInstance;
        };
        defer self.allocator.free(instance_exts);

        const instance_info = vk.InstanceCreateInfo{
            .p_application_info = &app_info,
            .enabled_extension_count = @intCast(instance_exts.len),
            .pp_enabled_extension_names = instance_exts.ptr,
            .enabled_layer_count = 0,
            .pp_enabled_layer_names = null,
            .p_next = null,
        };

        const inst = self.vkb.createInstance(&instance_info, null) catch |err| {
            log.err("vulkan-init", "Failed to create instance: {}", .{err});
            return error.VulkanInstance;
        };

        const instance_proc_addr = self.vkb.dispatch.vkGetInstanceProcAddr orelse {
            log.err("vulkan-init", "Failed to load instance functions.", .{});
            return error.InstanceLoader;
        };

        self.vki.* = InstanceLoader.load(inst, instance_proc_addr);
        self.instance = Instance.init(inst, self.vki);

        self.debug = self.instance.createDebugUtilsMessengerEXT(&debug_info, null) catch |err| {
            log.err("vulkan-init", "Failed to create debug messenger: {}", .{err});
            return error.DebugMessenger;
        };

        const instance_handle: usize = @intFromEnum(self.instance.handle);
        const surface = wnd.request_surface(instance_handle);
        self.surface = @enumFromInt(surface);

        log.debug("vulkan-init",
            \\instance           = {x}
            \\debug              = {x}
            \\surface            = {x}
        , .{ self.instance.handle, self.debug, self.surface });
    }

    pub fn create_device(self: *VKContext) !void {
        const physical_device, const queue_infos = self.get_physical_device() catch |err| {
            log.err("vulkan-init", "Failed to get physical device: {}", .{err});
            return error.PhysicalDevice;
        };

        const device_props = self.instance.getPhysicalDeviceProperties(physical_device);

        const device_exts = self.get_device_extensions() catch |err| {
            log.err("vulkan-init", "Failed to get device extensions: {}", .{err});
            return error.DeviceExtensions;
        };
        defer self.allocator.free(device_exts);

        for (device_exts) |ext| {
            log.debug("vulkan-init", "device extension   = {s}", .{ext});
        }

        var device_info = vk.DeviceCreateInfo{
            .queue_create_info_count = 1,
            .p_queue_create_infos = &queue_infos,
            .enabled_extension_count = @intCast(device_exts.len),
            .pp_enabled_extension_names = device_exts.ptr,
            .enabled_layer_count = 0,
            .pp_enabled_layer_names = null,
            .p_next = null,
        };

        const dev = self.instance.createDevice(physical_device, &device_info, null) catch |err| {
            log.err("vulkan-init", "failed to create device: {}", .{err});
            return error.Device;
        };

        const device_proc_addr = self.instance.wrapper.dispatch.vkGetDeviceProcAddr orelse {
            log.err("vulkan-init", "Failed to load device functions.", .{});
            return error.DeviceLoader;
        };

        self.vkd.* = try DeviceLoader.load(dev, device_proc_addr);
        self.device = Device.init(dev, self.vkd);

        log.debug("vulkan-init",
            \\device             = {s}
            \\device             = {x}
        , .{ device_props.device_name, self.device.handle });
    }

    // --- Private helper functions ---

    fn get_instance_extensions(self: *VKContext) ![]const [*:0]const u8 {
        var ext_list = std.ArrayList([*:0]const u8).init(self.allocator);
        for (instance_extensions_info) |ext| {
            try ext_list.append(ext.name);
        }
        for (wnd.request_extensions()) |ext| {
            try ext_list.append(ext);
        }
        for (ext_list.items) |ext| {
            log.debug("vulkan-init", "instance extension = {s}", .{ext});
        }
        return try ext_list.toOwnedSlice();
    }

    fn get_device_extensions(self: *VKContext) ![]const [*:0]const u8 {
        var ext_list = std.ArrayList([*:0]const u8).init(self.allocator);
        for (device_extensions_info) |ext| {
            try ext_list.append(ext.name);
        }
        return try ext_list.toOwnedSlice();
    }

    fn get_physical_device(self: *VKContext) !struct { vk.PhysicalDevice, [2]vk.DeviceQueueCreateInfo } {
        const pdevs = self.instance.enumeratePhysicalDevicesAlloc(self.allocator) catch |err| {
            log.err("vulkan-init", "Failed to enumerate physical devices: {}", .{err});
            return error.PhysicalDeviceUnavailable;
        };
        defer self.allocator.free(pdevs);

        if (pdevs.len == 0) {
            log.err("vulkan-init", "No physical devices found", .{});
            return error.PhysicalDeviceUnavailable;
        }

        for (pdevs) |pdev| {
            const device_props = self.instance.getPhysicalDeviceProperties(pdev);
            log.debug("vulkan-init",
                \\
                \\device option      = {s}
            , .{device_props.device_name});

            if (self.check_extensions_support(pdev) and self.check_surface_support(pdev, self.surface)) {
                const queue_infos = self.select_physical_device_queues(pdev, self.surface) catch |err| {
                    log.err("vulkan-init", "Failed to select physical device queues: {}", .{err});
                    return error.PhysicalDeviceUnavailable;
                };

                return .{ pdev, queue_infos };
            }
        }

        return error.PhysicalDeviceUnavailable;
    }

    fn check_extensions_support(self: *VKContext, pdev: vk.PhysicalDevice) bool {
        const ext_list = self.get_device_extensions() catch |err| {
            log.err("vulkan-init",
                \\Failed to get device extensions: {}
                \\Make sure to enable the required extensions.
            , .{err});
            return false;
        };
        defer self.allocator.free(ext_list);

        const propsv = self.instance.enumerateDeviceExtensionPropertiesAlloc(pdev, null, self.allocator) catch |err| {
            log.err("vulkan-init", "failed to enumerate device extension properties: {}", .{err});
            return false;
        };
        defer self.allocator.free(propsv);

        for (ext_list) |ext| {
            if (!VKContext.is_extension_supported(ext, propsv)) return false;
        }
        return true;
    }

    fn check_surface_support(self: *VKContext, pdev: vk.PhysicalDevice, surface: vk.SurfaceKHR) bool {
        const surface_formats = self.instance.getPhysicalDeviceSurfaceFormatsAllocKHR(pdev, surface, self.allocator) catch |err| {
            log.err("vulkan-init", "failed to get surface formats: {}", .{err});
            return false;
        };
        defer self.allocator.free(surface_formats);

        const present_modes = self.instance.getPhysicalDeviceSurfacePresentModesAllocKHR(pdev, surface, self.allocator) catch |err| {
            log.err("vulkan-init", "failed to get surface present modes: {}", .{err});
            return false;
        };
        defer self.allocator.free(present_modes);

        return surface_formats.len > 0 and present_modes.len > 0;
    }

    fn is_extension_supported(ext: [*:0]const u8, propsv: []vk.ExtensionProperties) bool {
        for (propsv) |prop| {
            const prop_name = std.mem.sliceTo(&prop.extension_name, 0);
            if (std.mem.eql(u8, std.mem.span(ext), prop_name)) {
                return true;
            }
        }
        return false;
    }

    fn select_physical_device_queues(self: *VKContext, pdev: vk.PhysicalDevice, surface: vk.SurfaceKHR) ![2]vk.DeviceQueueCreateInfo {
        const queue_props = self.instance.getPhysicalDeviceQueueFamilyPropertiesAlloc(pdev, self.allocator) catch |err| {
            log.err("vulkan-init", "Failed to allocate queue family properties: {}", .{err});
            return error.QueueFamilyProperties;
        };
        defer self.allocator.free(queue_props);

        var graphics_queue_index: ?vk.DeviceQueueCreateInfo = null;
        var present_queue_index: ?vk.DeviceQueueCreateInfo = null;

        for (queue_props, 0..) |queue_prop, family_index| {
            if (graphics_queue_index == null and queue_prop.queue_flags.graphics_bit) {
                graphics_queue_index = vk.DeviceQueueCreateInfo{
                    .queue_family_index = @intCast(family_index),
                    .queue_count = 1,
                    .p_queue_priorities = &.{1.0},
                    .p_next = null,
                };
                log.debug("vulkan-init", "graphics queue     = {}", .{family_index});
            }

            const present_support = self.instance.getPhysicalDeviceSurfaceSupportKHR(pdev, @intCast(family_index), surface) catch |err| {
                log.err("vulkan-init", "Failed to check surface support for queue family {}: {}", .{ family_index, err });
                return error.SurfaceSupport;
            };

            if (present_queue_index == null and present_support == vk.TRUE) {
                present_queue_index = vk.DeviceQueueCreateInfo{
                    .queue_family_index = @intCast(family_index),
                    .queue_count = 1,
                    .p_queue_priorities = &.{1.0},
                    .p_next = null,
                };
                log.debug("vulkan-init", "present queue      = {}", .{family_index});
            }
        }

        if (graphics_queue_index == null or present_queue_index == null) {
            log.err("vulkan-init", "Failed to find suitable queue families", .{});
            return error.NoSuitableQueueFamilies;
        }

        return .{ graphics_queue_index.?, present_queue_index.? };
    }
};

fn vk_debug(
    severity: vk.DebugUtilsMessageSeverityFlagsEXT,
    _: vk.DebugUtilsMessageTypeFlagsEXT,
    data: ?*const vk.DebugUtilsMessengerCallbackDataEXT,
    _: ?*anyopaque,
) callconv(vk.vulkan_call_conv) vk.Bool32 {
    const message = b: {
        break :b (data orelse break :b "<no data>").p_message orelse "<no message>";
    };

    if (severity.contains(vk.DebugUtilsMessageSeverityFlagsEXT{ .error_bit_ext = true })) {
        log.im_err("vk", "{s}", .{message});
    } else if (severity.contains(vk.DebugUtilsMessageSeverityFlagsEXT{ .warning_bit_ext = true })) {
        log.im_warn("vk", "{s}", .{message});
    } else {
        log.im_debug("vk", "{s}", .{message});
    }
    return vk.FALSE;
}
