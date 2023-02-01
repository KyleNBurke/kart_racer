package main;

import "core:fmt";
import "core:c";
import "core:time";
import "core:runtime";
import "vendor:glfw";

when ODIN_DEBUG {
	import "core:mem";
}

MAX_FRAME_DURATION := time.Duration(33333333); // 1 / 30 seconds
MAX_UPDATES := 5;

Callback_State :: struct {
	framebuffer_size_change: bool,
	minimized: bool,
	game: ^Game,
}

Game :: struct {
	camera: Camera,
	entities_geos: Entities_Geos,
	font: Font,
	texts: [dynamic]Text,
	ground_grid: Ground_Grid,
	collision_hull_grid: Collision_Hull_Grid,
	awake_rigid_body_lookups: [dynamic]Entity_Lookup,
	islands: Islands,
	constraints: Constraints,
	car: ^Car_Entity,
	car_helpers: Car_Helpers,
	frame_metrics: Frame_Metrics,
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

	glfw.SetFramebufferSizeCallback(window, framebuffer_size_callback);
	glfw.SetWindowIconifyCallback(window, iconify_callback);
	glfw.SetWindowContentScaleCallback(window, content_scale_callback);
	glfw.SetKeyCallback(window, key_callback);

	vulkan := init_vulkan(window);
	game := init_game(&vulkan, window);

	free_all(context.temp_allocator);

	callback_state := Callback_State {
		game = &game,
	};

	glfw.SetWindowUserPointer(window, &callback_state);

	frame_start := time.now();
	suboptimal_swapchain := false;

	for !glfw.WindowShouldClose(window) {
		glfw.PollEvents();

		if callback_state.minimized {
			glfw.WaitEvents();
			continue;
		}

		if callback_state.framebuffer_size_change || suboptimal_swapchain {
			callback_state.framebuffer_size_change = false;

			width_i32, height_i32 := glfw.GetFramebufferSize(window);
			width := u32(width_i32);
			height := u32(height_i32);

			if width != vulkan.extent.width || height != vulkan.extent.height {
				recreate_swapchain(&vulkan, width, height);
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

		suboptimal_swapchain = render(&vulkan, &game.camera, &game.entities_geos, &game.texts);
	}

	cleanup_vulkan(&vulkan);
	glfw.DestroyWindow(window);
	glfw.Terminate();

	when ODIN_DEBUG {
		cleanup_game(&game);

		for _, leak in track.allocation_map {
			fmt.printf("%v leaked %v bytes\n", leak.location, leak.size);
		}

		for bad_free in track.bad_free_array {
			fmt.printf("%v allocation %p was freed badly\n", bad_free.location, bad_free.memory);
		}
	}
}

framebuffer_size_callback : glfw.FramebufferSizeProc : proc "c" (window: glfw.WindowHandle, width, height: c.int) {
	callback_state := cast(^Callback_State) glfw.GetWindowUserPointer(window);
	callback_state.framebuffer_size_change = true;
}

iconify_callback : glfw.WindowIconifyProc : proc "c" (window: glfw.WindowHandle, iconified: c.int) {
	callback_state := cast(^Callback_State) glfw.GetWindowUserPointer(window);
	callback_state.minimized = iconified == 1 ? true : false;
}

content_scale_callback : glfw.WindowContentScaleProc : proc "c" (window: glfw.WindowHandle, xscale, yscale: f32) {
	
}

key_callback : glfw.KeyProc : proc "c" (window: glfw.WindowHandle, key, scancode, action, mods: c.int) {
	context = runtime.default_context()
	callback_state := cast(^Callback_State) glfw.GetWindowUserPointer(window);

	if action == glfw.PRESS {
		switch key {
			case glfw.KEY_ESCAPE:
				glfw.SetWindowShouldClose(window, true);
		}

		camera_handle_key_press(&callback_state.game.camera, key, window);
	}
}

init_game :: proc(vulkan: ^Vulkan, window: glfw.WindowHandle) -> Game {
	camera_aspect := f32(vulkan.extent.width) / f32(vulkan.extent.height);

	game := Game {
		camera = init_camera(camera_aspect, 75.0, window),
	};

	content_scale_x, _ := glfw.GetWindowContentScale(window);
	game.font = init_font("roboto", 20, content_scale_x);
	submit_font(vulkan, &game.font);

	game.frame_metrics = init_frame_metrics(&game.font, &game.texts);

	spawn_position, spawn_orientation := load_level(&game);
	load_car(&game, spawn_position, spawn_orientation);
	game.car_helpers = init_car_helpers(&game.entities_geos);

	return game;
}

update_game :: proc(window: glfw.WindowHandle, game: ^Game, dt: f32) {
	move_car(window, game.car, dt, &game.entities_geos, &game.car_helpers);
	simulate(game, dt);
	position_and_orient_wheels(game.car, &game.entities_geos, dt);
	move_camera(&game.camera, window, game.car, dt);

	update_frame_metrics(&game.frame_metrics, &game.font, game.texts[:], dt);

	collision_hull_grid_update_hull_helpers(&game.collision_hull_grid, &game.entities_geos);

	free_all(context.temp_allocator);
}

cleanup_game :: proc(game: ^Game) {
	cleanup_entities_geos(&game.entities_geos);
	cleanup_font(&game.font);
	ground_grid_cleanup(&game.ground_grid);
	collision_hull_grid_cleanup(&game.collision_hull_grid);
	cleanup_constraints(&game.constraints);
	cleanup_islands(&game.islands);

	for text in &game.texts {
		cleanup_text(&text);
	}

	delete(game.texts);
	delete(game.awake_rigid_body_lookups);
}