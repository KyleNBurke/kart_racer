package render;

import "core:fmt";
import "core:c";
import vk "vendor:vulkan";

find_memory_type_index :: proc(physical_device: vk.PhysicalDevice, requirements: vk.MemoryRequirements, property_flag: vk.MemoryPropertyFlag) -> u32 {
	properties: vk.PhysicalDeviceMemoryProperties;
	vk.GetPhysicalDeviceMemoryProperties(physical_device, &properties);

	for type, i in properties.memoryTypes {
		if requirements.memoryTypeBits & (1 << u32(i)) != 0 && property_flag in type.propertyFlags {
			return u32(i);
		}
	}

	fmt.panicf("Failed to find suitable memory type index\n");
}

find_color_surface_format :: proc(physical_device: vk.PhysicalDevice, surface: vk.SurfaceKHR) -> vk.SurfaceFormatKHR {
	surface_format_counts: u32;
	vk.GetPhysicalDeviceSurfaceFormatsKHR(physical_device, surface, &surface_format_counts, nil);
	surface_formats := make([]vk.SurfaceFormatKHR, surface_format_counts);
	defer delete(surface_formats);
	vk.GetPhysicalDeviceSurfaceFormatsKHR(physical_device, surface, &surface_format_counts, raw_data(surface_formats));

	for surface_format in &surface_formats {
		if surface_format.format == vk.Format.B8G8R8A8_SRGB && surface_format.colorSpace == vk.ColorSpaceKHR.SRGB_NONLINEAR {
			return surface_format;
		}
	}

	return surface_formats[0];
}

find_depth_format :: proc(physical_device: vk.PhysicalDevice) -> vk.Format {
	suitable_formats := [?]vk.Format{vk.Format.D32_SFLOAT, vk.Format.D32_SFLOAT_S8_UINT, vk.Format.D24_UNORM_S8_UINT};

	for format in suitable_formats {
		properties: vk.FormatProperties;
		vk.GetPhysicalDeviceFormatProperties(physical_device, format, &properties);

		if .DEPTH_STENCIL_ATTACHMENT in properties.optimalTilingFeatures {
			return format;
		}
	}

	fmt.panicf("Failed to find suitable depth format\n");
}

create_render_pass :: proc(logical_device: vk.Device, color_format: vk.Format, depth_format: vk.Format) -> vk.RenderPass {
	color_attachment_description: vk.AttachmentDescription;
	color_attachment_description.format = color_format;
	color_attachment_description.samples = {._1};
	color_attachment_description.loadOp = .CLEAR;
	color_attachment_description.storeOp = .STORE;
	color_attachment_description.stencilLoadOp = .DONT_CARE;
	color_attachment_description.stencilStoreOp = .DONT_CARE;
	color_attachment_description.initialLayout = .UNDEFINED;
	color_attachment_description.finalLayout = .PRESENT_SRC_KHR;

	depth_attachment_description: vk.AttachmentDescription;
	depth_attachment_description.format = depth_format;
	depth_attachment_description.samples = {._1};
	depth_attachment_description.loadOp = .CLEAR;
	depth_attachment_description.storeOp = .DONT_CARE;
	depth_attachment_description.stencilLoadOp = .DONT_CARE;
	depth_attachment_description.stencilStoreOp = .DONT_CARE;
	depth_attachment_description.initialLayout = .UNDEFINED;
	depth_attachment_description.finalLayout = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL;

	attachments := [?]vk.AttachmentDescription{color_attachment_description, depth_attachment_description};

	color_attachment_reference: vk.AttachmentReference;
	color_attachment_reference.attachment = 0;
	color_attachment_reference.layout = .COLOR_ATTACHMENT_OPTIMAL;

	depth_attachment_reference: vk.AttachmentReference;
	depth_attachment_reference.attachment = 1;
	depth_attachment_reference.layout = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL;

	subpass_description: vk.SubpassDescription;
	subpass_description.pipelineBindPoint = .GRAPHICS;
	subpass_description.pColorAttachments = &color_attachment_reference;
	subpass_description.colorAttachmentCount = 1;
	subpass_description.pDepthStencilAttachment = &depth_attachment_reference;
	
	subpass_dependency: vk.SubpassDependency;

	create_info: vk.RenderPassCreateInfo;
	create_info.sType = .RENDER_PASS_CREATE_INFO;
	create_info.pAttachments = &attachments[0];
	create_info.attachmentCount = cast(u32) len(attachments);
	create_info.pSubpasses = &subpass_description;
	create_info.subpassCount = 1;
	create_info.pDependencies = &subpass_dependency;
	create_info.subpassCount = 1;

	render_pass: vk.RenderPass;
	r := vk.CreateRenderPass(logical_device, &create_info, nil, &render_pass);
	fmt.assertf(r == .SUCCESS, "Failed to create render pass. Result: %v\n", r);

	return render_pass;
}

