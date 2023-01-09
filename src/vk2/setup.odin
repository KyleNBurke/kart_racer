package vk2;

import "core:fmt";
import "core:c";
import "core:os";
import "core:slice";
import "core:mem";
import "core:c/libc";
import "core:strings";
import vk "vendor:vulkan";
import "vendor:glfw";

IFFC :: 2; // In flight frames count
PIPELINES_COUNT :: 3;

INSTANCE_BUFFER_INDICES_ATTRIBUTES_BLOCK_SIZE :: 5_000_000;

MAX_ENTITIES :: 500;
INSTANCE_BUFFER_MESH_INSTANCE_BLOCK_SIZE :: 64 * MAX_ENTITIES;

MESH_INSTANCE_ELEMENT_SIZE :: 64;

Vulkan :: struct {
	vulkan_context: VulkanContext,
	surface_format: vk.SurfaceFormatKHR,
	depth_format: vk.Format,
	render_pass: vk.RenderPass,
	extent: vk.Extent2D,
	depth_image: DepthImage,
	swapchain: vk.SwapchainKHR,
	swapchain_frames: [dynamic]SwapchainFrame,
	descriptor_pool: vk.DescriptorPool,
	command_pool: vk.CommandPool,
	image_available_semaphores: [IFFC]vk.Semaphore,
	render_finished_semaphores: [IFFC]vk.Semaphore,
	fences: [IFFC]vk.Fence,
	primary_command_buffers: [IFFC]vk.CommandBuffer,
	frame_resources: FrameResources,
	mesh_resources: MeshResources,
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

FrameResources :: struct {
	descriptor_set_layout: vk.DescriptorSetLayout,
	descriptor_sets: [IFFC]vk.DescriptorSet,
	
	// This buffer holds per frame data like the projection and view matrices.
	per_frame_buffers: [IFFC]vk.Buffer,
	per_frame_buffers_memory: [IFFC]vk.DeviceMemory,

	// This buffer hold per instance data whether it be for a mesh, particle, text, etc.
	// E.g. mesh instance transformation matrix, particle instance position, size and color.
	per_instance_buffers: [IFFC]vk.Buffer,
	per_instance_buffers_memory: [IFFC]vk.DeviceMemory,
}

MeshResources :: struct {
	per_instance_buffer_instance_block_offset: int,
	line_secondary_command_buffers: [IFFC]vk.CommandBuffer,
	basic_secondary_command_buffers: [IFFC]vk.CommandBuffer,
	lambert_secondary_command_buffers: [IFFC]vk.CommandBuffer,
	instance_descriptor_set_layout: vk.DescriptorSetLayout,
	instance_descriptor_sets: [IFFC]vk.DescriptorSet,
	pipeline_layout: vk.PipelineLayout,
	line_pipeline: vk.Pipeline,
	basic_pipeline: vk.Pipeline,
	lambert_pipeline: vk.Pipeline,
}

LineResources :: struct {

}

ParticleResources :: struct {

}

UiResources :: struct {
	
}

init_vulkan :: proc(window: glfw.WindowHandle) -> Vulkan {
	framebuffer_width, framebuffer_height := glfw.GetFramebufferSize(window);
	
	using vulkan_context := init_vulkan_context(window);
	surface_format := find_color_surface_format(physical_device, window_surface);
	depth_format := find_depth_format(physical_device);
	render_pass := create_render_pass(logical_device, surface_format.format, depth_format);
	extent := create_extent(physical_device, window_surface, u32(framebuffer_width), u32(framebuffer_height));
	depth_image := create_depth_image(logical_device, physical_device, depth_format, extent);
	swapchain, swapchain_frames := create_swapchain(&vulkan_context, surface_format, extent, render_pass, depth_image.image_view);
	descriptor_pool := create_descriptor_pool(logical_device, 1);
	command_pool := create_command_pool(logical_device, graphics_queue_family);
	image_available_semaphores := create_semaphores(logical_device);
	render_finished_semaphores := create_semaphores(logical_device);
	fences := create_fences(logical_device);
	primary_command_buffers := create_primary_command_buffers(logical_device, command_pool);
	secondary_command_buffers := create_secondary_command_buffers(logical_device, command_pool);
	
	frame_descriptor_set_layout, frame_descriptor_sets := create_frame_descriptor_sets(logical_device, descriptor_pool);
	per_frame_buffers, per_frame_buffers_memory := create_per_frame_buffers(physical_device, logical_device);
	update_frame_descriptor_sets(logical_device, frame_descriptor_sets, per_frame_buffers);
	per_instance_buffer_instance_block_offset, per_instance_buffer_total_size := calculate_per_instance_buffer_metrics(physical_device);
	per_instance_buffers, per_instance_buffers_memory := create_per_instance_buffers(physical_device, logical_device, per_instance_buffer_total_size);
	
	frame_resources := FrameResources {
		descriptor_set_layout = frame_descriptor_set_layout,
		descriptor_sets = frame_descriptor_sets,
		per_frame_buffers = per_frame_buffers,
		per_frame_buffers_memory = per_frame_buffers_memory,
		per_instance_buffers = per_instance_buffers,
		per_instance_buffers_memory = per_instance_buffers_memory,
	};

	mesh_instance_descriptor_set_layout, mesh_instance_descriptor_sets := create_mesh_descriptor_sets(logical_device, descriptor_pool);
	update_mesh_instance_descriptor_sets(logical_device, mesh_instance_descriptor_sets, per_instance_buffers, per_instance_buffer_instance_block_offset);
	mesh_descriptor_set_layouts := [?]vk.DescriptorSetLayout {frame_descriptor_set_layout, mesh_instance_descriptor_set_layout};
	mesh_pipeline_layout := create_mesh_pipeline_layout(logical_device, &mesh_descriptor_set_layouts);
	
	pipelines := create_pipelines(logical_device, render_pass, extent, mesh_pipeline_layout);

	mesh_resources := MeshResources {
		per_instance_buffer_instance_block_offset = per_instance_buffer_instance_block_offset,
		line_secondary_command_buffers = secondary_command_buffers.line,
		basic_secondary_command_buffers = secondary_command_buffers.basic,
		lambert_secondary_command_buffers = secondary_command_buffers.lambert,
		instance_descriptor_set_layout = mesh_instance_descriptor_set_layout,
		instance_descriptor_sets = mesh_instance_descriptor_sets,
		pipeline_layout = mesh_pipeline_layout,
		line_pipeline = pipelines[0],
		basic_pipeline = pipelines[1],
		lambert_pipeline = pipelines[2],
	};

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
		image_available_semaphores,
		render_finished_semaphores,
		fences,
		primary_command_buffers,
		frame_resources,
		mesh_resources,
	};
}

