package render;

import "vendor:glfw";
import vk "vendor:vulkan";

LOGICAL_FRAMES_COUNT: u32 = 2;

Vulkan :: struct {
	vulkan_context: VulkanContext,
	surface_format: vk.SurfaceFormatKHR,
	depth_format: vk.Format,
	render_pass: vk.RenderPass,
	extent: vk.Extent2D,
	depth_image: DepthImage,
	swapchain: vk.SwapchainKHR,
	swapchain_frames: [dynamic]SwapchainFrame, // Consider using small_array
	descriptor_pool: vk.DescriptorPool,
	command_pool: vk.CommandPool,
}

VulkanContext :: struct {
	instance: vk.Instance,
	debug_messenger_ext: vk.DebugUtilsMessengerEXT,
	window_surface: vk.SurfaceKHR,
	physical_device: vk.PhysicalDevice,
	graphics_queue_family: u32,
	present_queue_family: u32,
	logical_device: vk.Device,
	graphics_queue: vk.Queue,
	present_queue: vk.Queue,
}

DepthImage :: struct {
	image: vk.Image,
	image_view: vk.ImageView,
	memory: vk.DeviceMemory,
}

SwapchainFrame :: struct {
	color_image_view: vk.ImageView,
	framebuffer: vk.Framebuffer,
}

MeshResources :: struct {

}

LineResources :: struct {

}

ParticleResources :: struct {

}

UiResources :: struct {
	
}

init_vulkan :: proc(window: glfw.WindowHandle) -> Vulkan {
	framebuffer_width, framebuffer_height := glfw.GetFramebufferSize(window);
	
	vulkan_context := init_vulkan_context(window);
	surface_format := find_color_surface_format(vulkan_context.physical_device, vulkan_context.window_surface);
	depth_format := find_depth_format(vulkan_context.physical_device);
	render_pass := create_render_pass(vulkan_context.logical_device, surface_format.format, depth_format);
	extent := create_extent(vulkan_context.physical_device, vulkan_context.window_surface, u32(framebuffer_width), u32(framebuffer_height));
	depth_image := create_depth_image(vulkan_context.logical_device, vulkan_context.physical_device, depth_format, extent);
	swapchain, swapchain_frames := create_swapchain(&vulkan_context, surface_format, extent, render_pass, depth_image.image_view);
	descriptor_pool := create_descriptor_pool(vulkan_context.logical_device, 1);
	command_pool := create_command_pool(vulkan_context.logical_device, vulkan_context.graphics_queue_family);

	return Vulkan {
		vulkan_context,
		surface_format,
		depth_format,
		render_pass,
		extent,
		depth_image,
		swapchain,
		swapchain_frames,
		descriptor_pool,
		command_pool,
	};
}

cleanup_vulkan :: proc(using vulkan: ^Vulkan) {
	logical_device := vulkan_context.logical_device;

	vk.DestroyCommandPool(logical_device, command_pool, nil);
	vk.DestroyDescriptorPool(logical_device, descriptor_pool, nil);

	for frame in swapchain_frames {
		vk.DestroyFramebuffer(logical_device, frame.framebuffer, nil);
		vk.DestroyImageView(logical_device, frame.color_image_view, nil);
	}

	vk.DestroySwapchainKHR(logical_device, swapchain, nil);
	vk.FreeMemory(logical_device, depth_image.memory, nil);
	vk.DestroyImageView(logical_device, depth_image.image_view, nil);
	vk.DestroyImage(logical_device, depth_image.image, nil);
	vk.DestroyRenderPass(logical_device, render_pass, nil);
	cleanup_vulkan_context(&vulkan_context);
}

recreate_swapchain :: proc() {
	
}

render :: proc() -> bool {
	return false;
}