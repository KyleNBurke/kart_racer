package main;

import "core:time";
import "core:fmt";
import "vendor:glfw";

when ODIN_DEBUG {
	import "core:mem";
}

MAX_FRAME_DURATION := time.Duration(33333333); // 1 / 30 seconds
MAX_UPDATES := 5;

Game :: struct {
	window: glfw.WindowHandle,
	vulkan: Vulkan,
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
	on_fire_oil_slick_lookups: [dynamic]Entity_Lookup,
	bumper_lookups: [dynamic]Entity_Lookup,
	boost_jet_lookups: [dynamic]Entity_Lookup,
}

main :: proc() {
	when ODIN_DEBUG {
		track: mem.Tracking_Allocator;
		mem.tracking_allocator_init(&track, context.allocator);
		context.allocator = mem.tracking_allocator(&track);
	}

	game: Game;

	init(&game);
	run(&game);
	cleanup(&game);

	when ODIN_DEBUG {
		debug_cleanup(&game);

		for _, leak in track.allocation_map {
			fmt.printf("%v leaked %v bytes\n", leak.location, leak.size);
		}

		for bad_free in track.bad_free_array {
			fmt.printf("%v allocation %p was freed badly\n", bad_free.location, bad_free.memory);
		}
	}
}

init :: proc(game: ^Game) {
	load_config();

	init_window(&game.window);
	init_vulkan(&game.vulkan, game.window);
	init_entities_geos();
	
	camera_aspect := f32(game.vulkan.extent.width) / f32(game.vulkan.extent.height);
	game.camera = init_camera(camera_aspect, 75.0, game.window);

	content_scale_x, _ := glfw.GetWindowContentScale(game.window);
	game.font = init_font("roboto", 20, content_scale_x);
	submit_font(&game.vulkan, &game.font);

	game.frame_metrics = init_frame_metrics(&game.font, &game.texts);

	spawn_position, spawn_orientation := load_level(game);
	load_car(game, spawn_position, spawn_orientation);
	load_runtime_assets(&game.runtime_assets);

	init_hull_helpers(&game.hull_helpers);
	game.car_helpers = init_car_helpers();

	init_shock_particles(game.shock_entities[:]);
	init_fire_particles(game.fire_entities[:]);
	init_boost_jet_particles(game.boost_jet_lookups[:]);

	free_all(context.temp_allocator);
}

run :: proc(game: ^Game) {
	callback_state := Callback_State {
		game = game,
	};

	glfw.SetWindowUserPointer(game.window, &callback_state);

	frame_start := time.now();
	suboptimal_swapchain := false;

	for !glfw.WindowShouldClose(game.window) {
		glfw.PollEvents();

		if callback_state.minimized {
			glfw.WaitEvents();
			continue;
		}

		if callback_state.config_changed {
			save_config();
			callback_state.config_changed = false;
		}

		if callback_state.framebuffer_size_change || suboptimal_swapchain {
			callback_state.framebuffer_size_change = false;

			width_i32, height_i32 := glfw.GetFramebufferSize(game.window);
			width := u32(width_i32);
			height := u32(height_i32);

			vulkan_extent := game.vulkan.extent;

			if width != vulkan_extent.width || height != vulkan_extent.height {
				recreate_swapchain(&game.vulkan, width, height);
				update_aspect_ratio(&game.camera, f32(vulkan_extent.width) / f32(vulkan_extent.height));
			}
		}

		frame_end := time.now();
		frame_duration := time.diff(frame_start, frame_end);
		frame_start = frame_end;
		updates := 0;

		for frame_duration > 0 && updates < MAX_UPDATES {
			frame_duration_capped := min(frame_duration, MAX_FRAME_DURATION);
			frame_duration_capped_secs := cast(f32) time.duration_seconds(frame_duration_capped)

			update(game, frame_duration_capped_secs);

			frame_duration -= frame_duration_capped;
			updates += 1;
		}

		suboptimal_swapchain = begin_render_frame(&game.vulkan, &game.camera, &game.texts);

		if !suboptimal_swapchain {
			immediate_mode_render_game(game);
			suboptimal_swapchain = end_render_frame(&game.vulkan);
		}
	}
}

update :: proc(game: ^Game, dt: f32) {
	if game.camera.state != .First_Person {
		move_car(game.window, game.car, dt, &game.car_helpers);
	}
	
	simulate(game, dt);
	position_and_orient_wheels(game.car, dt);
	move_camera(&game.camera, game.window, game.car, dt);
	update_frame_metrics(&game.frame_metrics, &game.font, game.texts[:], dt);

	update_shock_entity_particles(game.shock_entities[:], dt);
	update_fire_entity_particles(game.fire_entities[:], dt);
	update_status_effect_cloud_particles(game.status_effect_cloud_lookups[:], dt);
	update_car_status_effects_and_particles(game.car, game.camera.transform, dt);
	update_on_fire_oil_slicks(game.on_fire_oil_slick_lookups[:], dt);
	animate_bumpers(game.bumper_lookups[:], dt);
	update_boost_jet_particles(game.boost_jet_lookups[:], dt);

	if config.hull_helpers {
		update_entity_hull_helpers(&game.hull_helpers);
	}

	free_all(context.temp_allocator);
}

immediate_mode_render_game :: proc(using game: ^Game) {
	draw_shock_entity_particles(&vulkan, shock_entities[:]);
	draw_fire_entity_particles(&vulkan, fire_entities[:]);
	draw_car_status_effects(&vulkan, car);
	draw_status_effect_clouds(&vulkan, status_effect_cloud_lookups[:]);
	draw_on_fire_oil_slicks(&vulkan, on_fire_oil_slick_lookups[:]);
	draw_boost_jet_particles(&vulkan, boost_jet_lookups[:]);
}

cleanup :: proc(game: ^Game) {
	cleanup_vulkan(&game.vulkan);
	glfw.DestroyWindow(game.window);
	glfw.Terminate();
}

debug_cleanup :: proc(using game: ^Game) {
	cleanup_font(&font);
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

	delete(game.on_fire_oil_slick_lookups);
	delete(game.oil_slick_lookups);
	delete(game.status_effect_cloud_lookups);
	delete(game.shock_entities);
	delete(game.fire_entities);
	delete(game.texts);
	delete(game.awake_rigid_body_lookups);
	delete(game.contact_helpers);
	delete(game.bumper_lookups);
	delete(game.boost_jet_lookups);

	cleanup_config();
}