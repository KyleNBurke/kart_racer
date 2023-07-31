package main

import "core:os";
import "core:math/linalg";
import "core:fmt";
import "core:strings";
import "core:slice";

POSITION_CHECK_VALUE :: 0b10101010_10101010_10101010_10101010;

read_u32 :: proc(bytes: ^[]byte, pos: ^int) -> u32 {
	v := cast(u32) (cast(^u32le) raw_data(bytes[pos^:]))^;
	pos^ += 4;
	return v;
}

read_bool :: proc(bytes: ^[]byte, pos: ^int) -> bool {
	v := cast(bool) (cast(^b8) raw_data(bytes[pos^:]))^;
	pos^ += 1;
	return v;
}

read_string :: proc(bytes: ^[]byte, pos: ^int) -> string {
	length := cast(int) read_u32(bytes, pos);
	s := strings.clone_from_bytes(bytes[pos^ : pos^ + length], context.temp_allocator);
	pos^ += length;
	return s;
}

read_f32 :: proc(bytes: ^[]byte, pos: ^int) -> f32 {
	v := cast(f32) (cast(^f32le) raw_data(bytes[pos^:]))^;
	pos^ += 4;
	return v;
}

read_vec3 :: proc(bytes: ^[]byte, pos: ^int) -> linalg.Vector3f32 {
	x := cast(f32) (cast(^f32le) raw_data(bytes[pos^:]))^;
	y := cast(f32) (cast(^f32le) raw_data(bytes[pos^ + 4:]))^;
	z := cast(f32) (cast(^f32le) raw_data(bytes[pos^ + 8:]))^;

	pos^ += 12;

	return linalg.Vector3f32 {x, y, z};
}

read_quat :: proc(bytes: ^[]byte, pos: ^int) -> linalg.Quaternionf32 {
	x := cast(f32) (cast(^f32le) raw_data(bytes[pos^:]))^;
	y := cast(f32) (cast(^f32le) raw_data(bytes[pos^ + 4:]))^;
	z := cast(f32) (cast(^f32le) raw_data(bytes[pos^ + 8:]))^;
	w := cast(f32) (cast(^f32le) raw_data(bytes[pos^ + 12:]))^;

	pos^ += 16;

	return cast(linalg.Quaternionf32) quaternion(w, x, y, z);
}

read_indices_attributes :: proc(bytes: ^[]byte, pos: ^int) -> ([dynamic]u16, [dynamic]f32) {
	indices_count := read_u32(bytes, pos);
	indices := make([dynamic]u16, indices_count);

	for i in 0..<indices_count {
		index := cast(u16) (cast(^u16le) raw_data(bytes[pos^:]))^;
		pos^ += 2;
		indices[i] = index;
	}

	attributes_count := read_u32(bytes, pos);
	attributes := make([dynamic]f32, attributes_count);

	for i in 0..<attributes_count {
		attribute := cast(f32) (cast(^f32le) raw_data(bytes[pos^:]))^;
		pos^ += 4;
		attributes[i] = attribute;
	}

	return indices, attributes;
}

