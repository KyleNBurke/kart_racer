package main;

import "core:fmt";
import "core:c";
import "core:os";
import "core:slice";
import "core:mem";
import "core:math/linalg";
import vk "vendor:vulkan";
import "vendor:glfw";

IFFC :: 2; // In flight frames count
PIPELINES_COUNT :: 5;
MESH_INSTANCE_ELEMENT_SIZE :: 64;
PARTICLE_INSTANCE_ELEMENT_SIZE :: 32;
MAX_ENTITIES :: 1000;
MAX_PARTICLES :: 5000;

INSTANCE_BUFFER_INDICES_ATTRIBUTES_BLOCK_SIZE :: 5_000_000;
INSTANCE_BUFFER_MESH_INSTANCE_BLOCK_SIZE :: MESH_INSTANCE_ELEMENT_SIZE * MAX_ENTITIES;
INSTANCE_BUFFER_PARTICLE_INSTANCE_BLOCK_SIZE :: PARTICLE_INSTANCE_ELEMENT_SIZE * MAX_PARTICLES; 

TEXT_PUSH_CONSTANTS_SIZE :: 16;

Vulkan :: struct {
	vulkan_context: Vulkan_Context,
	surface_format: vk.SurfaceFormatKHR,
	depth_format: vk.Format,
	render_pass: vk.RenderPass,
	extent: vk.Extent2D,
	depth_image: Depth_Image,
	swapchain: vk.SwapchainKHR,
	swapchain_frames: [dynamic]Swapchain_Frame,
	descriptor_pool: vk.DescriptorPool,
	command_pool: vk.CommandPool,
	image_available_semaphores: [IFFC]vk.Semaphore,
	render_finished_semaphores: [IFFC]vk.Semaphore,
	fences: [IFFC]vk.Fence,
	primary_command_buffers: [IFFC]vk.CommandBuffer,
	frame_resources: Frame_Resources,
	mesh_resources: Mesh_Resources,
	particle_resources: Particle_Resources,
	ui_resources: UI_Resources,
	logical_frame_index: int,
	image_index: u32,
}

Depth_Image :: struct {
	image: vk.Image,
	image_view: vk.ImageView,
	memory: vk.DeviceMemory,
}

Swapchain_Frame :: struct {
	color_image_view: vk.ImageView,
	framebuffer: vk.Framebuffer,
}

Frame_Resources :: struct {
	descriptor_set_layout: vk.DescriptorSetLayout,
	descriptor_sets: [IFFC]vk.DescriptorSet,
	
	// This buffer holds per frame data like the projection and view matrices.
	per_frame_buffers: [IFFC]vk.Buffer,
	per_frame_buffers_memory: [IFFC]vk.DeviceMemory,

	// This buffer hold per instance data whether it be for a mesh, particle, text, etc.
	// E.g. mesh instance transformation matrix, particle instance position, size and color.
	per_instance_buffers: [IFFC]vk.Buffer,
	per_instance_buffers_memory: [IFFC]vk.DeviceMemory,

	per_instance_buffer_ptr: ^u8,
}

Mesh_Resources :: struct {
	per_instance_buffer_instance_block_offset: int,
	line_secondary_command_buffers: [IFFC]vk.CommandBuffer,
	basic_secondary_command_buffers: [IFFC]vk.CommandBuffer,
	lambert_secondary_command_buffers: [IFFC]vk.CommandBuffer,
	lambert_two_sided_secondary_command_buffers: [IFFC]vk.CommandBuffer,
	instance_descriptor_set_layout: vk.DescriptorSetLayout,
	instance_descriptor_sets: [IFFC]vk.DescriptorSet,
	pipeline_layout: vk.PipelineLayout,
	line_pipeline: vk.Pipeline,
	basic_pipeline: vk.Pipeline,
	lambert_pipeline: vk.Pipeline,
	lambert_two_sided_pipeline: vk.Pipeline,
}

