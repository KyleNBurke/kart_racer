package main;

import "core:fmt";
import "core:c";
import "core:time";
import "core:runtime";
import "core:math/linalg";
import "vendor:glfw";
import "vk2";
import "entity";

MAX_FRAME_DURATION := time.Duration(1e9 / 30e9); // 1 / 30 seconds
MAX_UPDATES := 5;

WindowState :: struct {
	framebuffer_size_change: bool,
	minimized: bool,
}

main :: proc() {
	fmt.assertf(glfw.Init() == 1, "Failed to initialize GLFW");
	defer glfw.Terminate();

	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API);
	window := glfw.CreateWindow(1080, 720, "Kart Guys", nil, nil);
	fmt.assertf(window != nil, "Failed to create window");
	defer glfw.DestroyWindow(window);

	window_state: WindowState;
	glfw.SetWindowUserPointer(window, &window_state);

	glfw.SetFramebufferSizeCallback(window, framebuffer_size_callback);
	glfw.SetWindowIconifyCallback(window, iconify_callback);
	glfw.SetWindowContentScaleCallback(window, content_scale_callback);
	glfw.SetKeyCallback(window, key_callback);

	content_scale_x, content_scale_y := glfw.GetWindowContentScale(window);
	// font := init_font("roboto", 20, content_scale_x);
	vulkan := vk2.init_vulkan(window);
	defer vk2.cleanup_vulkan(&vulkan);

	framebuffer_width, framebuffer_height := glfw.GetFramebufferSize(window);
	camera := init_camera(f32(framebuffer_width) / f32(framebuffer_height), 75.0);
	entities := entity.init_entites();
	init_scene(&entities, &camera);

	frame_start := time.now();
	suboptimal_swapchain := false;

	for !glfw.WindowShouldClose(window) {
		glfw.PollEvents();

		if window_state.minimized {
			glfw.WaitEvents();
			continue;
		}

		if window_state.framebuffer_size_change || suboptimal_swapchain {
			window_state.framebuffer_size_change = false;
			width, height := glfw.GetFramebufferSize(window);
			vk2.recreate_swapchain();
		}

		frame_end := time.now();
		frame_duration := time.diff(frame_start, frame_end);
		frame_start = frame_end;
		updates := 0;

		for frame_duration > 0 && updates < MAX_UPDATES {
			frame_duration_capped := min(frame_duration, MAX_FRAME_DURATION);
			frame_duration_capped_secs := cast(f32) time.duration_seconds(frame_duration_capped)

			update_game(frame_duration_capped_secs);

			frame_duration -= frame_duration_capped;
			updates += 1;
		}

		suboptimal_swapchain = render(&vulkan, &camera, &entities);
	}
}

framebuffer_size_callback : glfw.FramebufferSizeProc : proc "c" (window: glfw.WindowHandle, width, height: c.int) {
	window_state := cast(^WindowState) glfw.GetWindowUserPointer(window);
	window_state.framebuffer_size_change = true;
}

iconify_callback : glfw.WindowIconifyProc : proc "c" (window: glfw.WindowHandle, iconified: c.int) {
	window_state := cast(^WindowState) glfw.GetWindowUserPointer(window);
	window_state.minimized = iconified == 1 ? true : false;
}

content_scale_callback : glfw.WindowContentScaleProc : proc "c" (window: glfw.WindowHandle, xscale, yscale: f32) {
	
}

key_callback : glfw.KeyProc : proc "c" (window: glfw.WindowHandle, key, scancode, action, mods: c.int) {
	switch key {
		case glfw.KEY_ESCAPE:
			glfw.SetWindowShouldClose(window, true);
	}
}

init_scene :: proc(entities: ^entity.Entities, camera: ^Camera) {
	geometry := entity.init_box();
	geometry_record := entity.add_geometry(entities, geometry);

	e := entity.init_entity(position = linalg.Vector3f32{0.0, 0.0, 5.0});
	entity.add_entity(entities, geometry_record, e);
}

update_game :: proc(dt: f32) {
	
}