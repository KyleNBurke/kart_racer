package render;

Vulkan :: struct {
	vulkan_context: VulkanContext,
}

init_vulkan :: proc() -> Vulkan {
	vulkan_context := init_vulkan_context();

	return Vulkan {
		vulkan_context,
	};
}