Particle_Resources :: struct {
	per_instance_buffer_instance_block_offset: int,
	secondary_command_buffers: [IFFC]vk.CommandBuffer,
	instance_descriptor_set_layout: vk.DescriptorSetLayout,
	instance_descriptor_sets: [IFFC]vk.DescriptorSet,
	pipeline_layout: vk.PipelineLayout,
	pipeline: vk.Pipeline,
	instance_offset: int,
	first_instance: u32,
}

UI_Resources :: struct {

}

Frame_Data :: struct #align(4) {
	projection_mat,
	view_mat,
	camera_mat: linalg.Matrix4f32,
}

Render_Particle :: struct #align(4) {
	position: linalg.Vector3f32,
	size: f32,
	color: [3]f32,
}

init_vulkan :: proc(using vulkan: ^Vulkan, window: glfw.WindowHandle) {
	framebuffer_width, framebuffer_height := glfw.GetFramebufferSize(window);
	
	vulkan_context = init_vulkan_context(window);
	using vulkan_context;

	surface_format = find_color_surface_format(physical_device, vulkan_context.window_surface);
	depth_format = find_depth_format(physical_device);
	render_pass = create_render_pass(logical_device, surface_format.format, depth_format);
	extent = create_extent(physical_device, window_surface, u32(framebuffer_width), u32(framebuffer_height));
	depth_image = create_depth_image(logical_device, physical_device, depth_format, extent);
	swapchain, swapchain_frames = create_swapchain(&vulkan_context, surface_format, extent, render_pass, depth_image.image_view);
	descriptor_pool = create_descriptor_pool(logical_device, 1);
	command_pool = create_command_pool(logical_device, graphics_queue_family);
	image_available_semaphores = create_semaphores(logical_device);
	render_finished_semaphores = create_semaphores(logical_device);
	fences = create_fences(logical_device);
	primary_command_buffers = create_primary_command_buffers(logical_device, command_pool);
	secondary_command_buffers := create_secondary_command_buffers(logical_device, command_pool);
	
	frame_descriptor_set_layout, frame_descriptor_sets := create_frame_descriptor_sets(logical_device, descriptor_pool);
	per_frame_buffers, per_frame_buffers_memory := create_per_frame_buffers(physical_device, logical_device);
	update_frame_descriptor_sets(logical_device, frame_descriptor_sets, per_frame_buffers);
	per_instance_buffer_info := calculate_per_instance_buffer_info(physical_device);
	per_instance_buffers, per_instance_buffers_memory := create_per_instance_buffers(physical_device, logical_device, per_instance_buffer_info.total_size);
	
	frame_resources = Frame_Resources {
		descriptor_set_layout = frame_descriptor_set_layout,
		descriptor_sets = frame_descriptor_sets,
		per_frame_buffers = per_frame_buffers,
		per_frame_buffers_memory = per_frame_buffers_memory,
		per_instance_buffers = per_instance_buffers,
		per_instance_buffers_memory = per_instance_buffers_memory,
	};

	mesh_instance_descriptor_set_layout, mesh_instance_descriptor_sets := create_mesh_descriptor_sets(logical_device, descriptor_pool);
	update_mesh_instance_descriptor_sets(logical_device, mesh_instance_descriptor_sets, per_instance_buffers, per_instance_buffer_info.mesh_instance_block_offset);
	mesh_descriptor_set_layouts := [2]vk.DescriptorSetLayout {frame_descriptor_set_layout, mesh_instance_descriptor_set_layout};
	mesh_pipeline_layout := create_mesh_pipeline_layout(logical_device, &mesh_descriptor_set_layouts);

	particle_instance_descriptor_set_layout, particle_instance_descriptor_sets := create_particle_descriptor_sets(logical_device, descriptor_pool);
	update_particle_descriptor_sets(logical_device, particle_instance_descriptor_sets, per_instance_buffers, per_instance_buffer_info.particle_instance_block_offset);
	particle_descriptor_set_layouts := [2]vk.DescriptorSetLayout {frame_descriptor_set_layout, particle_instance_descriptor_set_layout};
	particle_pipeline_layout := create_particle_pipeline_layout(logical_device, &particle_descriptor_set_layouts);
	
	pipelines := create_pipelines(logical_device, render_pass, extent, mesh_pipeline_layout, particle_pipeline_layout);

	mesh_resources = Mesh_Resources {
		per_instance_buffer_instance_block_offset = per_instance_buffer_info.mesh_instance_block_offset,
		line_secondary_command_buffers = secondary_command_buffers.line,
		basic_secondary_command_buffers = secondary_command_buffers.basic,
		lambert_secondary_command_buffers = secondary_command_buffers.lambert,
		lambert_two_sided_secondary_command_buffers = secondary_command_buffers.lambert_two_sided,
		instance_descriptor_set_layout = mesh_instance_descriptor_set_layout,
		instance_descriptor_sets = mesh_instance_descriptor_sets,
		pipeline_layout = mesh_pipeline_layout,
		line_pipeline = pipelines[0],
		basic_pipeline = pipelines[1],
		lambert_pipeline = pipelines[2],
		lambert_two_sided_pipeline = pipelines[3],
	};

	particle_resources = Particle_Resources {
		per_instance_buffer_instance_block_offset = per_instance_buffer_info.particle_instance_block_offset,
		secondary_command_buffers = secondary_command_buffers.particle,
		instance_descriptor_set_layout = particle_instance_descriptor_set_layout,
		instance_descriptor_sets = particle_instance_descriptor_sets,
		pipeline_layout = particle_pipeline_layout,
		pipeline = pipelines[4],
	}
}

