package main;

import "core:fmt";
import "core:c";
import "core:time";
import "core:runtime";
import "core:math/linalg";
import "vendor:glfw";
import "vk2";
import "entity";
import "physics";

MAX_FRAME_DURATION := time.Duration(33333333); // 1 / 30 seconds
MAX_UPDATES := 5;

WindowState :: struct {
	framebuffer_size_change: bool,
	minimized: bool,
}

Game :: struct {
	camera: Camera,
	entities: entity.Entities,
	ground_grid: physics.GroundGrid,
	collision_hull_grid: physics.CollisionHullGrid,
	awake_rigid_body_entity_indices: [dynamic]u32,
	islands: physics.Islands,
}

main :: proc() {
	fmt.assertf(glfw.Init() == 1, "Failed to initialize GLFW");
	defer glfw.Terminate();

	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API);
	glfw.WindowHint(glfw.MAXIMIZED, 1);
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

	camera_aspect := f32(vulkan.extent.width) / f32(vulkan.extent.height);
	game := init_game(camera_aspect, window);

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

			width_i32, height_i32 := glfw.GetFramebufferSize(window);
			width := u32(width_i32);
			height := u32(height_i32);

			if width != vulkan.extent.width || height != vulkan.extent.height {
				vk2.recreate_swapchain(&vulkan, width, height);
				update_aspect_ratio(&game.camera, f32(vulkan.extent.width) / f32(vulkan.extent.height));
			}
		}

		frame_end := time.now();
		frame_duration := time.diff(frame_start, frame_end);
		frame_start = frame_end;
		updates := 0;

		for frame_duration > 0 && updates < MAX_UPDATES {
			frame_duration_capped := min(frame_duration, MAX_FRAME_DURATION);
			frame_duration_capped_secs := cast(f32) time.duration_seconds(frame_duration_capped)

			update_game(window, &game, frame_duration_capped_secs);

			frame_duration -= frame_duration_capped;
			updates += 1;
		}

		suboptimal_swapchain = render(&vulkan, &game.camera, &game.entities);
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

init_game :: proc(camera_aspect: f32, window: glfw.WindowHandle) -> Game {
	game := Game {
		camera = init_camera(camera_aspect, 75.0, window),
		entities = entity.init_entites(),
	};

	load_level(&game);

	return game;
}

update_game :: proc(window: glfw.WindowHandle, game: ^Game, dt: f32) {
	move_camera(&game.camera, window, dt);
}