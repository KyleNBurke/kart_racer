package main;

import "core:time";
import "core:fmt";
import "core:math/linalg";
import "core:os";
import "core:mem";
import "vendor:glfw";

MAX_FRAME_DURATION := time.Duration(33333333); // 1 / 30 seconds
MAX_UPDATES := 5;

Game :: struct {
	window: glfw.WindowHandle,
	gamepad: Gamepad,
	vulkan: Vulkan,
	camera: Camera,
	font: Font,
	texts: [dynamic]Text,
	runtime_assets: Runtime_Assets,
	frame_metrics: Frame_Metrics,
	single_stepping: bool,
	step: bool,
	scene: Scene,
}

Scene :: struct {
	file_path: string,
	reload_file_path: string,
	load_time: os.File_Time,
	car_loaded_data: Car_Loaded_Data,
	ground_grid: Ground_Grid,
	entity_grid: Entity_Grid,
	awake_rigid_bodies: [dynamic]Entity_Lookup,
	islands: Islands,
	constraints: Constraints,
	hull_helpers: Hull_Helpers,
	contact_helpers: [dynamic]Geometry_Lookup,
	shock_entities: [dynamic]Entity_Lookup,
	fire_entities: [dynamic]Entity_Lookup,
	spawn_position: linalg.Vector3f32,
	spawn_orientation: linalg.Quaternionf32,
	status_effect_clouds: [dynamic]Entity_Lookup,
	oil_slicks: [dynamic]Entity_Lookup,
	on_fire_oil_slicks: [dynamic]Entity_Lookup,
	bumpers: [dynamic]Entity_Lookup,
	boost_jets: [dynamic]Entity_Lookup,
	all_players: [dynamic]Entity_Lookup, // First item is the human player
	player: ^Car_Entity,
	ai: AI,
}

