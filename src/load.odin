package main

import "core:os";
import "core:math/linalg";
import "core:fmt";
import "core:strings";

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

load_level :: proc(using game: ^Game) -> (spawn_position: linalg.Vector3f32, spawn_orientation: linalg.Quaternionf32) {
	REQUIRED_VERSION :: 3;
	
	file_path := fmt.tprintf("res/maps/%s.kgl", config.level);
	bytes, success := os.read_entire_file_from_filename(file_path);
	defer delete(bytes);
	assert(success, fmt.tprintf("Failed to load level file %s", file_path));
	
	pos := 0;

	version := read_u32(&bytes, &pos);
	assert(REQUIRED_VERSION == version, fmt.tprintf("[level loading] Required version %v but found %v.", REQUIRED_VERSION, version));

	spawn_position = read_vec3(&bytes, &pos);
	spawn_orientation = read_quat(&bytes, &pos);

	// Init grids
	grid_half_size := read_f32(&bytes, &pos);
	reset_ground_grid(&ground_grid, grid_half_size);
	init_entity_grid(&entity_grid, grid_half_size);
	
	{
		meshes_count := read_u32(&bytes, &pos);

		for i in 0..<meshes_count {
			indices, positions := read_indices_attributes(&bytes, &pos);
			insert_into_ground_grid(&ground_grid, indices[:], positions[:]);
			
			delete(indices);
			delete(positions);

			assert(read_u32(&bytes, &pos) == POSITION_CHECK_VALUE);
		}
	}

	// Geometries
	geometries_count := read_u32(&bytes, &pos);
	geometry_lookups := make([dynamic]Geometry_Lookup, geometries_count);
	defer delete(geometry_lookups);

	for i in 0..<geometries_count {
		name := read_string(&bytes, &pos);
		indices, attributes := read_indices_attributes(&bytes, &pos);
		geometry := init_triangle_geometry(name, indices, attributes, .Lambert);
		geometry_lookups[i] = add_geometry(geometry);

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

			inanimate_entity := new_inanimate_entity(name, position, orientation, size);
			entity_lookup := add_entity(geometry_lookups[geometry_index], inanimate_entity);

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
				insert_entity_into_grid(&entity_grid, inanimate_entity);
			}

			assert(read_u32(&bytes, &pos) == POSITION_CHECK_VALUE);
		}
	}

	{ // Rigid body islands
		island_count := read_u32(&bytes, &pos);
		init_islands(&islands, island_count);
		
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

				rigid_body := new_rigid_body_entity(name, position, orientation, size, mass, dimensions, status_effect);
				rigid_body.collision_exclude = collision_exclude;
				entity_lookup := add_entity(geometry_lookups[geometry_index], rigid_body);

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
				insert_entity_into_grid(&entity_grid, rigid_body);

				if config.init_sleeping_islands {
					add_rigid_body_to_island(&islands, int(island_index), entity_lookup, rigid_body);
				} else {
					append(&awake_rigid_body_lookups, entity_lookup);
				}
				
				switch status_effect {
					case .None:
					case .Shock, .ExplodingShock:
						append(&shock_entities, entity_lookup);
					case .Fire, .ExplodingFire:
						append(&fire_entities, entity_lookup);
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

			entity := new_oil_slick_entity(name, position, orientation, size, particles_count);
			entity_lookup := add_entity(geometry_lookups[geometry_index], entity);
			append(&game.oil_slick_lookups, entity_lookup);

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

			entity := new_bumper_entity(name, position, orientation, size);
			entity_lookup := add_entity(geometry_lookups[geometry_index], entity);
			append(&game.bumper_lookups, entity_lookup);

			hull_position := read_vec3(&bytes, &pos);
			hull_orientation := read_quat(&bytes, &pos);
			hull_size := read_vec3(&bytes, &pos);
			local_transform := linalg.matrix4_from_trs(hull_position, hull_orientation, hull_size);
			hull := init_collision_hull(hull_position, hull_orientation, hull_size, .Cylinder);
			append(&entity.collision_hulls, hull);
			update_entity_hull_transforms_and_bounds(entity, entity.orientation, entity.transform);

			insert_entity_into_grid(&entity_grid, entity);

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

			entity := new_boost_jet_entity(name, position, orientation, size);
			entity_lookup := add_entity(geometry_lookups[geometry_index], entity);
			append(&game.boost_jet_lookups, entity_lookup);

			hull_position := read_vec3(&bytes, &pos);
			hull_orientation := read_quat(&bytes, &pos);
			hull_size := read_vec3(&bytes, &pos);
			local_transform := linalg.matrix4_from_trs(hull_position, hull_orientation, hull_size);
			hull := init_collision_hull(hull_position, hull_orientation, hull_size, .Box);
			append(&entity.collision_hulls, hull);
			update_entity_hull_transforms_and_bounds(entity, entity.orientation, entity.transform);

			insert_entity_into_grid(&entity_grid, entity);

			assert(read_u32(&bytes, &pos) == POSITION_CHECK_VALUE);
		}
	}

	fmt.printf("Loaded level file %s\n", file_path);
	return;
}

load_car :: proc(game: ^Game, spawn_position: linalg.Vector3f32, spawn_orientation: linalg.Quaternionf32) {
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
		geometry := init_triangle_geometry("car", indices, attributes, .Lambert);
		geometry_lookup := add_geometry(geometry);
		entity := new_car_entity(spawn_position, spawn_orientation);
		add_entity(geometry_lookup, entity);
		game.car = entity;
	}

	{ // Bottom hull
		local_position := read_vec3(&bytes, &pos);
		local_orientation := read_quat(&bytes, &pos);
		local_size := read_vec3(&bytes, &pos);

		local_transform := linalg.matrix4_from_trs(local_position, local_orientation, local_size);
		hull := init_collision_hull(local_position, local_orientation, local_size, .Box);
		append(&game.car.collision_hulls, hull);
	}

	{ // Wheels
		indices, attributes := read_indices_attributes(&bytes, &pos);
		geometry := init_triangle_geometry("wheel", indices, attributes, .Lambert);
		geometry_lookup := add_geometry(geometry);

		for i in 0..<4 {
			entity := new_inanimate_entity("wheel");
			entity_lookup := add_entity(geometry_lookup, entity);
			game.car.wheels[i].entity_lookup = entity_lookup;
		}

		game.car.wheel_radius = read_f32(&bytes, &pos);

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
			
			geo := init_triangle_geometry("shrapnel", indices, attributes, .LambertTwoSided);
			geo_lookup := add_geometry(geo, .Keep);
			hull_local_transform := linalg.matrix4_from_trs(hull_position, hull_orientation, hull_size);

			shrapnel := Shock_Barrel_Shrapnel_Asset {
				geo_lookup,
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

			geo := init_triangle_geometry("oil_slick_asset", indices, attributes, .Lambert);
			geo_lookup := add_geometry(geo, .Keep);
			
			hull_local_transform := linalg.matrix4_from_trs(hull_position, hull_orientation, hull_size);

			oil_slick := Oil_Slick_Asset {
				geo_lookup,
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