cleanup_vulkan :: proc(using vulkan: ^Vulkan) {
	logical_device := vulkan_context.logical_device;
	vk.DeviceWaitIdle(logical_device);
	
	vk.DestroyPipeline(logical_device, mesh_resources.lambert_pipeline, nil);
	vk.DestroyPipeline(logical_device, mesh_resources.basic_pipeline, nil);
	vk.DestroyPipeline(logical_device, mesh_resources.line_pipeline, nil);
	vk.DestroyPipelineLayout(logical_device, mesh_resources.pipeline_layout, nil);
	vk.DestroyDescriptorSetLayout(logical_device, mesh_resources.instance_descriptor_set_layout, nil);
	vk.DestroyDescriptorSetLayout(logical_device, frame_resources.descriptor_set_layout, nil);

	for i in 0..<IFFC {
		vk.FreeMemory(logical_device, frame_resources.per_instance_buffers_memory[i], nil);
		vk.DestroyBuffer(logical_device, frame_resources.per_instance_buffers[i], nil);
		vk.FreeMemory(logical_device, frame_resources.per_frame_buffers_memory[i], nil);
		vk.DestroyBuffer(logical_device, frame_resources.per_frame_buffers[i], nil);

		vk.DestroyFence(logical_device, fences[i], nil);
		vk.DestroySemaphore(logical_device, render_finished_semaphores[i], nil);
		vk.DestroySemaphore(logical_device, image_available_semaphores[i], nil);
	}

	vk.DestroyCommandPool(logical_device, command_pool, nil);
	vk.DestroyDescriptorPool(logical_device, descriptor_pool, nil);

	for frame in swapchain_frames {
		vk.DestroyFramebuffer(logical_device, frame.framebuffer, nil);
		vk.DestroyImageView(logical_device, frame.color_image_view, nil);
	}

	delete(swapchain_frames);
	vk.DestroySwapchainKHR(logical_device, swapchain, nil);
	vk.FreeMemory(logical_device, depth_image.memory, nil);
	vk.DestroyImageView(logical_device, depth_image.image_view, nil);
	vk.DestroyImage(logical_device, depth_image.image, nil);
	vk.DestroyRenderPass(logical_device, render_pass, nil);

	cleanup_vulkan_context(&vulkan_context);
}

recreate_swapchain :: proc(using vulkan: ^Vulkan, framebuffer_width, framebuffer_height: u32) {
	logical_device := vulkan_context.logical_device;

	vk.DeviceWaitIdle(logical_device);
	vk.DestroyPipeline(logical_device, mesh_resources.lambert_pipeline, nil);
	vk.DestroyPipeline(logical_device, mesh_resources.basic_pipeline, nil);
	vk.DestroyPipeline(logical_device, mesh_resources.line_pipeline, nil);

	for frame in swapchain_frames {
		vk.DestroyFramebuffer(logical_device, frame.framebuffer, nil);
		vk.DestroyImageView(logical_device, frame.color_image_view, nil);
	}

	delete(swapchain_frames);
	vk.DestroySwapchainKHR(logical_device, swapchain, nil);
	vk.FreeMemory(logical_device, depth_image.memory, nil);
	vk.DestroyImageView(logical_device, depth_image.image_view, nil);
	vk.DestroyImage(logical_device, depth_image.image, nil);

	extent = create_extent(vulkan_context.physical_device, vulkan_context.window_surface, framebuffer_width, framebuffer_height);
	depth_image = create_depth_image(logical_device, vulkan_context.physical_device, depth_format, extent);
	swapchain, swapchain_frames = create_swapchain(&vulkan_context, surface_format, extent, render_pass, depth_image.image_view);

	pipelines := create_pipelines(logical_device, render_pass, extent, mesh_resources.pipeline_layout);
	mesh_resources.line_pipeline = pipelines[0];
	mesh_resources.basic_pipeline = pipelines[1];
	mesh_resources.lambert_pipeline = pipelines[2];

	fmt.println("Swapchain recreated");
}

find_memory_type_index :: proc(physical_device: vk.PhysicalDevice, requirements: vk.MemoryRequirements, property_flags: vk.MemoryPropertyFlags) -> u32 {
	properties: vk.PhysicalDeviceMemoryProperties;
	vk.GetPhysicalDeviceMemoryProperties(physical_device, &properties);

	for type, i in properties.memoryTypes {
		if requirements.memoryTypeBits & (1 << u32(i)) != 0 && property_flags <= type.propertyFlags {
			return u32(i);
		}
	}

	panic("Failed to find suitable memory type index\n");
}

align_forward :: proc(unaligned_offset: int, alignment: int) -> int {
	under := (alignment - unaligned_offset % alignment) % alignment;
	return unaligned_offset + under;
}

align_backward :: proc(unaligned_offset: int, alignment: int) -> int {
	over := unaligned_offset % alignment;
	return unaligned_offset - over;
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

	panic("Failed to find suitable depth format\n");
}

