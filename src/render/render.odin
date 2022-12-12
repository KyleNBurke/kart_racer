package render;

import "core:fmt";
import "core:c";
import "vendor:glfw";
import vk "vendor:vulkan";

LOGICAL_FRAMES_COUNT :: 2;

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
	frame_data_descriptor_set_layout: vk.DescriptorSetLayout,
	mesh_resources: MeshResources,
	logical_frames: [LOGICAL_FRAMES_COUNT]LogicalFrame,
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
	instance_data_descriptor_set_layout: vk.DescriptorSetLayout,
}

LineResources :: struct {

}

ParticleResources :: struct {

}

UiResources :: struct {
	
}

LogicalFrame :: struct {
	image_available_semaphore: vk.Semaphore,
	render_finished_semaphore: vk.Semaphore,
	fence: vk.Fence,
	primary_command_buffer: vk.CommandBuffer,
	basic_secondary_command_buffer: vk.CommandBuffer,
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
	frame_data_descriptor_set_layout := create_frame_data_descriptor_set_layout(logical_device);
	instance_data_descriptor_set_layout := create_instance_data_descriptor_set_layout(logical_device);

	mesh_resources := MeshResources {
		instance_data_descriptor_set_layout,
	};

	logical_frames := create_logical_frames(logical_device, command_pool, descriptor_pool);

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
		frame_data_descriptor_set_layout,
		mesh_resources,
		logical_frames,
	};
}

