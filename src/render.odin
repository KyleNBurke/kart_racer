package main;

import "core:c";
import "core:fmt";
import "core:mem";
import vk "vendor:vulkan";
import "core:math/linalg";
import "vk2";
import "entity";

render :: proc(using vulkan: ^vk2.Vulkan, camera: ^Camera, entities: ^entity.Entities) -> bool {
	@(static) logical_frame_index := 0;
	logical_device := vulkan_context.logical_device;

	// Wait for this logical frame to become available
	r := vk.WaitForFences(logical_device, 1, &fences[logical_frame_index], true, c.UINT64_MAX);
	assert(r == .SUCCESS);

	// Acquire a swapchain image to render to
	image_index: u32;
	r = vk.AcquireNextImageKHR(logical_device, swapchain, c.UINT64_MAX, image_available_semaphores[logical_frame_index], {}, &image_index);
	if r == .ERROR_OUT_OF_DATE_KHR do return true;
	assert(r == .SUCCESS);

	framebuffer := swapchain_frames[image_index].framebuffer;

	r = vk.ResetFences(logical_device, 1, &fences[logical_frame_index]);
	assert(r == .SUCCESS);

	// Copy data and record draw commands
	handle_scene(vulkan, logical_frame_index, framebuffer, camera, entities);

	// Record primary command buffer
	command_buffer_begin_info := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
		flags = {.ONE_TIME_SUBMIT},
	};

	color_clear_value := vk.ClearValue {
		color = vk.ClearColorValue {
			float32 = [4]f32 {0.0, 0.0, 0.0, 1.0},
		},
	};

	depth_clear_value := vk.ClearValue {
		depthStencil = vk.ClearDepthStencilValue {
			depth = 1.0,
			stencil = 0,
		},
	};

	clear_values := [?]vk.ClearValue{color_clear_value, depth_clear_value};

	render_pass_begin_info := vk.RenderPassBeginInfo {
		sType = .RENDER_PASS_BEGIN_INFO,
		renderPass = render_pass,
		framebuffer = framebuffer,
		renderArea = vk.Rect2D {
			vk.Offset2D { 0, 0 },
			vk.Extent2D { extent.width, extent.height },
		},
		pClearValues = &clear_values[0],
		clearValueCount = len(clear_values),
	};

	primary_command_buffer := primary_command_buffers[logical_frame_index];

	secondary_command_buffers := [?]vk.CommandBuffer {
		mesh_resources.basic_secondary_command_buffers[logical_frame_index],
		mesh_resources.lambert_secondary_command_buffers[logical_frame_index],
	};

	r = vk.BeginCommandBuffer(primary_command_buffers[logical_frame_index], &command_buffer_begin_info);
	assert(r == .SUCCESS);

	vk.CmdBeginRenderPass(primary_command_buffer, &render_pass_begin_info, .SECONDARY_COMMAND_BUFFERS);
	vk.CmdExecuteCommands(primary_command_buffer, cast(u32) len(secondary_command_buffers), &secondary_command_buffers[0]);
	vk.CmdEndRenderPass(primary_command_buffer);

	r = vk.EndCommandBuffer(primary_command_buffer);
	assert(r == .SUCCESS);

	// Wait for image to be available then submit primary command buffer
	wait_stages: vk.PipelineStageFlags = {.COLOR_ATTACHMENT_OUTPUT};

	submit_info := vk.SubmitInfo {
		sType = .SUBMIT_INFO,
		pWaitSemaphores = &image_available_semaphores[logical_frame_index],
		waitSemaphoreCount = 1,
		pWaitDstStageMask = &wait_stages,
		pCommandBuffers = &primary_command_buffer,
		commandBufferCount = 1,
		pSignalSemaphores = &render_finished_semaphores[logical_frame_index],
		signalSemaphoreCount = 1,
	};

	r = vk.QueueSubmit(vulkan_context.graphics_queue, 1, &submit_info, fences[logical_frame_index]);
	assert(r == .SUCCESS);

	// Wait for render to finish then present swapchain image
	present_info := vk.PresentInfoKHR {
		sType = .PRESENT_INFO_KHR,
		pWaitSemaphores = &render_finished_semaphores[logical_frame_index],
		waitSemaphoreCount = 1,
		pSwapchains = &swapchain,
		swapchainCount = 1,
		pImageIndices = &image_index,
	};

	r = vk.QueuePresentKHR(vulkan_context.present_queue, &present_info);
	
	suboptimal := false;
	if r == .ERROR_OUT_OF_DATE_KHR || r == .SUBOPTIMAL_KHR {
		suboptimal = true;
	} else if r != .SUCCESS {
		panic("Failed to present swapchain image");
	}

	logical_frame_index = (logical_frame_index + 1) % vk2.IFFC;
	
	return suboptimal;
}

