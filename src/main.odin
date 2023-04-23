package main;

import "core:fmt";
import "core:c";
import "core:time";
import "core:runtime";
import "core:math/linalg";
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
	font: Font,
	texts: [dynamic]Text,
	ground_grid: Ground_Grid,
	entity_grid: Entity_Grid,
	awake_rigid_body_lookups: [dynamic]Entity_Lookup,
	islands: Islands,
	constraints: Constraints,
	hull_helpers: Hull_Helpers,
	contact_helpers: [dynamic]Geometry_Lookup,
	car: ^Car_Entity,
	car_helpers: Car_Helpers,
	runtime_assets: Runtime_Assets,
	frame_metrics: Frame_Metrics,
	shock_entities: [dynamic]Entity_Lookup,
	fire_entities: [dynamic]Entity_Lookup,

	// Let's keep in mind, we could have the entity manager keep track of entities by variant which would eliminate the need for this.
	// We'll stick with this for now and change it if more situations like this arise.
	status_effect_cloud_lookups: [dynamic]Entity_Lookup,

	oil_slick_lookups: [dynamic]Entity_Lookup,
}

main :: proc() {
	when ODIN_DEBUG {
		track: mem.Tracking_Allocator;
		mem.tracking_allocator_init(&track, context.allocator);
		context.allocator = mem.tracking_allocator(&track);
	}

	load_config();

	assert(glfw.Init() == 1);

	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API);
	glfw.WindowHint(glfw.MAXIMIZED, 1);
	window := glfw.CreateWindow(1280, 720, "Kart Guys", nil, nil);
	assert(window != nil);

	glfw.SetFramebufferSizeCallback(window, framebuffer_size_callback);
	glfw.SetWindowIconifyCallback(window, iconify_callback);
	glfw.SetWindowContentScaleCallback(window, content_scale_callback);
	glfw.SetKeyCallback(window, key_callback);

	vulkan := init_vulkan(window);
	init_entities_geos();
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

		suboptimal_swapchain = begin_render_frame(&vulkan, &game.camera, &game.texts);

		if !suboptimal_swapchain {
			immediate_mode_render_game(&vulkan, &game);
			suboptimal_swapchain = end_render_frame(&vulkan);
		}
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
	game: Game;

	camera_aspect := f32(vulkan.extent.width) / f32(vulkan.extent.height);
	game.camera = init_camera(camera_aspect, 75.0, window);

	content_scale_x, _ := glfw.GetWindowContentScale(window);
	game.font = init_font("roboto", 20, content_scale_x);
	submit_font(vulkan, &game.font);

	game.frame_metrics = init_frame_metrics(&game.font, &game.texts);

	spawn_position, spawn_orientation := load_level(&game);
	load_car(&game, spawn_position, spawn_orientation);
	load_runtime_assets(&game.runtime_assets);

	init_hull_helpers(&game.hull_helpers);
	game.car_helpers = init_car_helpers();

	init_shock_particles(game.shock_entities[:]);
	init_fire_particles(game.fire_entities[:]);

	return game;
}

update_game :: proc(window: glfw.WindowHandle, game: ^Game, dt: f32) {
	if game.camera.state != .First_Person {
		move_car(window, game.car, dt, &game.car_helpers);
	}
	
	simulate(game, dt);
	position_and_orient_wheels(game.car, dt);
	move_camera(&game.camera, window, game.car, dt);
	update_frame_metrics(&game.frame_metrics, &game.font, game.texts[:], dt);

	update_shock_entity_particles(game.shock_entities[:], dt);
	update_fire_entity_particles(game.fire_entities[:], dt);
	update_status_effect_cloud_particles(game.status_effect_cloud_lookups[:], dt);
	update_car_status_effects_and_particles(game.car, game.camera.transform, dt);

	if config.hull_helpers {
		update_entity_hull_helpers(&game.hull_helpers);
	}

	free_all(context.temp_allocator);
}

immediate_mode_render_game :: proc(vulkan: ^Vulkan, game: ^Game) {
	draw_shock_entity_particles(vulkan, game.shock_entities[:]);
	draw_fire_entity_particles(vulkan, game.fire_entities[:]);
	draw_car_status_effects(vulkan, game.car);
	draw_status_effect_clouds(vulkan, game.status_effect_cloud_lookups[:]);
}

cleanup_game :: proc(game: ^Game) {
	cleanup_status_effect_clouds(game.status_effect_cloud_lookups[:]);
	cleanup_shock_entity_particles(game.shock_entities[:]);
	cleanup_fire_entity_particles(game.fire_entities[:]);
	cleanup_car(game.car);
	cleanup_font(&game.font);
	ground_grid_cleanup(&game.ground_grid);
	cleanup_entity_grid(&game.entity_grid);
	cleanup_hull_helpers(&game.hull_helpers);
	cleanup_constraints(&game.constraints);
	cleanup_islands(&game.islands);
	cleanup_runtime_assets(&game.runtime_assets);

	for text in &game.texts {
		cleanup_text(&text);
	}
	
	cleanup_entities_geos();

	delete(game.oil_slick_lookups);
	delete(game.status_effect_cloud_lookups);
	delete(game.shock_entities);
	delete(game.fire_entities);
	delete(game.texts);
	delete(game.awake_rigid_body_lookups);
	delete(game.contact_helpers);
}