cleanup_vulkan :: proc(using vulkan: ^Vulkan) {
	logical_device := vulkan_context.logical_device;
	vk.DeviceWaitIdle(logical_device);

	for frame in &logical_frames {
		vk.DestroyFence(logical_device, frame.fence, nil);
		vk.DestroySemaphore(logical_device, frame.render_finished_semaphore, nil);
		vk.DestroySemaphore(logical_device, frame.image_available_semaphore, nil);
	}

	vk.DestroyDescriptorSetLayout(logical_device, mesh_resources.instance_data_descriptor_set_layout, nil);
	vk.DestroyDescriptorSetLayout(logical_device, frame_data_descriptor_set_layout, nil);
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

render :: proc(using vulkan: ^Vulkan) -> bool {
	@(static) logical_frame_index := 0;
	logical_device := vulkan_context.logical_device;

	logical_frame := &logical_frames[logical_frame_index];

	// Wait for this logical frame to become available
	r := vk.WaitForFences(logical_device, 1, &logical_frame.fence, true, c.UINT64_MAX);
	assert(r == .SUCCESS);

	// Acquire a swapchain image to render to
	image_index: u32;
	r = vk.AcquireNextImageKHR(logical_device, swapchain, c.UINT64_MAX, logical_frame.image_available_semaphore, {}, &image_index);
	if r == .ERROR_OUT_OF_DATE_KHR do return true;
	assert(r == .SUCCESS);

	framebuffer := swapchain_frames[image_index].framebuffer;

	r = vk.ResetFences(logical_device, 1, &logical_frame.fence);
	assert(r == .SUCCESS);

	// Copy data and record draw commands
	handle_scene(render_pass, framebuffer, logical_frame);

	// Record primary command buffer
	command_buffer_begin_info: vk.CommandBufferBeginInfo;
	command_buffer_begin_info.sType = .COMMAND_BUFFER_BEGIN_INFO;
	command_buffer_begin_info.flags = {.ONE_TIME_SUBMIT};

	color_clear_value: vk.ClearValue;
	color_clear_value.color.float32 = [4]f32{ 0.0, 0.0, 0.0, 1.0 };

	depth_clear_value: vk.ClearValue;
	depth_clear_value.depthStencil.depth = 1.0;
	depth_clear_value.depthStencil.stencil = 0;

	clear_values := [?]vk.ClearValue{color_clear_value, depth_clear_value};

	render_pass_begin_info: vk.RenderPassBeginInfo;
	render_pass_begin_info.sType = .RENDER_PASS_BEGIN_INFO;
	render_pass_begin_info.renderPass = render_pass;
	render_pass_begin_info.framebuffer = framebuffer;
	render_pass_begin_info.renderArea = vk.Rect2D {
		vk.Offset2D { 0, 0 },
		vk.Extent2D { extent.width, extent.height },
	};
	render_pass_begin_info.pClearValues = &clear_values[0];
	render_pass_begin_info.clearValueCount = len(clear_values);

	secondary_command_buffers := [?]vk.CommandBuffer {
		logical_frame.basic_secondary_command_buffer,
	};

	r = vk.BeginCommandBuffer(logical_frame.primary_command_buffer, &command_buffer_begin_info);
	assert(r == .SUCCESS);

	vk.CmdBeginRenderPass(logical_frame.primary_command_buffer, &render_pass_begin_info, .SECONDARY_COMMAND_BUFFERS);
	vk.CmdExecuteCommands(logical_frame.primary_command_buffer, cast(u32) len(secondary_command_buffers), &secondary_command_buffers[0]);
	vk.CmdEndRenderPass(logical_frame.primary_command_buffer);

	r = vk.EndCommandBuffer(logical_frame.primary_command_buffer);
	assert(r == .SUCCESS);

	// Wait for image to be available then submit primary command buffer
	wait_stages: vk.PipelineStageFlags = {.COLOR_ATTACHMENT_OUTPUT};

	submit_info: vk.SubmitInfo;
	submit_info.sType = .SUBMIT_INFO;
	submit_info.pWaitSemaphores = &logical_frame.image_available_semaphore;
	submit_info.waitSemaphoreCount = 1;
	submit_info.pWaitDstStageMask = &wait_stages;
	submit_info.pCommandBuffers = &logical_frame.primary_command_buffer;
	submit_info.commandBufferCount = 1;
	submit_info.pSignalSemaphores = &logical_frame.render_finished_semaphore;
	submit_info.signalSemaphoreCount = 1;

	r = vk.QueueSubmit(vulkan_context.graphics_queue, 1, &submit_info, logical_frame.fence);
	assert(r == .SUCCESS);

	// Wait for render to finish then present swapchain image
	present_info: vk.PresentInfoKHR;
	present_info.sType = .PRESENT_INFO_KHR;
	present_info.pWaitSemaphores = &logical_frame.render_finished_semaphore;
	present_info.waitSemaphoreCount = 1;
	present_info.pSwapchains = &swapchain;
	present_info.swapchainCount = 1;
	present_info.pImageIndices = &image_index;

	r = vk.QueuePresentKHR(vulkan_context.present_queue, &present_info);
	
	suboptimal := false;
	if r == .ERROR_OUT_OF_DATE_KHR || r == .SUBOPTIMAL_KHR {
		suboptimal = true;
	} else if r != .SUCCESS {
		panic("Failed to present swapchain image");
	}

	logical_frame_index = (logical_frame_index + 1) % LOGICAL_FRAMES_COUNT;
	
	return suboptimal;
}

handle_scene :: proc(render_pass: vk.RenderPass, framebuffer: vk.Framebuffer, logical_frame: ^LogicalFrame) {
	command_buffer_inheritance_info: vk.CommandBufferInheritanceInfo;
	command_buffer_inheritance_info.sType = .COMMAND_BUFFER_INHERITANCE_INFO;
	command_buffer_inheritance_info.renderPass = render_pass;
	command_buffer_inheritance_info.subpass = 0;
	command_buffer_inheritance_info.framebuffer = framebuffer;

	command_buffer_begin_info: vk.CommandBufferBeginInfo;
	command_buffer_begin_info.sType = .COMMAND_BUFFER_BEGIN_INFO;
	command_buffer_begin_info.flags = {.RENDER_PASS_CONTINUE, .ONE_TIME_SUBMIT};
	command_buffer_begin_info.pInheritanceInfo = &command_buffer_inheritance_info;

	r := vk.BeginCommandBuffer(logical_frame.basic_secondary_command_buffer, &command_buffer_begin_info);
	assert(r == .SUCCESS);

	r = vk.EndCommandBuffer(logical_frame.basic_secondary_command_buffer);
	assert(r == .SUCCESS);
}