handle_scene :: proc(using vulkan: ^vk2.Vulkan, logical_frame_index: int, framebuffer: vk.Framebuffer, camera: ^Camera, entities: ^entity.Entities) {
	logical_device := vulkan_context.logical_device;

	{ // Copy matrices into per frame buffer
		per_frame_buffer_memory := frame_resources.per_frame_buffers_memory[logical_frame_index];

		per_frame_buffer_rawptr: rawptr;
		vk.MapMemory(logical_device, per_frame_buffer_memory, 0, cast(vk.DeviceSize) vk.WHOLE_SIZE, {}, &per_frame_buffer_rawptr);
		per_frame_buffer_ptr := cast(^u8) per_frame_buffer_rawptr;

		mem.copy_non_overlapping(per_frame_buffer_ptr, &camera.projection, size_of(camera.projection));

		view_mat := linalg.matrix4_inverse(camera.transform);
		mem.copy_non_overlapping(mem.ptr_offset(per_frame_buffer_ptr, 64), &view_mat, size_of(view_mat));

		range := vk.MappedMemoryRange {
			sType = .MAPPED_MEMORY_RANGE,
			memory = per_frame_buffer_memory,
			offset = 0,
			size = cast(vk.DeviceSize) vk.WHOLE_SIZE,
		};

		r := vk.FlushMappedMemoryRanges(logical_device, 1, &range);
		assert(r == .SUCCESS);

		vk.UnmapMemory(logical_device, per_frame_buffer_memory);
	}

	per_instance_buffer := frame_resources.per_instance_buffers[logical_frame_index];
	per_instance_buffer_memory := frame_resources.per_instance_buffers_memory[logical_frame_index];

	// Map per instance buffer
	per_instance_buffer_rawptr: rawptr;
	vk.MapMemory(logical_device, per_instance_buffer_memory, 0, cast(vk.DeviceSize) vk.WHOLE_SIZE, {}, &per_instance_buffer_rawptr);
	per_instance_buffer_ptr := cast(^u8) per_instance_buffer_rawptr;

	// Begin secondary command buffers and bind rendering resources
	command_buffer_inheritance_info := vk.CommandBufferInheritanceInfo {
		sType = .COMMAND_BUFFER_INHERITANCE_INFO,
		renderPass = render_pass,
		subpass = 0,
		framebuffer = framebuffer,
	};

	command_buffer_begin_info := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
		flags = {.RENDER_PASS_CONTINUE, .ONE_TIME_SUBMIT},
		pInheritanceInfo = &command_buffer_inheritance_info,
	};

	basic_secondary_command_buffer := mesh_resources.basic_secondary_command_buffers[logical_frame_index];
	lambert_secondary_command_buffer := mesh_resources.lambert_secondary_command_buffers[logical_frame_index];

	r := vk.BeginCommandBuffer(basic_secondary_command_buffer, &command_buffer_begin_info);
	assert(r == .SUCCESS);
	vk.CmdBindPipeline(basic_secondary_command_buffer, .GRAPHICS, mesh_resources.basic_pipeline);
	vk.CmdBindDescriptorSets(basic_secondary_command_buffer, .GRAPHICS, mesh_resources.pipeline_layout, 0, 1, &frame_resources.descriptor_sets[0], 0, {});
	vk.CmdBindDescriptorSets(basic_secondary_command_buffer, .GRAPHICS, mesh_resources.pipeline_layout, 1, 1, &mesh_resources.instance_descriptor_sets[0], 0, {});

	r = vk.BeginCommandBuffer(lambert_secondary_command_buffer, &command_buffer_begin_info);
	assert(r == .SUCCESS);
	vk.CmdBindPipeline(lambert_secondary_command_buffer, .GRAPHICS, mesh_resources.lambert_pipeline);
	vk.CmdBindDescriptorSets(lambert_secondary_command_buffer, .GRAPHICS, mesh_resources.pipeline_layout, 0, 1, &frame_resources.descriptor_sets[0], 0, {});
	vk.CmdBindDescriptorSets(lambert_secondary_command_buffer, .GRAPHICS, mesh_resources.pipeline_layout, 1, 1, &mesh_resources.instance_descriptor_sets[0], 0, {});

	// Copy mesh data and record draw commands
	geometry_offset := 0;
	instance_offset := mesh_resources.per_instance_buffer_instance_block_offset;
	first_instance: u32 = 0;

	for record in &entities.geometry_records {
		index_array_size := size_of(u16) * len(record.geometry.indices);
		attribute_array_size := size_of(f32) * len(record.geometry.attributes);

		index_array_offset := geometry_offset;
		attribute_array_offset := vk2.align_forward(index_array_offset + index_array_size, 4);
		geometry_offset = attribute_array_offset + attribute_array_size;

		when ODIN_DEBUG {
			assert(geometry_offset <= instance_offset);
			assert(int(first_instance) + len(record.entities) <= vk2.MAX_ENTITIES);
		}

		// Copy geometry data
		mem.copy_non_overlapping(mem.ptr_offset(per_instance_buffer_ptr, index_array_offset), raw_data(record.geometry.indices), index_array_size);
		mem.copy_non_overlapping(mem.ptr_offset(per_instance_buffer_ptr, attribute_array_offset), raw_data(record.geometry.attributes), attribute_array_size);

		// Copy matrix data
		for e in &record.entities {
			mem.copy_non_overlapping(mem.ptr_offset(per_instance_buffer_ptr, instance_offset), &e.transform, size_of(e.transform));
			instance_offset += vk2.MESH_INSTANCE_ELEMENT_SIZE;
		}

		// Record draw command
		vertex_buffers := [?]vk.Buffer {per_instance_buffer};
		offsets := [?]vk.DeviceSize {cast(vk.DeviceSize) attribute_array_offset};

		secondary_command_buffer: vk.CommandBuffer;
		switch record.geometry.pipeline {
			case .Line:

			case .Basic:
				secondary_command_buffer = basic_secondary_command_buffer;
			case .Lambert:
				secondary_command_buffer = lambert_secondary_command_buffer;
		}

		vk.CmdBindIndexBuffer(secondary_command_buffer, per_instance_buffer, cast(vk.DeviceSize) index_array_offset, .UINT16);
		vk.CmdBindVertexBuffers(secondary_command_buffer, 0, 1, &vertex_buffers[0], &offsets[0]);
		vk.CmdDrawIndexed(secondary_command_buffer, cast(u32) len(record.geometry.indices), cast(u32) len(record.entities), 0, 0, first_instance);

		instance_offset += len(record.entities);
	}

	// End secondary command buffers
	r = vk.EndCommandBuffer(basic_secondary_command_buffer);
	assert(r == .SUCCESS);

	r = vk.EndCommandBuffer(lambert_secondary_command_buffer);
	assert(r == .SUCCESS);

	// Flush and unmap per instance buffer
	range := vk.MappedMemoryRange {
		sType = .MAPPED_MEMORY_RANGE,
		memory = per_instance_buffer_memory,
		offset = 0,
		size = cast(vk.DeviceSize) vk.WHOLE_SIZE,
	};

	r = vk.FlushMappedMemoryRanges(logical_device, 1, &range);
	assert(r == .SUCCESS);

	vk.UnmapMemory(logical_device, per_instance_buffer_memory);
}