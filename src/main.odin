package main;

import "core:fmt";
import "core:c";
import "core:time";
import "vendor:glfw";
import "vk2";

when ODIN_DEBUG {
	import "core:mem";
}

MAX_FRAME_DURATION := time.Duration(33333333); // 1 / 30 seconds
MAX_UPDATES := 5;

WindowState :: struct {
	framebuffer_size_change: bool,
	minimized: bool,
}

Game :: struct {
	camera: Camera,
	entities: Entities,
	ground_grid: Ground_Grid,
	collision_hull_grid: Collision_Hull_Grid,
	awake_rigid_body_lookups: [dynamic]Entity_Lookup,
	islands: Islands,
	constraints: Constraints,
}

main :: proc() {
	when ODIN_DEBUG {
		track: mem.Tracking_Allocator;
		mem.tracking_allocator_init(&track, context.allocator);
		context.allocator = mem.tracking_allocator(&track);
	}

	assert(glfw.Init() == 1,"Failed to initialize GLFW" );

	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API);
	glfw.WindowHint(glfw.MAXIMIZED, 1);
	window := glfw.CreateWindow(1080, 720, "Kart Guys", nil, nil);
	assert(window != nil, "Failed to create window");

	window_state: WindowState;
	glfw.SetWindowUserPointer(window, &window_state);

	glfw.SetFramebufferSizeCallback(window, framebuffer_size_callback);
	glfw.SetWindowIconifyCallback(window, iconify_callback);
	glfw.SetWindowContentScaleCallback(window, content_scale_callback);
	glfw.SetKeyCallback(window, key_callback);
	glfw.SetInputMode(window, glfw.CURSOR, glfw.CURSOR_DISABLED);

	content_scale_x, content_scale_y := glfw.GetWindowContentScale(window);
	// font := init_font("roboto", 20, content_scale_x);
	vulkan := vk2.init_vulkan(window);

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

	vk2.cleanup_vulkan(&vulkan);
	glfw.DestroyWindow(window);
	glfw.Terminate();

	when ODIN_DEBUG {
		// for _, leak in track.allocation_map {
		// 	fmt.printf("%v leaked %v bytes\n", leak.location, leak.size);
		// }

		// for bad_free in track.bad_free_array {
		// 	fmt.printf("%v allocation %p was freed badly\n", bad_free.location, bad_free.memory);
		// }
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
	};

	load_level(&game);

	return game;
}

update_game :: proc(window: glfw.WindowHandle, game: ^Game, dt: f32) {
	simulate(game, dt);
	move_camera(&game.camera, window, dt);

	collision_hull_grid_update_hull_helpers(&game.collision_hull_grid, &game.entities);

	free_all(context.temp_allocator);
}