package render;

import "vendor:glfw";

Vulkan :: struct {
	vulkan_context: VulkanContext,
}

init_vulkan :: proc(window: glfw.WindowHandle) -> Vulkan {
	vulkan_context := init_vulkan_context(window);

	return Vulkan {
		vulkan_context,
	};
}

cleanup_vulkan :: proc(using vulkan: ^Vulkan) {
	cleanup_vulkan_context(&vulkan_context);
}