Car_Loaded_Data :: struct {
	car_geometry_lookup: Geometry_Lookup,
	wheel_geometry_lookup: Geometry_Lookup,
	hull_local_position: linalg.Vector3f32,
	hull_local_orientation: linalg.Quaternionf32,
	hull_local_size: linalg.Vector3f32,
	wheel_radius: f32,
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
	
	camera_aspect := f32(game.vulkan.extent.width) / f32(game.vulkan.extent.height);
	game.camera = init_camera(camera_aspect, 75.0, game.window);

	content_scale_x, _ := glfw.GetWindowContentScale(game.window);
	game.font = init_font("roboto", 20, content_scale_x);
	submit_font(&game.vulkan, &game.font);

	game.gamepad.deadzone_radius = 0.25;
	game.frame_metrics = init_frame_metrics(&game.font, &game.texts);

	ground_grid_init(&game.scene.ground_grid);

	load_car_data(&game.scene);
	init_scene(&game.scene);
	load_runtime_assets(&game.runtime_assets);

	ai_init(&game.scene);

	init_hull_helpers(&game.scene.hull_helpers);

	if config.ai_helpers {
		ai_show_path_helpers(&game.scene.ai);
	}

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

		if callback_state.window_config_changed {
			update_config_from_window_change(game.window);
			callback_state.window_config_changed = false;
		}

		if callback_state.framebuffer_size_change || suboptimal_swapchain {
			callback_state.framebuffer_size_change = false;

			width_i32, height_i32 := glfw.GetFramebufferSize(game.window);
			width := u32(width_i32);
			height := u32(height_i32);

			vulkan_extent := game.vulkan.extent;

			if width != vulkan_extent.width || height != vulkan_extent.height {
				recreate_swapchain(&game.vulkan, width, height);

				new_vulkan_extent := game.vulkan.extent;
				update_aspect_ratio(&game.camera, f32(new_vulkan_extent.width) / f32(new_vulkan_extent.height));
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
	update_gamepad_state(&game.gamepad);

	when ODIN_DEBUG {
		hot_reload_scene_if_needed(game);

		if gamepad_button_pressed(&game.gamepad, glfw.GAMEPAD_BUTTON_X) {
			respawn_player(game.scene.player, game.scene.spawn_position, game.scene.spawn_orientation);
		}
	}

	if game.single_stepping {
		if game.step {
			set_player_inputs(&game.gamepad, game.window, game.scene.player);
			move_players(game.scene.all_players[:], dt);
			simulate(&game.scene, &game.runtime_assets, dt);
			// position_and_orient_wheels(game.scene.player, dt);
			ai_signal_update_if_ready(&game.scene.ai, dt);
			game.step = false;
		}
	} else {
		set_player_inputs(&game.gamepad, game.window, game.scene.player);
		move_players(game.scene.all_players[:], dt);
		simulate(&game.scene, &game.runtime_assets, dt);
		// position_and_orient_wheels(game.scene.player, dt);
		ai_signal_update_if_ready(&game.scene.ai, dt);
	}

	// Move camera
	when ODIN_DEBUG {
		if config.camera_follow_first_ai {
			ai_car := get_entity(game.scene.all_players[1]).variant.(^Car_Entity);
			move_camera(&game.camera, &game.gamepad, game.window, ai_car, dt);
		} else {
			move_camera(&game.camera, &game.gamepad, game.window, game.scene.player, dt);
		}
	} else {
		move_camera(&game.camera, &game.gamepad, game.window, game.scene.player, dt);
	}

	update_frame_metrics(&game.frame_metrics, &game.font, game.texts[:], dt);

	scene := &game.scene;
	update_shock_entity_particles(scene.shock_entities[:], dt);
	update_fire_entity_particles(scene.fire_entities[:], dt);
	update_status_effect_cloud_particles(scene.status_effect_clouds[:], dt);
	update_car_status_effects_and_particles(game.scene.player, game.camera.transform, dt);
	update_on_fire_oil_slicks(scene.on_fire_oil_slicks[:], dt);
	animate_bumpers(scene.bumpers[:], dt);
	update_boost_jet_particles(scene.boost_jets[:], dt);

	if config.hull_helpers {
		update_entity_hull_helpers(&scene.hull_helpers);
	}

	if config.ai_helpers {
		ai_show_helpers(game.scene.all_players[1:]);
	}

	free_all(context.temp_allocator);
}

immediate_mode_render_game :: proc(game: ^Game) {
	vulkan := &game.vulkan;
	scene := &game.scene;

	draw_shock_entity_particles(vulkan, scene.shock_entities[:]);
	draw_fire_entity_particles(vulkan, scene.fire_entities[:]);
	draw_car_status_effects(vulkan, game.scene.player);
	draw_status_effect_clouds(vulkan, scene.status_effect_clouds[:]);
	draw_on_fire_oil_slicks(vulkan, scene.on_fire_oil_slicks[:]);
	draw_boost_jet_particles(vulkan, scene.boost_jets[:]);
}

cleanup :: proc(game: ^Game) {
	cleanup_vulkan(&game.vulkan);
	glfw.DestroyWindow(game.window);
	glfw.Terminate();
}

debug_cleanup :: proc(game: ^Game) {
	cleanup_font(&game.font);

	scene := &game.scene;
	ground_grid_cleanup(&scene.ground_grid);
	entity_grid_cleanup(&scene.entity_grid);
	cleanup_hull_helpers(&scene.hull_helpers);
	cleanup_constraints(&scene.constraints);
	cleanup_islands(&scene.islands);
	cleanup_runtime_assets(&game.runtime_assets);
	ai_debug_cleanup(&scene.ai);

	for &text in game.texts {
		cleanup_text(&text);
	}
	
	cleanup_entities_geos();

	// Cleanup scene should do all this and hold all theses variables too.
	delete(scene.all_players);
	delete(scene.on_fire_oil_slicks);
	delete(scene.oil_slicks);
	delete(scene.status_effect_clouds);
	delete(scene.shock_entities);
	delete(scene.fire_entities);
	delete(game.texts);
	delete(scene.awake_rigid_bodies);
	delete(scene.contact_helpers);
	delete(scene.bumpers);
	delete(scene.boost_jets);

	cleanup_scene(&game.scene);

	cleanup_config();
}