create_render_pass :: proc(logical_device: vk.Device, color_format: vk.Format, depth_format: vk.Format) -> vk.RenderPass {
	color_attachment_description := vk.AttachmentDescription {
		format = color_format,
		samples = {._1},
		loadOp = .CLEAR,
		storeOp = .STORE,
		stencilLoadOp = .DONT_CARE,
		stencilStoreOp = .DONT_CARE,
		initialLayout = .UNDEFINED,
		finalLayout = .PRESENT_SRC_KHR,
	};

	depth_attachment_description := vk.AttachmentDescription {
		format = depth_format,
		samples = {._1},
		loadOp = .CLEAR,
		storeOp = .DONT_CARE,
		stencilLoadOp = .DONT_CARE,
		stencilStoreOp = .DONT_CARE,
		initialLayout = .UNDEFINED,
		finalLayout = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
	};

	attachments := [?]vk.AttachmentDescription{color_attachment_description, depth_attachment_description};

	color_attachment_reference := vk.AttachmentReference {
		attachment = 0,
		layout = .COLOR_ATTACHMENT_OPTIMAL,
	};

	depth_attachment_reference := vk.AttachmentReference {
		attachment = 1,
		layout = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
	};

	subpass_description := vk.SubpassDescription {
		pipelineBindPoint = .GRAPHICS,
		pColorAttachments = &color_attachment_reference,
		colorAttachmentCount = 1,
		pDepthStencilAttachment = &depth_attachment_reference,
	};
	
	subpass_dependency: vk.SubpassDependency;

	create_info := vk.RenderPassCreateInfo {
		sType = .RENDER_PASS_CREATE_INFO,
		pAttachments = &attachments[0],
		attachmentCount = cast(u32) len(attachments),
		pSubpasses = &subpass_description,
		subpassCount = 1,
		pDependencies = &subpass_dependency,
	};

	render_pass: vk.RenderPass;
	r := vk.CreateRenderPass(logical_device, &create_info, nil, &render_pass);
	assert(r == .SUCCESS);

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
	image_create_info := vk.ImageCreateInfo {
		sType = .IMAGE_CREATE_INFO,
		imageType = .D2,
		extent = vk.Extent3D { extent.width, extent.height, 1 },
		mipLevels = 1,
		arrayLayers = 1,
		format = format,
		tiling = .OPTIMAL,
		initialLayout = .UNDEFINED,
		usage = {.DEPTH_STENCIL_ATTACHMENT},
		samples = {._1},
		sharingMode = .EXCLUSIVE,
	};

	image: vk.Image;
	r := vk.CreateImage(logical_device, &image_create_info, nil, &image);
	assert(r == .SUCCESS);

	// Allocate image memory
	memory_requirements: vk.MemoryRequirements;
	vk.GetImageMemoryRequirements(logical_device, image, &memory_requirements);
	memory_type_index := find_memory_type_index(physical_device, memory_requirements, {.DEVICE_LOCAL});

	memory_allocate_info := vk.MemoryAllocateInfo {
		sType = .MEMORY_ALLOCATE_INFO,
		allocationSize = memory_requirements.size,
		memoryTypeIndex = memory_type_index,
	};

	memory: vk.DeviceMemory;
	r = vk.AllocateMemory(logical_device, &memory_allocate_info, nil, &memory);
	assert(r == .SUCCESS);

	// Bind image to image memory
	r = vk.BindImageMemory(logical_device, image, memory, 0);
	assert(r == .SUCCESS);

	// Create image view
	subresource_range := vk.ImageSubresourceRange {
		aspectMask = {.DEPTH},
		baseMipLevel = 0,
		levelCount = 1,
		baseArrayLayer = 0,
		layerCount = 1,
	};

	image_view_create_info := vk.ImageViewCreateInfo {
		sType = .IMAGE_VIEW_CREATE_INFO,
		image = image,
		viewType = .D2,
		format = format,
		subresourceRange = subresource_range,
	};

	image_view: vk.ImageView;
	r = vk.CreateImageView(logical_device, &image_view_create_info, nil, &image_view);
	assert(r == .SUCCESS);

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
	defer delete(present_modes);
	vk.GetPhysicalDeviceSurfacePresentModesKHR(physical_device, window_surface, &present_modes_count, raw_data(present_modes));

	present_mode := present_modes[0];
	if slice.contains(present_modes[:], vk.PresentModeKHR.FIFO) {
		present_mode = vk.PresentModeKHR.FIFO;
	}

	swapchain_create_info := vk.SwapchainCreateInfoKHR {
		sType = .SWAPCHAIN_CREATE_INFO_KHR,
		surface = window_surface,
		minImageCount = min_image_count,
		imageFormat = color_surface_format.format,
		imageColorSpace = color_surface_format.colorSpace,
		imageExtent = extent,
		imageArrayLayers = 1,
		imageUsage = {.COLOR_ATTACHMENT},
		preTransform = surface_capabilities.currentTransform,
		compositeAlpha = {.OPAQUE},
		presentMode = present_mode,
		clipped = true,
	};

	queue_family_indices := []u32 { graphics_queue_family, present_queue_family };

	if graphics_queue_family == present_queue_family {
		swapchain_create_info.imageSharingMode = .EXCLUSIVE;
	} else {
		swapchain_create_info.imageSharingMode = .CONCURRENT;
		swapchain_create_info.pQueueFamilyIndices = &queue_family_indices[0];
		swapchain_create_info.queueFamilyIndexCount = cast(u32) len(queue_family_indices);
	}

	swapchain: vk.SwapchainKHR;
	r := vk.CreateSwapchainKHR(logical_device, &swapchain_create_info, nil, &swapchain);
	assert(r == .SUCCESS);

	swapchain_images_count: u32;
	vk.GetSwapchainImagesKHR(logical_device, swapchain, &swapchain_images_count, nil);
	swapchain_images := make([]vk.Image, swapchain_images_count);
	defer delete(swapchain_images);
	vk.GetSwapchainImagesKHR(logical_device, swapchain, &swapchain_images_count, raw_data(swapchain_images));

	swapchain_frames := make([dynamic]SwapchainFrame, swapchain_images_count);

	for image, i in swapchain_images {
		// Create image view
		subresource_range := vk.ImageSubresourceRange {
			aspectMask = {.COLOR},
			baseMipLevel = 0,
			levelCount = 1,
			baseArrayLayer = 0,
			layerCount = 1,
		};

		image_view_create_info := vk.ImageViewCreateInfo {
			sType = .IMAGE_VIEW_CREATE_INFO,
			image = image,
			viewType = .D2,
			format = color_surface_format.format,
			components = vk.ComponentMapping {.IDENTITY, .IDENTITY, .IDENTITY, .IDENTITY},
			subresourceRange = subresource_range,
		};

		image_view: vk.ImageView;
		r = vk.CreateImageView(logical_device, &image_view_create_info, nil, &image_view);
		assert(r == .SUCCESS);

		// Create framebuffer
		framebuffer_attachments := []vk.ImageView{image_view, depth_image_view};

		framebuffer_create_info := vk.FramebufferCreateInfo {
			sType = .FRAMEBUFFER_CREATE_INFO,
			renderPass = render_pass,
			pAttachments = &framebuffer_attachments[0],
			attachmentCount = cast(u32) len(framebuffer_attachments),
			width = extent.width,
			height = extent.height,
			layers = 1,
		}

		framebuffer: vk.Framebuffer;
		r = vk.CreateFramebuffer(logical_device, &framebuffer_create_info, nil, &framebuffer);
		assert(r == .SUCCESS);

		swapchain_frames[i] = SwapchainFrame {image_view, framebuffer};
	}

	return swapchain, swapchain_frames;
}