load_scene :: proc(scene: ^Scene) {
	{ // Clear things out
		clear(&scene.awake_rigid_bodies);
		clear(&scene.shock_entities);
		clear(&scene.fire_entities);
		clear(&scene.status_effect_clouds);
		clear(&scene.oil_slicks);
		clear(&scene.on_fire_oil_slicks);
		clear(&scene.bumpers);
		clear(&scene.boost_jets);

		remove_scene_associated_entities();
	}

	REQUIRED_VERSION :: 3;
	
	bytes, success := os.read_entire_file_from_filename(scene.file_path, context.temp_allocator);
	assert(success, fmt.tprintf("Failed to load level file %s", scene.file_path));
	
	pos := 0;

	version := read_u32(&bytes, &pos);
	assert(REQUIRED_VERSION == version, fmt.tprintf("[level loading] Required version %v but found %v.", REQUIRED_VERSION, version));

	// Spawn position & orientation
	scene.spawn_position = read_vec3(&bytes, &pos);
	scene.spawn_orientation = read_quat(&bytes, &pos);

	// Reset grids
	grid_half_size := read_f32(&bytes, &pos);
	ground_grid_reset(&scene.ground_grid, grid_half_size);
	entity_grid_reset(&scene.entity_grid, grid_half_size);
	
	{ // Ground grid
		meshes_count := read_u32(&bytes, &pos);

		for _ in 0..<meshes_count {
			indices, positions := read_indices_attributes(&bytes, &pos);
			insert_into_ground_grid(&scene.ground_grid, indices[:], positions[:]);

			delete(indices);
			delete(positions);

			assert(read_u32(&bytes, &pos) == POSITION_CHECK_VALUE);
		}
	}

	// Geometries
	geometries_count := read_u32(&bytes, &pos);
	geometry_lookups := make([dynamic]Geometry_Lookup, 0, geometries_count, context.temp_allocator);

	for i in 0..<geometries_count {
		name := read_string(&bytes, &pos);
		indices, attributes := read_indices_attributes(&bytes, &pos);

		geometry, geometry_lookup := create_geometry(name);
		geometry_make_triangle_mesh(geometry, indices[:], attributes[:], .Lambert);

		delete(indices);
		delete(attributes);

		append(&geometry_lookups, geometry_lookup);

		assert(read_u32(&bytes, &pos) == POSITION_CHECK_VALUE);
	}

	{ // Inanimate entities
		entity_count := read_u32(&bytes, &pos);

		for i in 0..<entity_count {
			name := read_string(&bytes, &pos);
			position := read_vec3(&bytes, &pos);
			orientation := read_quat(&bytes, &pos);
			size := read_vec3(&bytes, &pos);
			geometry_index := read_u32(&bytes, &pos);
			hull_count := read_u32(&bytes, &pos);

			geometry_lookup := geometry_lookups[geometry_index];
			inanimate_entity, entity_lookup := create_entity(name, geometry_lookup, Inanimate_Entity);
			inanimate_entity.scene_associated = true;

			inanimate_entity.position = position;
			inanimate_entity.orientation = orientation;
			inanimate_entity.size = size;
			update_entity_transform(inanimate_entity);

			for hull_index in 0..<hull_count {
				local_position := read_vec3(&bytes, &pos);
				local_orientation := read_quat(&bytes, &pos);
				local_size := read_vec3(&bytes, &pos);
				kind := cast(Hull_Kind) read_u32(&bytes, &pos);

				local_transform := linalg.matrix4_from_trs(local_position, local_orientation, local_size);
				hull := init_collision_hull(local_position, local_orientation, local_size, kind);
				append(&inanimate_entity.collision_hulls, hull);
			}

			if hull_count > 0 {
				update_entity_hull_transforms_and_bounds(inanimate_entity, inanimate_entity.orientation, inanimate_entity.transform);
				entity_grid_insert(&scene.entity_grid, entity_lookup, inanimate_entity);
			}

			assert(read_u32(&bytes, &pos) == POSITION_CHECK_VALUE);
		}
	}

	{ // Rigid body islands
		island_count := read_u32(&bytes, &pos);
		islands_reset(&scene.islands, island_count);
		
		for island_index in 0..<island_count {
			bodies_count := read_u32(&bytes, &pos);
			
			for _ in 0..<bodies_count {
				name := read_string(&bytes, &pos);
				position := read_vec3(&bytes, &pos);
				orientation := read_quat(&bytes, &pos);
				size := read_vec3(&bytes, &pos);
				geometry_index := read_u32(&bytes, &pos);
				mass := read_f32(&bytes, &pos);
				dimensions := read_vec3(&bytes, &pos);
				collision_exclude := read_bool(&bytes, &pos);
				status_effect_u32 := read_u32(&bytes, &pos);

				status_effect: Status_Effect;
				switch status_effect_u32 {
					case 0: status_effect = .None;
					case 1: status_effect = .Shock;
					case 2: status_effect = .Fire;
					case 3: status_effect = .ExplodingShock;
					case 4: status_effect = .ExplodingFire;
				}

				geometry_lookup := geometry_lookups[geometry_index];
				rigid_body, entity_lookup := create_entity(name, geometry_lookup, Rigid_Body_Entity);
				rigid_body.scene_associated = true;

				rigid_body.position = position;
				rigid_body.orientation = orientation;
				rigid_body.size = size;
				rigid_body.collision_exclude = collision_exclude;
				init_rigid_body_entity(rigid_body, mass, dimensions);
				update_entity_transform(rigid_body);

				hull_count := read_u32(&bytes, &pos);
				for hull_index in 0..<hull_count {
					local_position := read_vec3(&bytes, &pos);
					local_orientation := read_quat(&bytes, &pos);
					local_size := read_vec3(&bytes, &pos);
					kind := cast(Hull_Kind) read_u32(&bytes, &pos);

					local_transform := linalg.matrix4_from_trs(local_position, local_orientation, local_size);
					hull := init_collision_hull(local_position, local_orientation, local_size, kind);
					append(&rigid_body.collision_hulls, hull);
				}

				update_entity_hull_transforms_and_bounds(rigid_body, rigid_body.orientation, rigid_body.transform);
				entity_grid_insert(&scene.entity_grid, entity_lookup, rigid_body);

				if config.init_sleeping_islands {
					add_rigid_body_to_sleeping_island(&scene.islands, int(island_index), entity_lookup, rigid_body);
				} else {
					append(&scene.awake_rigid_bodies, entity_lookup);
				}
				
				switch status_effect {
				case .None:
				case .Shock, .ExplodingShock:
					init_shock_particles(rigid_body);
					append(&scene.shock_entities, entity_lookup);
				case .Fire, .ExplodingFire:
					init_fire_particles(rigid_body);
					append(&scene.fire_entities, entity_lookup);
				}

				assert(read_u32(&bytes, &pos) == POSITION_CHECK_VALUE);
			}
		}
	}

	{ // Oil slicks
		oil_slicks_count := read_u32(&bytes, &pos);

		for _ in 0..<oil_slicks_count {
			name := read_string(&bytes, &pos);
			position := read_vec3(&bytes, &pos);
			orientation := read_quat(&bytes, &pos);
			size := read_vec3(&bytes, &pos);
			geometry_index := read_u32(&bytes, &pos);
			particles_count := cast(int) read_u32(&bytes, &pos);

			geometry_lookup := geometry_lookups[geometry_index];
			entity, entity_lookup := create_entity(name, geometry_lookup, Oil_Slick_Entity);
			entity.scene_associated = true;
			entity.desired_fire_particles = particles_count;
			append(&scene.oil_slicks, entity_lookup);

			local_position := read_vec3(&bytes, &pos);
			local_orientation := read_quat(&bytes, &pos);
			local_size := read_vec3(&bytes, &pos);
			local_transform := linalg.matrix4_from_trs(local_position, local_orientation, local_size);
			indices, positions := read_indices_attributes(&bytes, &pos);
			hull := init_collision_hull(local_position, local_orientation, local_size, .Mesh, indices, positions);
			append(&entity.collision_hulls, hull);
			update_entity_hull_transforms_and_bounds(entity, entity.orientation, entity.transform);

			assert(read_u32(&bytes, &pos) == POSITION_CHECK_VALUE);
		}
	}

	{ // Bumpers
		count := read_u32(&bytes, &pos);

		for _ in 0..<count {
			name := read_string(&bytes, &pos);
			position := read_vec3(&bytes, &pos);
			orientation := read_quat(&bytes, &pos);
			size := read_vec3(&bytes, &pos);
			geometry_index := read_u32(&bytes, &pos);

			geometry_lookup := geometry_lookups[geometry_index];
			entity, entity_lookup := create_entity(name, geometry_lookup, Bumper_Entity);
			entity.scene_associated = true;
			
			entity.position = position;
			entity.orientation = orientation;
			entity.size = size;
			update_entity_transform(entity);

			append(&scene.bumpers, entity_lookup);

			hull_position := read_vec3(&bytes, &pos);
			hull_orientation := read_quat(&bytes, &pos);
			hull_size := read_vec3(&bytes, &pos);
			local_transform := linalg.matrix4_from_trs(hull_position, hull_orientation, hull_size);
			hull := init_collision_hull(hull_position, hull_orientation, hull_size, .Cylinder);
			append(&entity.collision_hulls, hull);
			update_entity_hull_transforms_and_bounds(entity, entity.orientation, entity.transform);

			entity_grid_insert(&scene.entity_grid, entity_lookup, entity);

			assert(read_u32(&bytes, &pos) == POSITION_CHECK_VALUE);
		}
	}

	{ // Boost jets
		count := read_u32(&bytes, &pos);

		for _ in 0..<count {
			name := read_string(&bytes, &pos);
			position := read_vec3(&bytes, &pos);
			orientation := read_quat(&bytes, &pos);
			size := read_vec3(&bytes, &pos);
			geometry_index := read_u32(&bytes, &pos);

			geometry_lookup := geometry_lookups[geometry_index];
			entity, entity_lookup := create_entity(name, geometry_lookup, Boost_Jet_Entity);
			entity.scene_associated = true;

			entity.position = position
			entity.orientation = orientation;
			entity.size = size;
			update_entity_transform(entity);

			append(&scene.boost_jets, entity_lookup);

			hull_position := read_vec3(&bytes, &pos);
			hull_orientation := read_quat(&bytes, &pos);
			hull_size := read_vec3(&bytes, &pos);
			local_transform := linalg.matrix4_from_trs(hull_position, hull_orientation, hull_size);
			hull := init_collision_hull(hull_position, hull_orientation, hull_size, .Box);
			append(&entity.collision_hulls, hull);
			update_entity_hull_transforms_and_bounds(entity, entity.orientation, entity.transform);

			entity_grid_insert(&scene.entity_grid, entity_lookup, entity);
			init_boost_jet_particles(entity);

			assert(read_u32(&bytes, &pos) == POSITION_CHECK_VALUE);
		}
	}

	// Ensure we've added an entity to all the geometries
	when ODIN_DEBUG {
		for geometry_lookup in geometry_lookups {
			geometry := get_geometry(geometry_lookup);
			
			if len(geometry.entity_lookups) == 0 {
				fmt.printf("[level loading] No entities were added to geometry '%s'.\n", geometry.name);
			}
		}
	}

	fmt.printf("Loaded level file %s\n", scene.file_path);
	return;
}