vulkan_cleanup :: proc(using vulkan: ^Vulkan) {
	logical_device := vulkan_context.logical_device;
	vk.DeviceWaitIdle(logical_device);

	vk.DestroyPipeline(logical_device, particle_resources.pipeline, nil);
	vk.DestroyPipelineLayout(logical_device, particle_resources.pipeline_layout, nil);
	vk.DestroyDescriptorSetLayout(logical_device, particle_resources.instance_descriptor_set_layout, nil);
	
	vk.DestroyPipeline(logical_device, mesh_resources.lambert_two_sided_pipeline, nil);
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
	vk.DestroyPipeline(logical_device, particle_resources.pipeline, nil);
	vk.DestroyPipeline(logical_device, mesh_resources.lambert_two_sided_pipeline, nil);
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

	pipelines := create_pipelines(
		logical_device,
		render_pass,
		extent,
		mesh_resources.pipeline_layout,
		particle_resources.pipeline_layout);
	
	mesh_resources.line_pipeline = pipelines[0];
	mesh_resources.basic_pipeline = pipelines[1];
	mesh_resources.lambert_pipeline = pipelines[2];
	mesh_resources.lambert_two_sided_pipeline = pipelines[3];
	particle_resources.pipeline = pipelines[4];

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

create_depth_image :: proc(logical_device: vk.Device, physical_device: vk.PhysicalDevice, format: vk.Format, extent: vk.Extent2D) -> Depth_Image {
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

	return Depth_Image {
		image,
		image_view,
		memory,
	}
}

create_swapchain :: proc(
	using vulkan_context: ^Vulkan_Context,
	color_surface_format: vk.SurfaceFormatKHR,
	extent: vk.Extent2D,
	render_pass: vk.RenderPass,
	depth_image_view: vk.ImageView,
) -> (vk.SwapchainKHR, [dynamic]Swapchain_Frame) {
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

	swapchain_frames := make([dynamic]Swapchain_Frame, swapchain_images_count);

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

		swapchain_frames[i] = Swapchain_Frame {image_view, framebuffer};
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
	line, basic, lambert, lambert_two_sided, particle: [IFFC]vk.CommandBuffer,
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
	assert(vk.AllocateCommandBuffers(logical_device, &allocate_info, &command_buffers_array[0]) == .SUCCESS);

	line, basic, lambert, lambert_two_sided, particle: [IFFC]vk.CommandBuffer;
	
	for i in 0..<IFFC {
		line[i]              = command_buffers_array[PIPELINES_COUNT * i];
		basic[i]             = command_buffers_array[PIPELINES_COUNT * i + 1];
		lambert[i]           = command_buffers_array[PIPELINES_COUNT * i + 2];
		lambert_two_sided[i] = command_buffers_array[PIPELINES_COUNT * i + 3];
		particle[i]          = command_buffers_array[PIPELINES_COUNT * i + 4];
	}

	return SecondaryCommandBuffers { line, basic, lambert, lambert_two_sided, particle };
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

create_per_frame_buffers :: proc(physical_device: vk.PhysicalDevice, logical_device: vk.Device) -> ([IFFC]vk.Buffer, [IFFC]vk.DeviceMemory) {
	buffers: [IFFC]vk.Buffer;
	buffers_memory: [IFFC]vk.DeviceMemory;

	for i in 0..<IFFC {
		buffer, memory := create_allocate_and_bind_buffer_memory(physical_device, logical_device, {.UNIFORM_BUFFER}, {.HOST_VISIBLE}, size_of(Frame_Data));
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

	vk.UpdateDescriptorSets(logical_device, IFFC, &write_descriptor_sets[0], 0, nil);
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

Per_Instance_Buffer_Info :: struct {
	mesh_instance_block_offset,
	particle_instance_block_offset,
	total_size: int,
}

calculate_per_instance_buffer_info :: proc(physical_device: vk.PhysicalDevice) -> Per_Instance_Buffer_Info {
	physical_device_properties: vk.PhysicalDeviceProperties;
	vk.GetPhysicalDeviceProperties(physical_device, &physical_device_properties);
	alignment := cast(int) physical_device_properties.limits.minStorageBufferOffsetAlignment;

	unaligned_mesh_instance_block_offset := INSTANCE_BUFFER_INDICES_ATTRIBUTES_BLOCK_SIZE;
	// aligned_mesh_instance_block_offset := math2.align_forward(unaligned_mesh_instance_block_offset, alignment);
	aligned_mesh_instance_block_offset := mem.align_forward_int(unaligned_mesh_instance_block_offset, alignment);

	unaligned_particle_instance_block_offset := aligned_mesh_instance_block_offset + INSTANCE_BUFFER_MESH_INSTANCE_BLOCK_SIZE;
	// aligned_particle_instance_block_offset := math2.align_forward(unaligned_particle_instance_block_offset, alignment);
	aligned_particle_instance_block_offset := mem.align_forward_int(unaligned_particle_instance_block_offset, alignment);

	total_size := aligned_particle_instance_block_offset + INSTANCE_BUFFER_PARTICLE_INSTANCE_BLOCK_SIZE;

	return Per_Instance_Buffer_Info {
		mesh_instance_block_offset = aligned_mesh_instance_block_offset,
		particle_instance_block_offset = aligned_particle_instance_block_offset,
		total_size = total_size,
	};
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

	vk.UpdateDescriptorSets(logical_device, IFFC, &write_descriptor_sets[0], 0, nil);
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

create_particle_descriptor_sets :: proc(logical_device: vk.Device, descriptor_pool: vk.DescriptorPool) -> (vk.DescriptorSetLayout, [IFFC]vk.DescriptorSet) {
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

update_particle_descriptor_sets :: proc(logical_device: vk.Device, descriptor_sets: [IFFC]vk.DescriptorSet, buffers: [IFFC]vk.Buffer, particle_instance_block_offset: int) {
	descriptor_buffer_infos: [IFFC]vk.DescriptorBufferInfo;
	write_descriptor_sets: [IFFC]vk.WriteDescriptorSet;
	
	for i in 0..<IFFC {
		descriptor_buffer_infos[i] = vk.DescriptorBufferInfo {
			buffer = buffers[i],
			offset = cast(vk.DeviceSize) particle_instance_block_offset,
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

	vk.UpdateDescriptorSets(logical_device, IFFC, &write_descriptor_sets[0], 0, nil);
}

create_particle_pipeline_layout :: proc(logical_device: vk.Device, descriptor_set_layouts: ^[2]vk.DescriptorSetLayout) -> vk.PipelineLayout {
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