create_descriptor_pool :: proc(logical_device: vk.Device, fonts_count: u32) -> vk.DescriptorPool {
	// 1 set per logical frame
	storage_buffer_pool_size := vk.DescriptorPoolSize {
		type = .STORAGE_BUFFER,
		// 1 descriptor for the mesh data per logical frame
		descriptorCount = IFFC,
	};

	// 1 set per logical frame
	uniform_buffer_pool_size := vk.DescriptorPoolSize {
		type = .UNIFORM_BUFFER,
		// 1 descriptor for the frame data and particle instance data per logical frame
		descriptorCount = IFFC * 2,
	};

	sampler_pool_size := vk.DescriptorPoolSize {
		type = .SAMPLER,
		// 1 descriptor for the text sampler
		descriptorCount = 1,
	};

	sampled_image_pool_size := vk.DescriptorPoolSize {
		type = .SAMPLED_IMAGE,
		// 1 descriptor for each atlas
		descriptorCount = fonts_count,
	};

	pool_sizes := []vk.DescriptorPoolSize {
		storage_buffer_pool_size,
		uniform_buffer_pool_size,
		sampler_pool_size,
		sampled_image_pool_size,
	};

	create_info := vk.DescriptorPoolCreateInfo {
		sType = .DESCRIPTOR_POOL_CREATE_INFO,
		pPoolSizes = &pool_sizes[0],
		poolSizeCount = cast(u32) len(pool_sizes),
		maxSets = IFFC * 3 + 2,
	};

	descriptor_pool: vk.DescriptorPool;
	r := vk.CreateDescriptorPool(logical_device, &create_info, nil, &descriptor_pool);
	assert(r == .SUCCESS);

	return descriptor_pool;
}

create_command_pool :: proc(logical_device: vk.Device, graphics_queue_family: u32) -> vk.CommandPool {
	create_info := vk.CommandPoolCreateInfo {
		sType = .COMMAND_POOL_CREATE_INFO,
		queueFamilyIndex = graphics_queue_family,
		flags = {.RESET_COMMAND_BUFFER},
	};

	command_pool: vk.CommandPool;
	r := vk.CreateCommandPool(logical_device, &create_info, nil, &command_pool);
	assert(r == .SUCCESS);

	return command_pool;
}

create_semaphores :: proc(logical_device: vk.Device) -> [IFFC]vk.Semaphore {
	create_info := vk.SemaphoreCreateInfo {
		sType = .SEMAPHORE_CREATE_INFO,
	};
	
	semaphores: [IFFC]vk.Semaphore;
	for semaphore in &semaphores {
		r := vk.CreateSemaphore(logical_device, &create_info, nil, &semaphore);
		assert(r == .SUCCESS);
	}

	return semaphores;
}

create_fences :: proc(logical_device: vk.Device) -> [IFFC]vk.Fence {
	create_info := vk.FenceCreateInfo {
		sType = .FENCE_CREATE_INFO,
		flags = {.SIGNALED},
	};

	fences: [IFFC]vk.Fence;
	for fence in &fences {
		r := vk.CreateFence(logical_device, &create_info, nil, &fence);
		assert(r == .SUCCESS);
	}

	return fences;
}

create_primary_command_buffers :: proc(logical_device: vk.Device, command_pool: vk.CommandPool) -> [IFFC]vk.CommandBuffer {
	create_info := vk.CommandBufferAllocateInfo {
		sType = .COMMAND_BUFFER_ALLOCATE_INFO,
		commandPool = command_pool,
		level = .PRIMARY,
		commandBufferCount = IFFC,
	};

	command_buffers: [IFFC]vk.CommandBuffer;
	r := vk.AllocateCommandBuffers(logical_device, &create_info, &command_buffers[0]);
	assert(r == .SUCCESS);

	return command_buffers;
}

SecondaryCommandBuffers :: struct {
	line: [IFFC]vk.CommandBuffer,
	basic: [IFFC]vk.CommandBuffer,
	lambert: [IFFC]vk.CommandBuffer,
}