load_car :: proc(car: ^^Car_Entity, scene: ^Scene) {
	REQUIRED_VERSION :: 2;
	
	bytes, success := os.read_entire_file_from_filename("res/car.kgc");
	defer delete(bytes);
	assert(success);
	
	pos := 0;

	version := read_u32(&bytes, &pos);
	assert(REQUIRED_VERSION == version, fmt.tprintf("[car loading] Required version %v but found %v.", REQUIRED_VERSION, version));

	indices, attributes := read_indices_attributes(&bytes, &pos);
	assert(read_u32(&bytes, &pos) == POSITION_CHECK_VALUE);

	{ // Geometry
		geometry, geometry_lookup := create_geometry("car");
		geometry_make_triangle_mesh(geometry, indices[:], attributes[:], .Lambert);

		delete(indices);
		delete(attributes);

		created_car, _ := create_entity("car", geometry_lookup, Car_Entity);
		car^ = created_car;

		car^.position = scene.spawn_position;
		car^.orientation = scene.spawn_orientation;
		update_entity_transform(car^);

		init_car_entity(car^);
	}

	{ // Bottom hull
		local_position := read_vec3(&bytes, &pos);
		local_orientation := read_quat(&bytes, &pos);
		local_size := read_vec3(&bytes, &pos);

		local_transform := linalg.matrix4_from_trs(local_position, local_orientation, local_size);
		hull := init_collision_hull(local_position, local_orientation, local_size, .Box);
		append(&car^.collision_hulls, hull);
	}

	{ // Wheels
		indices, attributes := read_indices_attributes(&bytes, &pos);

		geometry, geometry_lookup := create_geometry("wheel");
		geometry_make_triangle_mesh(geometry, indices[:], attributes[:], .Lambert);

		delete(indices);
		delete(attributes);

		for i in 0..<4 {
			_, entity_lookup := create_entity("wheel", geometry_lookup, Inanimate_Entity);
			car^.wheels[i].entity_lookup = entity_lookup;
		}

		car^.wheel_radius = read_f32(&bytes, &pos);

		assert(read_u32(&bytes, &pos) == POSITION_CHECK_VALUE);
	}
}