create_extent :: proc(physical_device: vk.PhysicalDevice, surface: vk.SurfaceKHR, framebuffer_width, framebuffer_height: u32) -> vk.Extent2D {
	capabilities: vk.SurfaceCapabilitiesKHR;
	vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(physical_device, surface, &capabilities);

	if capabilities.currentExtent.width == c.UINT32_MAX {
		width := clamp(framebuffer_width, capabilities.minImageExtent.width, capabilities.maxImageExtent.width);
		height := clamp(framebuffer_height, capabilities.minImageExtent.height, capabilities.maxImageExtent.height);

		return vk.Extent2D { width, height };
	} else {
		return capabilities.currentExtent;
	}
}

create_depth_image :: proc(logical_device: vk.Device, physical_device: vk.PhysicalDevice, format: vk.Format, extent: vk.Extent2D) -> DepthImage {
	// Create image
	image_create_info: vk.ImageCreateInfo;
	image_create_info.sType = .IMAGE_CREATE_INFO;
	image_create_info.imageType = .D2;
	image_create_info.extent = vk.Extent3D { extent.width, extent.height, 1 };
	image_create_info.mipLevels = 1;
	image_create_info.arrayLayers = 1;
	image_create_info.format = format;
	image_create_info.tiling = .OPTIMAL;
	image_create_info.initialLayout = .UNDEFINED;
	image_create_info.usage = {.DEPTH_STENCIL_ATTACHMENT};
	image_create_info.samples = {._1};
	image_create_info.sharingMode = .EXCLUSIVE;

	image: vk.Image;
	r := vk.CreateImage(logical_device, &image_create_info, nil, &image);
	fmt.assertf(r == .SUCCESS, "Failed to create depth image. Result: %v\n", r);

	// Allocate image memory
	memory_requirements: vk.MemoryRequirements;
	vk.GetImageMemoryRequirements(logical_device, image, &memory_requirements);
	memory_type_index := find_memory_type_index(physical_device, memory_requirements, .DEVICE_LOCAL);

	memory_allocate_info: vk.MemoryAllocateInfo;
	memory_allocate_info.sType = .MEMORY_ALLOCATE_INFO;
	memory_allocate_info.allocationSize = memory_requirements.size;
	memory_allocate_info.memoryTypeIndex = memory_type_index;

	memory: vk.DeviceMemory;
	r = vk.AllocateMemory(logical_device, &memory_allocate_info, nil, &memory);
	fmt.assertf(r == .SUCCESS, "Failed to allocate depth image memory. Result: %v\n", r);

	// Bind image to image memory
	r = vk.BindImageMemory(logical_device, image, memory, 0);
	fmt.assertf(r == .SUCCESS, "Failed to bind depth image to image memory. Result: %v\n", r);

	// Create image view
	subresource_range: vk.ImageSubresourceRange;
	subresource_range.aspectMask = {.DEPTH};
	subresource_range.baseMipLevel = 0;
	subresource_range.levelCount = 1;
	subresource_range.baseArrayLayer = 0;
	subresource_range.layerCount = 1;

	image_view_create_info: vk.ImageViewCreateInfo;
	image_view_create_info.sType = .IMAGE_VIEW_CREATE_INFO;
	image_view_create_info.image = image;
	image_view_create_info.viewType = .D2;
	image_view_create_info.format = format;
	image_view_create_info.subresourceRange = subresource_range;

	image_view: vk.ImageView;
	r = vk.CreateImageView(logical_device, &image_view_create_info, nil, &image_view);
	fmt.assertf(r == .SUCCESS, "Failed to create depth image view. Result: %v\n", r);

	return DepthImage {
		image,
		image_view,
		memory,
	}
}