create_secondary_command_buffers :: proc(logical_device: vk.Device, command_pool: vk.CommandPool) -> SecondaryCommandBuffers {
	COUNT :: IFFC * PIPELINES_COUNT;
	
	allocate_info := vk.CommandBufferAllocateInfo {
		sType = .COMMAND_BUFFER_ALLOCATE_INFO,
		commandPool = command_pool,
		level = .SECONDARY,
		commandBufferCount = COUNT,
	};

	command_buffers_array: [COUNT]vk.CommandBuffer;
	r := vk.AllocateCommandBuffers(logical_device, &allocate_info, &command_buffers_array[0]);
	assert(r == .SUCCESS);

	line, basic, lambert: [IFFC]vk.CommandBuffer;
	
	for i in 0..<IFFC {
		line[i]    = command_buffers_array[PIPELINES_COUNT * i];
		basic[i]   = command_buffers_array[PIPELINES_COUNT * i + 1];
		lambert[i] = command_buffers_array[PIPELINES_COUNT * i + 2];
	}

	return SecondaryCommandBuffers {
		line,
		basic,
		lambert,
	};
}

create_frame_descriptor_sets :: proc(logical_device: vk.Device, descriptor_pool: vk.DescriptorPool) -> (vk.DescriptorSetLayout, [IFFC]vk.DescriptorSet) {
	layout_binding := vk.DescriptorSetLayoutBinding {
		binding = 0,
		descriptorType = .UNIFORM_BUFFER,
		descriptorCount = 1,
		stageFlags = {.VERTEX},
	};

	layout_create_info := vk.DescriptorSetLayoutCreateInfo {
		sType = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
		pBindings = &layout_binding,
		bindingCount = 1,
	};

	descriptor_set_layout: vk.DescriptorSetLayout;
	r := vk.CreateDescriptorSetLayout(logical_device, &layout_create_info, nil, &descriptor_set_layout);
	assert(r == .SUCCESS);

	descriptor_set_layouts: [IFFC]vk.DescriptorSetLayout;
	slice.fill(descriptor_set_layouts[:], descriptor_set_layout);

	allocate_info := vk.DescriptorSetAllocateInfo {
		sType = .DESCRIPTOR_SET_ALLOCATE_INFO,
		descriptorPool = descriptor_pool,
		pSetLayouts = &descriptor_set_layouts[0],
		descriptorSetCount = len(descriptor_set_layouts),
	};

	descriptor_sets: [IFFC]vk.DescriptorSet;
	r = vk.AllocateDescriptorSets(logical_device, &allocate_info, &descriptor_sets[0]);
	assert(r == .SUCCESS);

	return descriptor_set_layout, descriptor_sets;
}

create_per_frame_buffers :: proc(physical_device: vk.PhysicalDevice, logical_device: vk.Device, ) -> ([IFFC]vk.Buffer, [IFFC]vk.DeviceMemory) {
	PER_FRAME_BUFFER_SIZE :: 128;

	buffers: [IFFC]vk.Buffer;
	buffers_memory: [IFFC]vk.DeviceMemory;

	for i in 0..<IFFC {
		buffer, memory := create_allocate_and_bind_buffer_memory(physical_device, logical_device, {.UNIFORM_BUFFER}, {.HOST_VISIBLE}, PER_FRAME_BUFFER_SIZE);
		buffers[i] = buffer;
		buffers_memory[i] = memory;
	}
	
	return buffers, buffers_memory;
}

create_allocate_and_bind_buffer_memory :: proc(physical_device: vk.PhysicalDevice, logical_device: vk.Device, usage: vk.BufferUsageFlags, properties: vk.MemoryPropertyFlags, size: vk.DeviceSize) -> (vk.Buffer, vk.DeviceMemory) {
	create_info := vk.BufferCreateInfo {
		sType = .BUFFER_CREATE_INFO,
		size = size,
		usage = usage,
		sharingMode = .EXCLUSIVE,
	};

	buffer: vk.Buffer;
	r := vk.CreateBuffer(logical_device, &create_info, nil, &buffer);
	assert(r == .SUCCESS);

	memory_requirements: vk.MemoryRequirements;
	vk.GetBufferMemoryRequirements(logical_device, buffer, &memory_requirements);

	memory_type_index := find_memory_type_index(physical_device, memory_requirements, {.HOST_VISIBLE});

	allocate_info := vk.MemoryAllocateInfo {
		sType = .MEMORY_ALLOCATE_INFO,
		allocationSize = memory_requirements.size,
		memoryTypeIndex = memory_type_index,
	};

	memory: vk.DeviceMemory;
	r = vk.AllocateMemory(logical_device, &allocate_info, nil, &memory);
	assert(r == .SUCCESS);

	r = vk.BindBufferMemory(logical_device, buffer, memory, 0);
	assert(r == .SUCCESS);

	return buffer, memory;
}

update_frame_descriptor_sets :: proc(logical_device: vk.Device, descriptor_sets: [IFFC]vk.DescriptorSet, buffers: [IFFC]vk.Buffer) {
	descriptor_buffer_infos: [IFFC]vk.DescriptorBufferInfo;
	write_descriptor_sets: [IFFC]vk.WriteDescriptorSet;
	
	for i in 0..<IFFC {
		descriptor_buffer_infos[i] = vk.DescriptorBufferInfo {
			buffer = buffers[i],
			offset = 0,
			range = cast(vk.DeviceSize) vk.WHOLE_SIZE,
		};

		write_descriptor_sets[i] = vk.WriteDescriptorSet {
			sType = .WRITE_DESCRIPTOR_SET,
			dstSet = descriptor_sets[i],
			dstBinding = 0,
			dstArrayElement = 0,
			descriptorCount = 1,
			descriptorType = .UNIFORM_BUFFER,
			pBufferInfo = &descriptor_buffer_infos[i],
		};
	}

	vk.UpdateDescriptorSets(logical_device, IFFC, &write_descriptor_sets[0], 0, {});
}

