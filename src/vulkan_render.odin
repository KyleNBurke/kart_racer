package main;

import "core:c";
import "core:fmt";
import "core:mem";
import vk "vendor:vulkan";
import "core:math/linalg";

import "math2";

begin_render_frame :: proc(using vulkan: ^Vulkan, camera: ^Camera, entities_geos: ^Entities_Geos, texts: ^[dynamic]Text) -> bool {
	logical_device := vulkan_context.logical_device;

	{ // Wait for this logical frame to become available
		r := vk.WaitForFences(logical_device, 1, &fences[logical_frame_index], true, c.UINT64_MAX);
		assert(r == .SUCCESS);
	}

	{ // Acquire a swapchain image to render to
		r := vk.AcquireNextImageKHR(logical_device, swapchain, c.UINT64_MAX, image_available_semaphores[logical_frame_index], {}, &image_index);
		if r == .ERROR_OUT_OF_DATE_KHR do return true;
		assert(r == .SUCCESS);
	}

	{ // Reset fence
		r := vk.ResetFences(logical_device, 1, &fences[logical_frame_index]);
		assert(r == .SUCCESS);
	}

	{ // Copy matrices into per frame buffer
		per_frame_buffer_memory := frame_resources.per_frame_buffers_memory[logical_frame_index];

		per_frame_buffer_rawptr: rawptr;
		vk.MapMemory(logical_device, per_frame_buffer_memory, 0, cast(vk.DeviceSize) vk.WHOLE_SIZE, {}, &per_frame_buffer_rawptr);
		per_frame_buffer_ptr := cast(^u8) per_frame_buffer_rawptr;

		frame_data := Frame_Data {
			projection_mat = camera.projection,
			view_mat = linalg.matrix4_inverse(camera.transform),
			camera_mat = camera.transform,
		};

		mem.copy_non_overlapping(per_frame_buffer_ptr, &frame_data, size_of(Frame_Data));

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

	// Map per instance buffer
	{
		per_instance_buffer_memory := frame_resources.per_instance_buffers_memory[logical_frame_index];

		per_instance_buffer_rawptr: rawptr;
		vk.MapMemory(logical_device, per_instance_buffer_memory, 0, cast(vk.DeviceSize) vk.WHOLE_SIZE, {}, &per_instance_buffer_rawptr);
		frame_resources.per_instance_buffer_ptr = cast(^u8) per_instance_buffer_rawptr;
	}

	line_secondary_command_buffer := mesh_resources.line_secondary_command_buffers[logical_frame_index];
	basic_secondary_command_buffer := mesh_resources.basic_secondary_command_buffers[logical_frame_index];
	lambert_secondary_command_buffer := mesh_resources.lambert_secondary_command_buffers[logical_frame_index];
	particle_secondary_command_buffer := particle_resources.secondary_command_buffers[logical_frame_index];
	text_secondary_command_buffer := ui_resources.text_secondary_command_buffer[logical_frame_index];

	{ // Begin secondary command buffers and bind rendering resources
		command_buffer_inheritance_info := vk.CommandBufferInheritanceInfo {
			sType = .COMMAND_BUFFER_INHERITANCE_INFO,
			renderPass = render_pass,
			subpass = 0,
			framebuffer = swapchain_frames[image_index].framebuffer,
		};
	
		command_buffer_begin_info := vk.CommandBufferBeginInfo {
			sType = .COMMAND_BUFFER_BEGIN_INFO,
			flags = {.RENDER_PASS_CONTINUE, .ONE_TIME_SUBMIT},
			pInheritanceInfo = &command_buffer_inheritance_info,
		};

		frame_descriptor_set := frame_resources.descriptor_sets[logical_frame_index];
		mesh_instance_descriptor_set := mesh_resources.instance_descriptor_sets[logical_frame_index];
		particle_instance_descriptor_set := particle_resources.instance_descriptor_sets[logical_frame_index];

		r := vk.BeginCommandBuffer(line_secondary_command_buffer, &command_buffer_begin_info);
		assert(r == .SUCCESS);
		vk.CmdBindPipeline(line_secondary_command_buffer, .GRAPHICS, mesh_resources.line_pipeline);
		vk.CmdBindDescriptorSets(line_secondary_command_buffer, .GRAPHICS, mesh_resources.pipeline_layout, 0, 1, &frame_descriptor_set, 0, {});
		vk.CmdBindDescriptorSets(line_secondary_command_buffer, .GRAPHICS, mesh_resources.pipeline_layout, 1, 1, &mesh_instance_descriptor_set, 0, {});

		r = vk.BeginCommandBuffer(basic_secondary_command_buffer, &command_buffer_begin_info);
		assert(r == .SUCCESS);
		vk.CmdBindPipeline(basic_secondary_command_buffer, .GRAPHICS, mesh_resources.basic_pipeline);
		vk.CmdBindDescriptorSets(basic_secondary_command_buffer, .GRAPHICS, mesh_resources.pipeline_layout, 0, 1, &frame_descriptor_set, 0, {});
		vk.CmdBindDescriptorSets(basic_secondary_command_buffer, .GRAPHICS, mesh_resources.pipeline_layout, 1, 1, &mesh_instance_descriptor_set, 0, {});

		r = vk.BeginCommandBuffer(lambert_secondary_command_buffer, &command_buffer_begin_info);
		assert(r == .SUCCESS);
		vk.CmdBindPipeline(lambert_secondary_command_buffer, .GRAPHICS, mesh_resources.lambert_pipeline);
		vk.CmdBindDescriptorSets(lambert_secondary_command_buffer, .GRAPHICS, mesh_resources.pipeline_layout, 0, 1, &frame_descriptor_set, 0, {});
		vk.CmdBindDescriptorSets(lambert_secondary_command_buffer, .GRAPHICS, mesh_resources.pipeline_layout, 1, 1, &mesh_instance_descriptor_set, 0, {});

		r = vk.BeginCommandBuffer(particle_secondary_command_buffer, &command_buffer_begin_info);
		assert(r == .SUCCESS);
		vk.CmdBindPipeline(particle_secondary_command_buffer, .GRAPHICS, particle_resources.pipeline);
		vk.CmdBindDescriptorSets(particle_secondary_command_buffer, .GRAPHICS, particle_resources.pipeline_layout, 0, 1, &frame_descriptor_set, 0, {});
		vk.CmdBindDescriptorSets(particle_secondary_command_buffer, .GRAPHICS, particle_resources.pipeline_layout, 1, 1, &particle_instance_descriptor_set, 0, {});

		r = vk.BeginCommandBuffer(text_secondary_command_buffer, &command_buffer_begin_info);
		assert(r == .SUCCESS);
		vk.CmdBindPipeline(text_secondary_command_buffer, .GRAPHICS, ui_resources.text_pipeline);
		vk.CmdBindDescriptorSets(text_secondary_command_buffer, .GRAPHICS, ui_resources.text_pipeline_layout, 0, 1, &ui_resources.sampler_descriptor_set, 0, {});
		vk.CmdBindDescriptorSets(text_secondary_command_buffer, .GRAPHICS, ui_resources.text_pipeline_layout, 1, 1, &ui_resources.atlas_descriptor_set, 0, {});
	}

	// Copy mesh data and record draw commands
	geometry_offset := 0;
	instance_offset := mesh_resources.per_instance_buffer_instance_block_offset;
	per_instance_buffer := frame_resources.per_instance_buffers[logical_frame_index];
	per_instance_buffer_ptr := frame_resources.per_instance_buffer_ptr;
	{
		first_instance: u32 = 0;

		for record in &entities_geos.geometry_records {
			if record.freed do continue;

			index_array_size := size_of(u16) * len(record.geometry.indices);
			attribute_array_size := size_of(f32) * len(record.geometry.attributes);

			index_array_offset := geometry_offset;
			attribute_array_offset := math2.align_forward(index_array_offset + index_array_size, 4);
			geometry_offset = attribute_array_offset + attribute_array_size;

			when ODIN_DEBUG {
				assert(geometry_offset <= instance_offset);
				assert(int(first_instance) <= MAX_ENTITIES);
				if record.on_no_entities == .Render do assert(len(record.entity_lookups) == 0);
			}

			// Copy geometry data
			mem.copy_non_overlapping(mem.ptr_offset(per_instance_buffer_ptr, index_array_offset), raw_data(record.geometry.indices), index_array_size);
			mem.copy_non_overlapping(mem.ptr_offset(per_instance_buffer_ptr, attribute_array_offset), raw_data(record.geometry.attributes), attribute_array_size);

			instance_count: u32;

			// Copy matrix data
			if len(record.entity_lookups) == 0 {
				transform := linalg.MATRIX4F32_IDENTITY;
				mem.copy_non_overlapping(mem.ptr_offset(per_instance_buffer_ptr, instance_offset), &transform, size_of(linalg.Matrix4f32));
				instance_offset += MESH_INSTANCE_ELEMENT_SIZE;
				instance_count = 1;
			} else {
				for entity_lookup in &record.entity_lookups {
					entity := entities_geos.entity_records[entity_lookup.index].entity;
					mem.copy_non_overlapping(mem.ptr_offset(per_instance_buffer_ptr, instance_offset), &entity.transform, size_of(linalg.Matrix4f32));
					instance_offset += MESH_INSTANCE_ELEMENT_SIZE;
				}

				instance_count = cast(u32) len(record.entity_lookups);
			}

			// Record draw commandcd
			offset := cast(vk.DeviceSize) attribute_array_offset;

			secondary_command_buffer: vk.CommandBuffer;
			switch record.geometry.pipeline {
				case .Line:
					secondary_command_buffer = line_secondary_command_buffer;
				case .Basic:
					secondary_command_buffer = basic_secondary_command_buffer;
				case .Lambert:
					secondary_command_buffer = lambert_secondary_command_buffer;
			}

			vk.CmdBindIndexBuffer(secondary_command_buffer, per_instance_buffer, cast(vk.DeviceSize) index_array_offset, .UINT16);
			vk.CmdBindVertexBuffers(secondary_command_buffer, 0, 1, &per_instance_buffer, &offset);
			vk.CmdDrawIndexed(secondary_command_buffer, cast(u32) len(record.geometry.indices), instance_count, 0, 0, first_instance);

			first_instance += instance_count;
		}
	}

	{ // Reset particle running variables
		particle_resources.instance_offset = particle_resources.per_instance_buffer_instance_block_offset;
		particle_resources.first_instance = 0;
	}

	{ // Copy text data and record draw commands
		push_constants: [TEXT_PUSH_CONSTANTS_SIZE]u8;
		half_screen_size_x := f32(extent.width) / 2;
		half_screen_size_y := f32(extent.height) / 2;
		mem.copy_non_overlapping(&push_constants[0], cast(rawptr) &half_screen_size_x, 4);
		mem.copy_non_overlapping(&push_constants[4], cast(rawptr) &half_screen_size_y, 4);

		for text in texts {
			index_array_size := size_of(u16) * len(text.indices);
			attribute_array_size := size_of(f32) * len(text.attributes);

			index_array_offset := geometry_offset;
			attribute_array_offset := math2.align_forward(index_array_offset + index_array_size, 4);
			geometry_offset = attribute_array_offset + attribute_array_size;
			
			when ODIN_DEBUG do assert(geometry_offset <= instance_offset);

			// Copy text data
			mem.copy_non_overlapping(&push_constants[8], cast(rawptr) &text.position_x, 4);
			mem.copy_non_overlapping(&push_constants[12], cast(rawptr) &text.position_y, 4);

			mem.copy_non_overlapping(mem.ptr_offset(per_instance_buffer_ptr, index_array_offset), raw_data(text.indices), index_array_size);
			mem.copy_non_overlapping(mem.ptr_offset(per_instance_buffer_ptr, attribute_array_offset), raw_data(text.attributes), attribute_array_size);

			// Record draw command
			vk.CmdPushConstants(text_secondary_command_buffer, ui_resources.text_pipeline_layout, {.VERTEX}, 0, TEXT_PUSH_CONSTANTS_SIZE, &push_constants[0]);

			offset := cast(vk.DeviceSize) attribute_array_offset;

			vk.CmdBindIndexBuffer(text_secondary_command_buffer, per_instance_buffer, cast(vk.DeviceSize) index_array_offset, .UINT16);
			vk.CmdBindVertexBuffers(text_secondary_command_buffer, 0, 1, &per_instance_buffer, &offset);
			vk.CmdDrawIndexed(text_secondary_command_buffer, cast(u32) len(text.indices), 1, 0, 0, 0);
		}
	}

	return false;
}

end_render_frame :: proc(using vulkan: ^Vulkan) -> bool {
	logical_device := vulkan_context.logical_device;
	primary_command_buffer := primary_command_buffers[logical_frame_index];

	{ // End secondary command buffers
		line_secondary_command_buffer := mesh_resources.line_secondary_command_buffers[logical_frame_index];
		basic_secondary_command_buffer := mesh_resources.basic_secondary_command_buffers[logical_frame_index];
		lambert_secondary_command_buffer := mesh_resources.lambert_secondary_command_buffers[logical_frame_index];
		particle_secondary_command_buffer := particle_resources.secondary_command_buffers[logical_frame_index];
		text_secondary_command_buffer := ui_resources.text_secondary_command_buffer[logical_frame_index];

		r := vk.EndCommandBuffer(line_secondary_command_buffer);
		assert(r == .SUCCESS);
	
		r = vk.EndCommandBuffer(basic_secondary_command_buffer);
		assert(r == .SUCCESS);
	
		r = vk.EndCommandBuffer(lambert_secondary_command_buffer);
		assert(r == .SUCCESS);

		r = vk.EndCommandBuffer(particle_secondary_command_buffer);
		assert(r == .SUCCESS);
	
		r = vk.EndCommandBuffer(text_secondary_command_buffer);
		assert(r == .SUCCESS);
	}

	{ // Flush and unmap per instance buffer
		per_instance_buffer_memory := frame_resources.per_instance_buffers_memory[logical_frame_index];

		range := vk.MappedMemoryRange {
			sType = .MAPPED_MEMORY_RANGE,
			memory = per_instance_buffer_memory,
			offset = 0,
			size = cast(vk.DeviceSize) vk.WHOLE_SIZE,
		};
	
		r := vk.FlushMappedMemoryRanges(logical_device, 1, &range);
		assert(r == .SUCCESS);
	
		vk.UnmapMemory(logical_device, per_instance_buffer_memory);
	}

	{ // Record primary command buffer
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

		clear_values := [2]vk.ClearValue {
			vk.ClearValue {
				color = vk.ClearColorValue {
					float32 = [4]f32 {0.0, 0.0, 0.0, 1.0},
				},
			},
			vk.ClearValue {
				depthStencil = vk.ClearDepthStencilValue {
					depth = 1.0,
					stencil = 0,
				},
			},
		};

		framebuffer := swapchain_frames[image_index].framebuffer;

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

		secondary_command_buffers := [?]vk.CommandBuffer {
			mesh_resources.line_secondary_command_buffers[logical_frame_index],
			mesh_resources.basic_secondary_command_buffers[logical_frame_index],
			mesh_resources.lambert_secondary_command_buffers[logical_frame_index],
			particle_resources.secondary_command_buffers[logical_frame_index],
			ui_resources.text_secondary_command_buffer[logical_frame_index],
		};

		r := vk.BeginCommandBuffer(primary_command_buffers[logical_frame_index], &command_buffer_begin_info);
		assert(r == .SUCCESS);

		vk.CmdBeginRenderPass(primary_command_buffer, &render_pass_begin_info, .SECONDARY_COMMAND_BUFFERS);
		vk.CmdExecuteCommands(primary_command_buffer, cast(u32) len(secondary_command_buffers), &secondary_command_buffers[0]);
		vk.CmdEndRenderPass(primary_command_buffer);

		r = vk.EndCommandBuffer(primary_command_buffer);
		assert(r == .SUCCESS);
	}

	{ // Wait for image to be available then submit primary command buffer
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

		r := vk.QueueSubmit(vulkan_context.graphics_queue, 1, &submit_info, fences[logical_frame_index]);
		assert(r == .SUCCESS);
	}

	{ // Wait for render to finish then present swapchain image
		present_info := vk.PresentInfoKHR {
			sType = .PRESENT_INFO_KHR,
			pWaitSemaphores = &render_finished_semaphores[logical_frame_index],
			waitSemaphoreCount = 1,
			pSwapchains = &swapchain,
			swapchainCount = 1,
			pImageIndices = &image_index,
		};

		r := vk.QueuePresentKHR(vulkan_context.present_queue, &present_info);
		
		suboptimal := false;
		if r == .ERROR_OUT_OF_DATE_KHR || r == .SUBOPTIMAL_KHR {
			suboptimal = true;
		} else if r != .SUCCESS {
			panic("Failed to present swapchain image");
		}

		logical_frame_index = (logical_frame_index + 1) % IFFC;
		
		return suboptimal;
	}
}

draw_particle :: proc(using vulkan: ^Vulkan, particle: ^Particle) {
	mem.copy_non_overlapping(mem.ptr_offset(frame_resources.per_instance_buffer_ptr, particle_resources.instance_offset), particle, size_of(Particle));
	particle_resources.instance_offset += PARTICLE_INSTANCE_ELEMENT_SIZE;

	particle_secondary_command_buffer := particle_resources.secondary_command_buffers[logical_frame_index];
	vk.CmdDraw(particle_secondary_command_buffer, 6, 1, 0, particle_resources.first_instance);
	particle_resources.first_instance += 1;
}