create_swapchain :: proc(
	using vulkan_context: ^VulkanContext,
	color_surface_format: vk.SurfaceFormatKHR,
	extent: vk.Extent2D,
	render_pass: vk.RenderPass,
	depth_image_view: vk.ImageView,
) -> (vk.SwapchainKHR, [dynamic]SwapchainFrame) {
	surface_capabilities: vk.SurfaceCapabilitiesKHR;
	vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(physical_device, window_surface, &surface_capabilities);

	min_image_count := surface_capabilities.minImageCount;

	if surface_capabilities.maxImageCount != 0 {
		min_image_count = min(min_image_count, surface_capabilities.maxImageCount);
	}

	present_modes_count: u32;
	vk.GetPhysicalDeviceSurfacePresentModesKHR(physical_device, window_surface, &present_modes_count, nil);
	present_modes := make([]vk.PresentModeKHR, present_modes_count);
	vk.GetPhysicalDeviceSurfacePresentModesKHR(physical_device, window_surface, &present_modes_count, raw_data(present_modes));

	present_mode := present_modes[0];
	for m in present_modes {
		if m == .FIFO {
			present_mode = m;
			break;
		}
	}

	swapchain_create_info: vk.SwapchainCreateInfoKHR;
	swapchain_create_info.sType = .SWAPCHAIN_CREATE_INFO_KHR;
	swapchain_create_info.surface = window_surface;
	swapchain_create_info.minImageCount = min_image_count;
	swapchain_create_info.imageFormat = color_surface_format.format;
	swapchain_create_info.imageColorSpace = color_surface_format.colorSpace;
	swapchain_create_info.imageExtent = extent;
	swapchain_create_info.imageArrayLayers = 1;
	swapchain_create_info.imageUsage = {.COLOR_ATTACHMENT};
	swapchain_create_info.preTransform = surface_capabilities.currentTransform;
	swapchain_create_info.compositeAlpha = {.OPAQUE};
	swapchain_create_info.presentMode = present_mode;
	swapchain_create_info.clipped = true;

	queue_family_indices := []u32{graphics_queue_family, present_queue_family};

	if graphics_queue_family == present_queue_family {
		swapchain_create_info.imageSharingMode = .EXCLUSIVE;
	} else {
		swapchain_create_info.imageSharingMode = .CONCURRENT;
		swapchain_create_info.pQueueFamilyIndices = &queue_family_indices[0];
		swapchain_create_info.queueFamilyIndexCount = cast(u32) len(queue_family_indices);
	}

	swapchain: vk.SwapchainKHR;
	r := vk.CreateSwapchainKHR(logical_device, &swapchain_create_info, nil, &swapchain);
	fmt.assertf(r == .SUCCESS, "Failed to create swapchain. Result: %v\n", r);

	swapchain_images_count: u32;
	vk.GetSwapchainImagesKHR(logical_device, swapchain, &swapchain_images_count, nil);
	swapchain_images := make([]vk.Image, swapchain_images_count);
	vk.GetSwapchainImagesKHR(logical_device, swapchain, &swapchain_images_count, raw_data(swapchain_images));

	swapchain_frames := make([dynamic]SwapchainFrame, swapchain_images_count);

	for image, i in swapchain_images {
		// Create image view
		subresource_range: vk.ImageSubresourceRange;
		subresource_range.aspectMask = {.COLOR};
		subresource_range.baseMipLevel = 0;
		subresource_range.levelCount = 1;
		subresource_range.baseArrayLayer = 0;
		subresource_range.layerCount = 1;

		image_view_create_info: vk.ImageViewCreateInfo;
		image_view_create_info.sType = .IMAGE_VIEW_CREATE_INFO;
		image_view_create_info.image = image;
		image_view_create_info.viewType = .D2;
		image_view_create_info.format = color_surface_format.format;
		image_view_create_info.components = vk.ComponentMapping {.IDENTITY, .IDENTITY, .IDENTITY, .IDENTITY};
		image_view_create_info.subresourceRange = subresource_range;

		image_view: vk.ImageView;
		r = vk.CreateImageView(logical_device, &image_view_create_info, nil, &image_view);
		fmt.assertf(r == .SUCCESS, "Failed to create swapchain image view. Result: %v\n", r);

		// Create framebuffer
		framebuffer_attachments := []vk.ImageView{image_view, depth_image_view};

		framebuffer_create_info: vk.FramebufferCreateInfo;
		framebuffer_create_info.sType = .FRAMEBUFFER_CREATE_INFO;
		framebuffer_create_info.renderPass = render_pass;
		framebuffer_create_info.pAttachments = &framebuffer_attachments[0];
		framebuffer_create_info.attachmentCount = cast(u32) len(framebuffer_attachments);
		framebuffer_create_info.width = extent.width;
		framebuffer_create_info.height = extent.height;
		framebuffer_create_info.layers = 1;

		framebuffer: vk.Framebuffer;
		r = vk.CreateFramebuffer(logical_device, &framebuffer_create_info, nil, &framebuffer);
		fmt.assertf(r == .SUCCESS, "Failed to create swapchain framebuffer. Result: %v\n", r);

		swapchain_frames[i] = SwapchainFrame {image_view, framebuffer};
	}

	return swapchain, swapchain_frames;
}