load_runtime_assets :: proc(runtime_assets: ^Runtime_Assets) {
	REQUIRED_VERSION :: 1;
	
	bytes, success := os.read_entire_file_from_filename("res/runtime_assets.kga");
	defer delete(bytes);
	assert(success);
	pos := 0;

	version := read_u32(&bytes, &pos);
	assert(REQUIRED_VERSION == version, fmt.tprintf("[runtime assets loading] Required version %v but found %v.", REQUIRED_VERSION, version));

	{ // Shock barrel shrapnel
		count := read_u32(&bytes, &pos);

		for _ in 0..<count {
			indices, attributes := read_indices_attributes(&bytes, &pos);
			position := read_vec3(&bytes, &pos);
			orientation := read_quat(&bytes, &pos);
			size := read_vec3(&bytes, &pos);
			dimensions := read_vec3(&bytes, &pos);
			hull_position := read_vec3(&bytes, &pos);
			hull_orientation := read_quat(&bytes, &pos);
			hull_size := read_vec3(&bytes, &pos);
			
			geometry, geometry_lookup := create_geometry("shrapnel", .Keep);
			geometry_make_triangle_mesh(geometry, indices[:], attributes[:], .LambertTwoSided);

			delete(indices);
			delete(attributes);

			hull_local_transform := linalg.matrix4_from_trs(hull_position, hull_orientation, hull_size);

			shrapnel := Shock_Barrel_Shrapnel_Asset {
				geometry_lookup,
				position,
				orientation,
				size,
				dimensions,
				hull_position,
				hull_orientation,
				hull_size,
			};

			append(&runtime_assets.shock_barrel_shrapnel, shrapnel);

			assert(read_u32(&bytes, &pos) == POSITION_CHECK_VALUE);
		}
	}

	{ // Oil slicks
		count := read_u32(&bytes, &pos);

		for _ in 0..<count {
			indices, attributes := read_indices_attributes(&bytes, &pos);
			hull_position := read_vec3(&bytes, &pos);
			hull_orientation := read_quat(&bytes, &pos);
			hull_size := read_vec3(&bytes, &pos);
			hull_indices, hull_positions := read_indices_attributes(&bytes, &pos);

			geometry, geometry_lookup := create_geometry("Oil slick asset", .Keep);
			geometry_make_triangle_mesh(geometry, indices[:], attributes[:], .Lambert);

			delete(indices);
			delete(attributes);
			
			// #todo Should this be used? Is all we need for the oil slick asset this transform?
			hull_local_transform := linalg.matrix4_from_trs(hull_position, hull_orientation, hull_size);

			oil_slick := Oil_Slick_Asset {
				geometry_lookup,
				hull_position,
				hull_orientation,
				hull_size,
				hull_indices,
				hull_positions,
			};

			append(&runtime_assets.oil_slicks, oil_slick);

			assert(read_u32(&bytes, &pos) == POSITION_CHECK_VALUE);
		}
	}
}

init_scene :: proc(scene: ^Scene) {
	FILE_PATH :: "res/tracks/%s.kgl";

	scene.file_path = fmt.aprintf(FILE_PATH, config.level);
	scene.reload_file_path = fmt.aprintf(FILE_PATH + ".reload", config.level);

	time, error := os.last_write_time_by_name(scene.reload_file_path);
	assert(error == os.ERROR_NONE || error == os.ERROR_FILE_NOT_FOUND);
	
	if error == os.ERROR_NONE {
		scene.load_time = time;
	}

	load_scene(scene);
}

cleanup_scene :: proc(scene: ^Scene) {
	delete(scene.file_path);
	delete(scene.reload_file_path);
}

hot_reload_scene_if_needed :: proc(game: ^Game) {
	scene := &game.scene;
	
	time, error := os.last_write_time_by_name(scene.reload_file_path);
	assert(error == os.ERROR_NONE || error == os.ERROR_FILE_NOT_FOUND);

	if error == os.ERROR_FILE_NOT_FOUND do return;

	if time > scene.load_time {
		load_scene(scene);
		scene.load_time = time;
	}
}