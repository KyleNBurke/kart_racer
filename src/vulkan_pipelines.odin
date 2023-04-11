package main;

import "core:fmt";
import "core:os";
import "core:strings";
import "core:c/libc";
import vk "vendor:vulkan";

create_pipelines :: proc(
	logical_device: vk.Device,
	render_pass: vk.RenderPass,
	extent: vk.Extent2D,
	mesh_pipeline_layout,
	particle_pipeline_layout,
	text_pipeline_layout: vk.PipelineLayout,
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

	line_input_attribute_descriptions := [?]vk.VertexInputAttributeDescription {
		vk.VertexInputAttributeDescription { // Position
			binding = 0,
			location = 0,
			format = .R32G32B32_SFLOAT,
			offset = 0,
		},
		vk.VertexInputAttributeDescription { // Color
			binding = 0,
			location = 1,
			format = .R32G32B32_SFLOAT,
			offset = 12,
		},
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

	// Triangle
	triangle_input_assembly_state_create_info := vk.PipelineInputAssemblyStateCreateInfo {
		sType = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
		topology = .TRIANGLE_LIST,
		primitiveRestartEnable = false,
	};

	triangle_rasterization_state_create_info := vk.PipelineRasterizationStateCreateInfo {
		sType = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
		depthClampEnable = false,
		rasterizerDiscardEnable = false,
		polygonMode = .FILL,
		lineWidth = 1.0,
		cullMode = {.BACK},
		frontFace = .COUNTER_CLOCKWISE,
		depthBiasEnable = false,
	};

	// Basic
	basic_input_binding_description := vk.VertexInputBindingDescription {
		binding = 0,
		stride = 36,
		inputRate = .VERTEX,
	};

	basic_input_attribute_descriptions := [?]vk.VertexInputAttributeDescription {
		vk.VertexInputAttributeDescription { // Position
			binding = 0,
			location = 0,
			format = .R32G32B32_SFLOAT,
			offset = 0,
		},
		vk.VertexInputAttributeDescription { // Color
			binding = 0,
			location = 1,
			format = .R32G32B32_SFLOAT,
			offset = 24,
		},
	};

	basic_vertex_input_state_create_info := vk.PipelineVertexInputStateCreateInfo {
		sType = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
		pVertexBindingDescriptions = &basic_input_binding_description,
		vertexBindingDescriptionCount = 1,
		pVertexAttributeDescriptions = &basic_input_attribute_descriptions[0],
		vertexAttributeDescriptionCount = len(basic_input_attribute_descriptions),
	};

	basic_pipeline_create_info := vk.GraphicsPipelineCreateInfo {
		sType = .GRAPHICS_PIPELINE_CREATE_INFO,
		pStages = &basic_stage_create_infos[0],
		stageCount = len(basic_stage_create_infos),
		pVertexInputState = &basic_vertex_input_state_create_info,
		pInputAssemblyState = &triangle_input_assembly_state_create_info,
		pViewportState = &viewport_state_create_info,
		pRasterizationState = &triangle_rasterization_state_create_info,
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

	lambert_input_binding_description := vk.VertexInputBindingDescription {
		binding = 0,
		stride = 36,
		inputRate = .VERTEX,
	};

	lambert_input_attribute_descriptions := [?]vk.VertexInputAttributeDescription {
		vk.VertexInputAttributeDescription { // Position
			binding = 0,
			location = 0,
			format = .R32G32B32_SFLOAT,
			offset = 0,
		},
		vk.VertexInputAttributeDescription { // Normal
			binding = 0,
			location = 1,
			format = .R32G32B32_SFLOAT,
			offset = 12,
		},
		vk.VertexInputAttributeDescription { // Color
			binding = 0,
			location = 2,
			format = .R32G32B32_SFLOAT,
			offset = 24,
		},
	};

	lambert_vertex_input_state_create_info := vk.PipelineVertexInputStateCreateInfo {
		sType = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
		pVertexBindingDescriptions = &lambert_input_binding_description,
		vertexBindingDescriptionCount = 1,
		pVertexAttributeDescriptions = &lambert_input_attribute_descriptions[0],
		vertexAttributeDescriptionCount = len(lambert_input_attribute_descriptions),
	};

	lambert_pipeline_create_info := vk.GraphicsPipelineCreateInfo {
		sType = .GRAPHICS_PIPELINE_CREATE_INFO,
		pStages = &lambert_stage_create_infos[0],
		stageCount = len(lambert_stage_create_infos),
		pVertexInputState = &lambert_vertex_input_state_create_info,
		pInputAssemblyState = &triangle_input_assembly_state_create_info,
		pViewportState = &viewport_state_create_info,
		pRasterizationState = &triangle_rasterization_state_create_info,
		pMultisampleState = &multisample_state_create_info,
		pDepthStencilState = &depth_stencil_state_create_info,
		pColorBlendState = &color_blend_state_create_info,
		layout = mesh_pipeline_layout,
		renderPass = render_pass,
		subpass = 0,
	};

	// Lambert two sided
	lambert_two_sided_rasterization_state_create_info := vk.PipelineRasterizationStateCreateInfo {
		sType = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
		depthClampEnable = false,
		rasterizerDiscardEnable = false,
		polygonMode = .FILL,
		lineWidth = 1.0,
		cullMode = {},
		frontFace = .COUNTER_CLOCKWISE,
		depthBiasEnable = false,
	};

	lambert_two_sided_pipeline_create_info := vk.GraphicsPipelineCreateInfo {
		sType = .GRAPHICS_PIPELINE_CREATE_INFO,
		pStages = &lambert_stage_create_infos[0],
		stageCount = len(lambert_stage_create_infos),
		pVertexInputState = &lambert_vertex_input_state_create_info,
		pInputAssemblyState = &triangle_input_assembly_state_create_info,
		pViewportState = &viewport_state_create_info,
		pRasterizationState = &lambert_two_sided_rasterization_state_create_info,
		pMultisampleState = &multisample_state_create_info,
		pDepthStencilState = &depth_stencil_state_create_info,
		pColorBlendState = &color_blend_state_create_info,
		layout = mesh_pipeline_layout,
		renderPass = render_pass,
		subpass = 0,
	};

	// Particle
	particle_vert_module := create_shader_module(logical_device, "particle.vert");
	defer vk.DestroyShaderModule(logical_device, particle_vert_module, nil);
	particle_vert_stage_create_info := vk.PipelineShaderStageCreateInfo {
		sType = .PIPELINE_SHADER_STAGE_CREATE_INFO,
		stage = {.VERTEX},
		module = particle_vert_module,
		pName = shader_entry_point,
	};

	particle_frag_module := create_shader_module(logical_device, "particle.frag");
	defer vk.DestroyShaderModule(logical_device, particle_frag_module, nil);
	particle_frag_stage_create_info := vk.PipelineShaderStageCreateInfo {
		sType = .PIPELINE_SHADER_STAGE_CREATE_INFO,
		stage = {.FRAGMENT},
		module = particle_frag_module,
		pName = shader_entry_point,
	};

	particle_stage_create_infos := [?]vk.PipelineShaderStageCreateInfo {particle_vert_stage_create_info, particle_frag_stage_create_info};

	particle_vertex_input_state_create_info := vk.PipelineVertexInputStateCreateInfo {
		sType = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
	};

	particle_pipeline_create_info := vk.GraphicsPipelineCreateInfo {
		sType = .GRAPHICS_PIPELINE_CREATE_INFO,
		pStages = &particle_stage_create_infos[0],
		stageCount = len(particle_stage_create_infos),
		pVertexInputState = &particle_vertex_input_state_create_info,
		pInputAssemblyState = &triangle_input_assembly_state_create_info,
		pViewportState = &viewport_state_create_info,
		pRasterizationState = &triangle_rasterization_state_create_info,
		pMultisampleState = &multisample_state_create_info,
		pDepthStencilState = &depth_stencil_state_create_info,
		pColorBlendState = &color_blend_state_create_info, // This should change if we want to support transparency
		layout = particle_pipeline_layout,
		renderPass = render_pass,
		subpass = 0,
	};

	// Text
	text_vert_module := create_shader_module(logical_device, "text.vert");
	defer vk.DestroyShaderModule(logical_device, text_vert_module, nil);
	text_vert_stage_create_info := vk.PipelineShaderStageCreateInfo {
		sType = .PIPELINE_SHADER_STAGE_CREATE_INFO,
		stage = {.VERTEX},
		module = text_vert_module,
		pName = shader_entry_point,
	};

	text_frag_module := create_shader_module(logical_device, "text.frag");
	defer vk.DestroyShaderModule(logical_device, text_frag_module, nil);
	text_frag_stage_create_info := vk.PipelineShaderStageCreateInfo {
		sType = .PIPELINE_SHADER_STAGE_CREATE_INFO,
		stage = {.FRAGMENT},
		module = text_frag_module,
		pName = shader_entry_point,
	};

	text_stage_create_infos := [?]vk.PipelineShaderStageCreateInfo {text_vert_stage_create_info, text_frag_stage_create_info};

	text_input_binding_description := vk.VertexInputBindingDescription {
		binding = 0,
		stride = 16,
		inputRate = .VERTEX,
	};

	text_input_attribute_descriptions := [?]vk.VertexInputAttributeDescription {
		vk.VertexInputAttributeDescription { // Position
			binding = 0,
			location = 0,
			format = .R32G32_SFLOAT,
			offset = 0,
		},
		vk.VertexInputAttributeDescription { // Texture position
			binding = 0,
			location = 1,
			format = .R32G32_SFLOAT,
			offset = 8,
		},
	};

	text_vertex_input_state_create_info := vk.PipelineVertexInputStateCreateInfo {
		sType = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
		pVertexBindingDescriptions = &text_input_binding_description,
		vertexBindingDescriptionCount = 1,
		pVertexAttributeDescriptions = &text_input_attribute_descriptions[0],
		vertexAttributeDescriptionCount = len(text_input_attribute_descriptions),
	};

	text_depth_stencil_state_create_info := vk.PipelineDepthStencilStateCreateInfo {
		sType = .PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
		depthTestEnable = false,
		depthWriteEnable = false,
		depthBoundsTestEnable = false,
		stencilTestEnable = false,
	};

	text_color_blend_attachment_state := vk.PipelineColorBlendAttachmentState {
		colorWriteMask = {.R, .G, .B, .A},
		blendEnable = true,
		srcColorBlendFactor = .SRC_ALPHA,
		dstColorBlendFactor = .ONE_MINUS_SRC_ALPHA,
		colorBlendOp = .ADD,
		srcAlphaBlendFactor = .ONE,
		dstAlphaBlendFactor = .ZERO,
		alphaBlendOp = .ADD,
	};

	text_color_blend_state_create_info := vk.PipelineColorBlendStateCreateInfo {
		sType = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
		logicOpEnable = false,
		pAttachments = &text_color_blend_attachment_state,
		attachmentCount = 1,
	};

	text_pipeline_create_info := vk.GraphicsPipelineCreateInfo {
		sType = .GRAPHICS_PIPELINE_CREATE_INFO,
		pStages = &text_stage_create_infos[0],
		stageCount = len(text_stage_create_infos),
		pVertexInputState = &text_vertex_input_state_create_info,
		pInputAssemblyState = &triangle_input_assembly_state_create_info,
		pViewportState = &viewport_state_create_info,
		pRasterizationState = &triangle_rasterization_state_create_info,
		pMultisampleState = &multisample_state_create_info,
		pDepthStencilState = &text_depth_stencil_state_create_info,
		pColorBlendState = &text_color_blend_state_create_info,
		layout = text_pipeline_layout,
		renderPass = render_pass,
		subpass = 0,
	};

	// Create pipelines
	pipeline_create_infos := [PIPELINES_COUNT]vk.GraphicsPipelineCreateInfo {
		line_pipeline_create_info,
		basic_pipeline_create_info,
		lambert_pipeline_create_info,
		lambert_two_sided_pipeline_create_info,
		particle_pipeline_create_info,
		text_pipeline_create_info,
	};

	pipelines: [PIPELINES_COUNT]vk.Pipeline;
	r := vk.CreateGraphicsPipelines(logical_device, {}, len(pipeline_create_infos), &pipeline_create_infos[0], nil, &pipelines[0]);
	assert(r == .SUCCESS);

	return pipelines;
}