create_descriptor_pool :: proc(logical_device: vk.Device, fonts_count: u32) -> vk.DescriptorPool {
	// 1 set per logical frame
	storage_buffer_pool_size: vk.DescriptorPoolSize;
	storage_buffer_pool_size.type = .STORAGE_BUFFER;
	// 1 descriptor for the mesh data per logical frame
	storage_buffer_pool_size.descriptorCount = LOGICAL_FRAMES_COUNT;

	// 1 set per logical frame
	uniform_buffer_pool_size: vk.DescriptorPoolSize;
	uniform_buffer_pool_size.type = .UNIFORM_BUFFER;
	// 1 descriptor for the frame data and particle instance data per logical frame
	uniform_buffer_pool_size.descriptorCount = LOGICAL_FRAMES_COUNT * 2;

	sampler_pool_size: vk.DescriptorPoolSize;
	sampler_pool_size.type = .SAMPLER;
	// 1 descriptor for the text sampler
	sampler_pool_size.descriptorCount = 1;

	sampled_image_pool_size: vk.DescriptorPoolSize;
	sampled_image_pool_size.type = .SAMPLED_IMAGE;
	// 1 descriptor for each atlas
	sampled_image_pool_size.descriptorCount = fonts_count;

	pool_sizes := []vk.DescriptorPoolSize {
		storage_buffer_pool_size,
		uniform_buffer_pool_size,
		sampler_pool_size,
		sampled_image_pool_size,
	};

	create_info: vk.DescriptorPoolCreateInfo;
	create_info.sType = .DESCRIPTOR_POOL_CREATE_INFO;
	create_info.pPoolSizes = &pool_sizes[0];
	create_info.poolSizeCount = cast(u32) len(pool_sizes);
	create_info.maxSets = LOGICAL_FRAMES_COUNT * 3 + 2;

	descriptor_pool: vk.DescriptorPool;
	r := vk.CreateDescriptorPool(logical_device, &create_info, nil, &descriptor_pool);
	fmt.assertf(r == .SUCCESS, "Failed to create descriptor pool. Result: %v\n", r);

	return descriptor_pool;
}

create_command_pool :: proc(logical_device: vk.Device, graphics_queue_family: u32) -> vk.CommandPool {
	create_info: vk.CommandPoolCreateInfo;
	create_info.sType = .COMMAND_POOL_CREATE_INFO;
	create_info.queueFamilyIndex = graphics_queue_family;
	create_info.flags = {.RESET_COMMAND_BUFFER};

	command_pool: vk.CommandPool;
	r := vk.CreateCommandPool(logical_device, &create_info, nil, &command_pool);
	fmt.assertf(r == .SUCCESS, "Failed to create command pool. Result: %v\n", r);

	return command_pool;
}

create_frame_data_descriptor_set_layout :: proc(logical_device: vk.Device) -> vk.DescriptorSetLayout {
	layout_binding: vk.DescriptorSetLayoutBinding;
	layout_binding.binding = 0;
	layout_binding.descriptorType = .UNIFORM_BUFFER;
	layout_binding.descriptorCount = 1;
	layout_binding.stageFlags = {.VERTEX};

	create_info: vk.DescriptorSetLayoutCreateInfo;
	create_info.sType = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO;
	create_info.pBindings = &layout_binding;
	create_info.bindingCount = 1;

	descriptor_set_layout: vk.DescriptorSetLayout;
	r := vk.CreateDescriptorSetLayout(logical_device, &create_info, nil, &descriptor_set_layout);
	fmt.assertf(r == .SUCCESS, "Failed to create frame data descriptor set layout. Result: %v\n", r);

	return descriptor_set_layout;
}

