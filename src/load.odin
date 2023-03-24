package main

import "core:os";
import "core:math/linalg";
import "core:fmt";
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
	file_path := fmt.tprintf("res/maps/%s.kgl", game.config.level);
	bytes, success := os.read_entire_file_from_filename(file_path);
	defer delete(bytes);
	assert(success, fmt.tprintf("Failed to load level file %s", file_path));

	pos := 0;
	spawn_position = read_vec3(&bytes, &pos);
	spawn_orientation = read_quat(&bytes, &pos);

	// Ground grid
	ground_grid_half_size := read_f32(&bytes, &pos);
	reset_ground_grid(&ground_grid, ground_grid_half_size);
	reset_collision_hull_grid(&collision_hull_grid, ground_grid_half_size);
	
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
		indices, attributes := read_indices_attributes(&bytes, &pos);
		geometry := init_triangle_geometry("", indices, attributes);
		geometry_lookups[i] = add_geometry(&entities_geos, geometry);

		assert(read_u32(&bytes, &pos) == POSITION_CHECK_VALUE);
	}

	{ // Inanimate entities
		inanimate_entities_count := read_u32(&bytes, &pos);

		for i in 0..<inanimate_entities_count {
			position := read_vec3(&bytes, &pos);
			orientation := read_quat(&bytes, &pos);
			size := read_vec3(&bytes, &pos);
			geometry_index := read_u32(&bytes, &pos);
			hull_count := read_u32(&bytes, &pos);

			inanimate_entity := new_inanimate_entity(position, orientation, size);
			entity_lookup := add_entity(&entities_geos, geometry_lookups[geometry_index], inanimate_entity);

			for hull_index in 0..<hull_count {
				local_position := read_vec3(&bytes, &pos);
				local_orientation := read_quat(&bytes, &pos);
				local_size := read_vec3(&bytes, &pos);
				kind := cast(Hull_Kind) read_u32(&bytes, &pos);

				local_transform := linalg.matrix4_from_trs(local_position, local_orientation, local_size);
				hull := init_collision_hull(local_transform, inanimate_entity.transform, kind);
				
				append(&inanimate_entity.collision_hulls, hull);
				hull_ptr := slice.last_ptr(inanimate_entity.collision_hulls[:]);
				insert_into_collision_hull_grid(&collision_hull_grid, entity_lookup, hull_ptr);
			}

			assert(read_u32(&bytes, &pos) == POSITION_CHECK_VALUE);
		}
	}

	{ // Rigid body islands
		island_count := read_u32(&bytes, &pos);
		init_islands(&islands, island_count);
		
		for island_index in 0..<island_count {
			bodies_count := read_u32(&bytes, &pos);
			
			for body_index in 0..<bodies_count {
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
					case: unreachable()
				}

				rigid_body := new_rigid_body_entity(position, orientation, size, mass, dimensions, status_effect);
				rigid_body.collision_exclude = collision_exclude;
				entity_lookup := add_entity(&entities_geos, geometry_lookups[geometry_index], rigid_body);

				hull_count := read_u32(&bytes, &pos);
				for hull_index in 0..<hull_count {
					local_position := read_vec3(&bytes, &pos);
					local_orientation := read_quat(&bytes, &pos);
					local_size := read_vec3(&bytes, &pos);
					kind := cast(Hull_Kind) read_u32(&bytes, &pos);

					local_transform := linalg.matrix4_from_trs(local_position, local_orientation, local_size);
					hull := init_collision_hull(local_transform, rigid_body.transform, kind);

					append(&rigid_body.collision_hulls, hull);
					hull_ptr := slice.last_ptr(rigid_body.collision_hulls[:]);
					hull_record := insert_into_collision_hull_grid(&collision_hull_grid, entity_lookup, hull_ptr);
					append(&rigid_body.collision_hull_record_indices, hull_record);
				}

				// add_rigid_body_to_island(&islands, int(island_index), entity_lookup, rigid_body);
				append(&awake_rigid_body_lookups, entity_lookup);

				#partial switch status_effect {
					case .Shock:
						append(&shock_cubes, entity_lookup);
					case .Fire:
						append(&fire_cubes, entity_lookup);
				}

				assert(read_u32(&bytes, &pos) == POSITION_CHECK_VALUE);
			}
		}
	}

	fmt.printf("Loaded level file %s\n", file_path);
	return;
}

load_car :: proc(using game: ^Game, spawn_position: linalg.Vector3f32, spawn_orientation: linalg.Quaternionf32) {
	bytes, success := os.read_entire_file_from_filename("res/car.kgc");
	defer delete(bytes);
	assert(success);
	
	pos := 0;

	indices, attributes := read_indices_attributes(&bytes, &pos);

	geometry := init_triangle_geometry("car", indices, attributes);
	geometry_lookup := add_geometry(&entities_geos, geometry);
	entity := new_car_entity(spawn_position, spawn_orientation);
	entity_lookup := add_entity(&entities_geos, geometry_lookup, entity);
	game.car = entity;

	hull_count := read_u32(&bytes, &pos);
	for hull_index in 0..<hull_count {
		local_position := read_vec3(&bytes, &pos);
		local_orientation := read_quat(&bytes, &pos);
		local_scale := read_vec3(&bytes, &pos);
		kind := cast(Hull_Kind) read_u32(&bytes, &pos);

		local_transform := linalg.matrix4_from_trs(local_position, local_orientation, local_scale);
		hull := init_collision_hull(local_transform, entity.transform, kind);
		append(&car.collision_hulls, hull);
	}
	
	position_check := read_u32(&bytes, &pos);
	assert(position_check == POSITION_CHECK_VALUE);

	{ // Wheels
		indices, attributes := read_indices_attributes(&bytes, &pos);
		geometry := init_triangle_geometry("wheel", indices, attributes);
		geometry_lookup := add_geometry(&entities_geos, geometry);

		for i in 0..<4 {
			entity := new_inanimate_entity();
			entity_lookup := add_entity(&entities_geos, geometry_lookup, entity);
			car.wheels[i].entity_lookup = entity_lookup;
		}

		car.wheel_radius = read_f32(&bytes, &pos);
	}
}