create_per_instance_buffers :: proc(physical_device: vk.PhysicalDevice, logical_device: vk.Device, total_size: int) -> ([IFFC]vk.Buffer, [IFFC]vk.DeviceMemory) {
	buffers: [IFFC]vk.Buffer;
	buffers_memory: [IFFC]vk.DeviceMemory;

	for i in 0..<IFFC {
		buffer, memory := create_allocate_and_bind_buffer_memory(physical_device, logical_device, {.INDEX_BUFFER, .VERTEX_BUFFER, .STORAGE_BUFFER}, {.HOST_VISIBLE}, cast(vk.DeviceSize) total_size);
		buffers[i] = buffer;
		buffers_memory[i] = memory;
	}
	
	return buffers, buffers_memory;
}

calculate_per_instance_buffer_metrics :: proc(physical_device: vk.PhysicalDevice) -> (instance_block_offset, total_size: int) {
	physical_device_properties: vk.PhysicalDeviceProperties;
	vk.GetPhysicalDeviceProperties(physical_device, &physical_device_properties);
	alignment := physical_device_properties.limits.minStorageBufferOffsetAlignment;

	unaligned_offset := INSTANCE_BUFFER_INDICES_ATTRIBUTES_BLOCK_SIZE;
	instance_block_offset = align_forward(unaligned_offset, int(alignment));

	total_size = instance_block_offset + INSTANCE_BUFFER_MESH_INSTANCE_BLOCK_SIZE;

	return instance_block_offset, total_size;
}

create_mesh_descriptor_sets :: proc(logical_device: vk.Device, descriptor_pool: vk.DescriptorPool) -> (vk.DescriptorSetLayout, [IFFC]vk.DescriptorSet) {
	layout_binding := vk.DescriptorSetLayoutBinding {
		binding = 0,
		descriptorType = .STORAGE_BUFFER,
		descriptorCount = 1,
		stageFlags = {.VERTEX},
	};

	layout_create_info := vk.DescriptorSetLayoutCreateInfo {
		sType = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
		pBindings = &layout_binding,
		bindingCount = 1,
	};

	descriptor_set_layout: vk.DescriptorSetLayout;
	r := vk.CreateDescriptorSetLayout(logical_device, &layout_create_info, nil, &descriptor_set_layout);
	assert(r == .SUCCESS);

	descriptor_set_layouts: [IFFC]vk.DescriptorSetLayout;
	slice.fill(descriptor_set_layouts[:], descriptor_set_layout);

	allocate_info := vk.DescriptorSetAllocateInfo {
		sType = .DESCRIPTOR_SET_ALLOCATE_INFO,
		descriptorPool = descriptor_pool,
		pSetLayouts = &descriptor_set_layouts[0],
		descriptorSetCount = len(descriptor_set_layouts),
	};

	descriptor_sets: [IFFC]vk.DescriptorSet;
	r = vk.AllocateDescriptorSets(logical_device, &allocate_info, &descriptor_sets[0]);
	assert(r == .SUCCESS);

	return descriptor_set_layout, descriptor_sets;
}

update_mesh_instance_descriptor_sets :: proc(logical_device: vk.Device, descriptor_sets: [IFFC]vk.DescriptorSet, buffers: [IFFC]vk.Buffer, instance_block_offset: int) {
	descriptor_buffer_infos: [IFFC]vk.DescriptorBufferInfo;
	write_descriptor_sets: [IFFC]vk.WriteDescriptorSet;
	
	for i in 0..<IFFC {
		descriptor_buffer_infos[i] = vk.DescriptorBufferInfo {
			buffer = buffers[i],
			offset = cast(vk.DeviceSize) instance_block_offset,
			range = cast(vk.DeviceSize) vk.WHOLE_SIZE,
		};

		write_descriptor_sets[i] = vk.WriteDescriptorSet {
			sType = .WRITE_DESCRIPTOR_SET,
			dstSet = descriptor_sets[i],
			dstBinding = 0,
			dstArrayElement = 0,
			descriptorCount = 1,
			descriptorType = .STORAGE_BUFFER,
			pBufferInfo = &descriptor_buffer_infos[i],
		};
	}

	vk.UpdateDescriptorSets(logical_device, IFFC, &write_descriptor_sets[0], 0, {});
}

create_mesh_pipeline_layout :: proc(logical_device: vk.Device, descriptor_set_layouts: ^[2]vk.DescriptorSetLayout) -> vk.PipelineLayout {
	create_info := vk.PipelineLayoutCreateInfo {
		sType = .PIPELINE_LAYOUT_CREATE_INFO,
		pSetLayouts = &descriptor_set_layouts[0],
		setLayoutCount = len(descriptor_set_layouts),
	};

	pipeline_layout: vk.PipelineLayout;
	r := vk.CreatePipelineLayout(logical_device, &create_info, nil, &pipeline_layout);
	assert(r == .SUCCESS);

	return pipeline_layout;
}