create_instance_data_descriptor_set_layout :: proc(logical_device: vk.Device) -> vk.DescriptorSetLayout {
	layout_binding: vk.DescriptorSetLayoutBinding;
	layout_binding.binding = 0;
	layout_binding.descriptorType = .STORAGE_BUFFER;
	layout_binding.descriptorCount = 1;
	layout_binding.stageFlags = {.VERTEX};

	create_info: vk.DescriptorSetLayoutCreateInfo;
	create_info.sType = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO;
	create_info.pBindings = &layout_binding;
	create_info.bindingCount = 1;

	descriptor_set_layout: vk.DescriptorSetLayout;
	r := vk.CreateDescriptorSetLayout(logical_device, &create_info, nil, &descriptor_set_layout);
	fmt.assertf(r == .SUCCESS, "Failed to create instance data descriptor set layout. Result: %v\n", r);

	return descriptor_set_layout;
}

create_logical_frames :: proc(
	logical_device: vk.Device,
	// descriptor_set_layouts: ^[]vk.DescriptorSetLayout, think about this one
	command_pool: vk.CommandPool,
	descriptor_pool: vk.DescriptorPool,
) -> [LOGICAL_FRAMES_COUNT]LogicalFrame {
	semaphore_create_info: vk.SemaphoreCreateInfo;
	semaphore_create_info.sType = .SEMAPHORE_CREATE_INFO;

	fence_create_info: vk.FenceCreateInfo;
	fence_create_info.sType = .FENCE_CREATE_INFO;
	fence_create_info.flags = {.SIGNALED};

	primary_command_buffer_allocate_info: vk.CommandBufferAllocateInfo;
	primary_command_buffer_allocate_info.sType = .COMMAND_BUFFER_ALLOCATE_INFO;
	primary_command_buffer_allocate_info.commandPool = command_pool;
	primary_command_buffer_allocate_info.level = .PRIMARY;
	primary_command_buffer_allocate_info.commandBufferCount = LOGICAL_FRAMES_COUNT;

	primary_command_buffers: [LOGICAL_FRAMES_COUNT]vk.CommandBuffer;
	r := vk.AllocateCommandBuffers(logical_device, &primary_command_buffer_allocate_info, &primary_command_buffers[0]);
	assert(r == .SUCCESS);

	secondary_command_buffer_count :: 1;
	secondary_command_buffer_allocate_info: vk.CommandBufferAllocateInfo;
	secondary_command_buffer_allocate_info.sType = .COMMAND_BUFFER_ALLOCATE_INFO;
	secondary_command_buffer_allocate_info.commandPool = command_pool;
	secondary_command_buffer_allocate_info.level = .SECONDARY;
	secondary_command_buffer_allocate_info.commandBufferCount = LOGICAL_FRAMES_COUNT * secondary_command_buffer_count;

	secondary_command_buffers: [LOGICAL_FRAMES_COUNT * secondary_command_buffer_count]vk.CommandBuffer;
	r = vk.AllocateCommandBuffers(logical_device, &secondary_command_buffer_allocate_info, &secondary_command_buffers[0]);
	assert(r == .SUCCESS);

	logical_frames: [LOGICAL_FRAMES_COUNT]LogicalFrame;

	for frame, i in &logical_frames {
		r := vk.CreateSemaphore(logical_device, &semaphore_create_info, nil, &frame.image_available_semaphore);
		assert(r == .SUCCESS);

		r = vk.CreateSemaphore(logical_device, &semaphore_create_info, nil, &frame.render_finished_semaphore);
		assert(r == .SUCCESS);

		r = vk.CreateFence(logical_device, &fence_create_info, nil, &frame.fence);
		assert(r == .SUCCESS);

		frame.primary_command_buffer = primary_command_buffers[i];
		frame.basic_secondary_command_buffer = secondary_command_buffers[secondary_command_buffer_count * i];
	}
	
	return logical_frames;
}