create_pipelines :: proc(
	logical_device: vk.Device,
	render_pass: vk.RenderPass,
	extent: vk.Extent2D,
	mesh_pipeline_layout: vk.PipelineLayout,
) -> [PIPELINES_COUNT]vk.Pipeline {
	// Shared
	create_shader_module :: proc(logical_device: vk.Device, file_name: string) -> vk.ShaderModule {
		cmp_path := fmt.tprintf("build/shaders/%v.spv", file_name);
		
		when ODIN_DEBUG {
			src_path := fmt.tprintf("src/shaders/%v", file_name);
			src_time, src_error := os.last_write_time_by_name(src_path);
			assert(src_error == os.ERROR_NONE);

			cmp_time, cmp_error := os.last_write_time_by_name(cmp_path);

			if cmp_error == os.ERROR_PATH_NOT_FOUND {
				e := os.make_directory("build/shaders");
				assert(e == os.ERROR_NONE);
			}

			if cmp_error == os.ERROR_PATH_NOT_FOUND || cmp_error == os.ERROR_FILE_NOT_FOUND || src_time > cmp_time {
				command := fmt.tprintf("glslc %v -o %v", src_path, cmp_path);
				command_cstring := strings.clone_to_cstring(command);
				defer delete(command_cstring);
			
				r := libc.system(command_cstring);
				assert(r == 0);
			
				fmt.printf("Compiled shader %v\n", cmp_path);
			}
		}

		code, success := os.read_entire_file_from_filename(cmp_path);
		defer delete(code);
		assert(success);
		
		create_info := vk.ShaderModuleCreateInfo {
			sType = .SHADER_MODULE_CREATE_INFO,
			pCode = cast(^u32) raw_data(code),
			codeSize = len(code),
		};

		shader_module: vk.ShaderModule;
		r := vk.CreateShaderModule(logical_device, &create_info, nil, &shader_module);
		assert(r == .SUCCESS);

		return shader_module;
	}
	
	shader_entry_point: cstring = "main";

	viewport := vk.Viewport {
		x = 0.0,
		y = 0.0,
		width = f32(extent.width),
		height = f32(extent.height),
		minDepth = 0.0,
		maxDepth = 1.0,
	};

	scissor := vk.Rect2D {
		offset = vk.Offset2D {0, 0},
		extent = extent,
	};

	viewport_state_create_info := vk.PipelineViewportStateCreateInfo {
		sType = .PIPELINE_VIEWPORT_STATE_CREATE_INFO,
		pViewports = &viewport,
		viewportCount = 1,
		pScissors = &scissor,
		scissorCount = 1,
	};

	multisample_state_create_info := vk.PipelineMultisampleStateCreateInfo {
		sType = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
		sampleShadingEnable = false,
		rasterizationSamples = {._1},
	};

	depth_stencil_state_create_info := vk.PipelineDepthStencilStateCreateInfo {
		sType = .PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
		depthTestEnable = true,
		depthWriteEnable = true,
		depthCompareOp = .LESS,
		depthBoundsTestEnable = false,
		stencilTestEnable = false,
	};

	color_blend_attachment_state := vk.PipelineColorBlendAttachmentState {
		colorWriteMask = {.R, .G, .B, .A},
		blendEnable = false,
	};

	color_blend_state_create_info := vk.PipelineColorBlendStateCreateInfo {
		sType = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
		logicOpEnable = false,
		pAttachments = &color_blend_attachment_state,
		attachmentCount = 1,
	};

	// Line
	basic_vert_module := create_shader_module(logical_device, "basic.vert");
	defer vk.DestroyShaderModule(logical_device, basic_vert_module, nil);
	basic_vert_stage_create_info := vk.PipelineShaderStageCreateInfo {
		sType = .PIPELINE_SHADER_STAGE_CREATE_INFO,
		stage = {.VERTEX},
		module = basic_vert_module,
		pName = shader_entry_point,
	};

	basic_frag_module := create_shader_module(logical_device, "basic.frag");
	defer vk.DestroyShaderModule(logical_device, basic_frag_module, nil);
	basic_frag_stage_create_info := vk.PipelineShaderStageCreateInfo {
		sType = .PIPELINE_SHADER_STAGE_CREATE_INFO,
		stage = {.FRAGMENT},
		module = basic_frag_module,
		pName = shader_entry_point,
	};

	basic_stage_create_infos := [?]vk.PipelineShaderStageCreateInfo {basic_vert_stage_create_info, basic_frag_stage_create_info};

	line_input_binding_description := vk.VertexInputBindingDescription {
		binding = 0,
		stride = 24,
		inputRate = .VERTEX,
	};

	line_input_attribute_description_position := vk.VertexInputAttributeDescription {
		binding = 0,
		location = 0,
		format = .R32G32B32_SFLOAT,
		offset = 0,
	};

	line_input_attribute_description_color := vk.VertexInputAttributeDescription {
		binding = 0,
		location = 1,
		format = .R32G32B32_SFLOAT,
		offset = 12,
	};

	line_input_attribute_descriptions := [?]vk.VertexInputAttributeDescription {
		line_input_attribute_description_position,
		line_input_attribute_description_color,
	};

	line_vertex_input_state_create_info := vk.PipelineVertexInputStateCreateInfo {
		sType = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
		pVertexBindingDescriptions = &line_input_binding_description,
		vertexBindingDescriptionCount = 1,
		pVertexAttributeDescriptions = &line_input_attribute_descriptions[0],
		vertexAttributeDescriptionCount = len(line_input_attribute_descriptions),
	};

	line_input_assembly_state_create_info := vk.PipelineInputAssemblyStateCreateInfo {
		sType = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
		topology = .LINE_LIST,
		primitiveRestartEnable = false,
	};

	line_rasterization_state_create_info := vk.PipelineRasterizationStateCreateInfo {
		sType = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
		depthClampEnable = false,
		rasterizerDiscardEnable = false,
		lineWidth = 1.0,
		depthBiasEnable = false,
	};

	line_pipeline_create_info := vk.GraphicsPipelineCreateInfo {
		sType = .GRAPHICS_PIPELINE_CREATE_INFO,
		pStages = &basic_stage_create_infos[0],
		stageCount = len(basic_stage_create_infos),
		pVertexInputState = &line_vertex_input_state_create_info,
		pInputAssemblyState = &line_input_assembly_state_create_info,
		pViewportState = &viewport_state_create_info,
		pRasterizationState = &line_rasterization_state_create_info,
		pMultisampleState = &multisample_state_create_info,
		pDepthStencilState = &depth_stencil_state_create_info,
		pColorBlendState = &color_blend_state_create_info,
		layout = mesh_pipeline_layout,
		renderPass = render_pass,
		subpass = 0,
	};

	// Triangle mesh
	tri_mesh_input_assembly_state_create_info := vk.PipelineInputAssemblyStateCreateInfo {
		sType = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
		topology = .TRIANGLE_LIST,
		primitiveRestartEnable = false,
	};

	tri_mesh_rasterization_state_create_info := vk.PipelineRasterizationStateCreateInfo {
		sType = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
		depthClampEnable = false,
		rasterizerDiscardEnable = false,
		polygonMode = .FILL,
		lineWidth = 1.0,
		cullMode = {.BACK},
		frontFace = .COUNTER_CLOCKWISE,
		depthBiasEnable = false,
	};

	tri_mesh_input_binding_description := vk.VertexInputBindingDescription {
		binding = 0,
		stride = 36,
		inputRate = .VERTEX,
	};

	tri_mesh_input_attribute_description_position := vk.VertexInputAttributeDescription {
		binding = 0,
		location = 0,
		format = .R32G32B32_SFLOAT,
		offset = 0,
	};

	basic_input_attribute_description_color := vk.VertexInputAttributeDescription {
		binding = 0,
		location = 1,
		format = .R32G32B32_SFLOAT,
		offset = 24,
	};

	basic_input_attribute_descriptions := [?]vk.VertexInputAttributeDescription {
		tri_mesh_input_attribute_description_position,
		basic_input_attribute_description_color,
	};

	basic_vertex_input_state_create_info := vk.PipelineVertexInputStateCreateInfo {
		sType = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
		pVertexBindingDescriptions = &tri_mesh_input_binding_description,
		vertexBindingDescriptionCount = 1,
		pVertexAttributeDescriptions = &basic_input_attribute_descriptions[0],
		vertexAttributeDescriptionCount = len(basic_input_attribute_descriptions),
	};

	basic_pipeline_create_info := vk.GraphicsPipelineCreateInfo {
		sType = .GRAPHICS_PIPELINE_CREATE_INFO,
		pStages = &basic_stage_create_infos[0],
		stageCount = len(basic_stage_create_infos),
		pVertexInputState = &basic_vertex_input_state_create_info,
		pInputAssemblyState = &tri_mesh_input_assembly_state_create_info,
		pViewportState = &viewport_state_create_info,
		pRasterizationState = &tri_mesh_rasterization_state_create_info,
		pMultisampleState = &multisample_state_create_info,
		pDepthStencilState = &depth_stencil_state_create_info,
		pColorBlendState = &color_blend_state_create_info,
		layout = mesh_pipeline_layout,
		renderPass = render_pass,
		subpass = 0,
	};

	// Lambert
	lambert_vert_module := create_shader_module(logical_device, "lambert.vert");
	defer vk.DestroyShaderModule(logical_device, lambert_vert_module, nil);
	lambert_vert_stage_create_info := vk.PipelineShaderStageCreateInfo {
		sType = .PIPELINE_SHADER_STAGE_CREATE_INFO,
		stage = {.VERTEX},
		module = lambert_vert_module,
		pName = shader_entry_point,
	};

	lambert_frag_module := create_shader_module(logical_device, "lambert.frag");
	defer vk.DestroyShaderModule(logical_device, lambert_frag_module, nil);
	lambert_frag_stage_create_info := vk.PipelineShaderStageCreateInfo {
		sType = .PIPELINE_SHADER_STAGE_CREATE_INFO,
		stage = {.FRAGMENT},
		module = lambert_frag_module,
		pName = shader_entry_point,
	};

	lambert_stage_create_infos := [?]vk.PipelineShaderStageCreateInfo {lambert_vert_stage_create_info, lambert_frag_stage_create_info};

	lambert_input_attribute_description_normal := vk.VertexInputAttributeDescription {
		binding = 0,
		location = 1,
		format = .R32G32B32_SFLOAT,
		offset = 12,
	};

	lambert_input_attribute_description_color := vk.VertexInputAttributeDescription {
		binding = 0,
		location = 2,
		format = .R32G32B32_SFLOAT,
		offset = 24,
	};

	lambert_input_attribute_descriptions := [?]vk.VertexInputAttributeDescription {
		tri_mesh_input_attribute_description_position,
		lambert_input_attribute_description_normal,
		lambert_input_attribute_description_color,
	};

	lambert_vertex_input_state_create_info := vk.PipelineVertexInputStateCreateInfo {
		sType = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
		pVertexBindingDescriptions = &tri_mesh_input_binding_description,
		vertexBindingDescriptionCount = 1,
		pVertexAttributeDescriptions = &lambert_input_attribute_descriptions[0],
		vertexAttributeDescriptionCount = len(lambert_input_attribute_descriptions),
	};

	lambert_pipeline_create_info := vk.GraphicsPipelineCreateInfo {
		sType = .GRAPHICS_PIPELINE_CREATE_INFO,
		pStages = &lambert_stage_create_infos[0],
		stageCount = len(lambert_stage_create_infos),
		pVertexInputState = &lambert_vertex_input_state_create_info,
		pInputAssemblyState = &tri_mesh_input_assembly_state_create_info,
		pViewportState = &viewport_state_create_info,
		pRasterizationState = &tri_mesh_rasterization_state_create_info,
		pMultisampleState = &multisample_state_create_info,
		pDepthStencilState = &depth_stencil_state_create_info,
		pColorBlendState = &color_blend_state_create_info,
		layout = mesh_pipeline_layout,
		renderPass = render_pass,
		subpass = 0,
	};

	// Create pipelines
	pipeline_create_infos := [PIPELINES_COUNT]vk.GraphicsPipelineCreateInfo {
		line_pipeline_create_info,
		basic_pipeline_create_info,
		lambert_pipeline_create_info,
	};

	pipelines: [PIPELINES_COUNT]vk.Pipeline;
	r := vk.CreateGraphicsPipelines(logical_device, {}, len(pipeline_create_infos), &pipeline_create_infos[0], nil, &pipelines[0]);
	assert(r == .SUCCESS);

	return pipelines;
}