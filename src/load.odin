package main

import "core:os";
import "core:math/linalg";
import "core:fmt";
import "core:mem";
import "entity";
import "physics";

load_level :: proc(using game: ^Game) {
	read_u32 :: proc(bytes: ^[]byte, pos: ^int) -> u32 {
		v := cast(u32) (cast(^u32le) raw_data(bytes[pos^:]))^;
		pos^ += 4;
		return v;
	}

	read_u8 :: proc(bytes: ^[]byte, pos: ^int) -> u8 {
		v := (cast(^u8) raw_data(bytes[pos^:]))^;
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

	bytes, success := os.read_entire_file_from_filename("res/all.kgl");
	assert(success);

	pos := 0;
	spawn_position := read_vec3(&bytes, &pos);
	spawn_rotation := read_quat(&bytes, &pos);

	// Ground grid
	ground_grid_half_size: f32;
	{
		ground_grid_half_size = read_f32(&bytes, &pos);
		physics.reset_ground_grid(&ground_grid, ground_grid_half_size);
		
		meshes_count := read_u32(&bytes, &pos);

		for i in 0..<meshes_count {
			indices, positions := read_indices_attributes(&bytes, &pos);
			physics.insert_into_ground_grid(&ground_grid, &indices, &positions);
		}
	}

	{ // Geometries
		geometries_count := read_u32(&bytes, &pos);
		
		for i in 0..<geometries_count {
			indices, attributes := read_indices_attributes(&bytes, &pos);
			geometry := entity.init_triangle_geometry(indices, attributes);
			entity.add_geometry(&entities, geometry);
		}
	}

	{ // Inanimate entities
		inanimate_entities_count := read_u32(&bytes, &pos);

		for i in 0..<inanimate_entities_count {
			position := read_vec3(&bytes, &pos);
			rotation := read_quat(&bytes, &pos);
			scale := read_vec3(&bytes, &pos);
			geometry_index := read_u32(&bytes, &pos);
			hull_count := read_u32(&bytes, &pos);

			for hull_index in 0..<hull_count {
				local_position := read_vec3(&bytes, &pos);
				local_rotation := read_quat(&bytes, &pos);
				local_scale := read_vec3(&bytes, &pos);
				hull_type := read_u32(&bytes, &pos);
			}

			inanimate_entity := entity.init_entity(position, rotation, scale);
			entity.add_entity(&entities, int(geometry_index), inanimate_entity);
		}
	}

	{ // Rigid body islands
		physics.reset_collision_hull_grid(&collision_hull_grid, ground_grid_half_size);

		island_count := read_u32(&bytes, &pos);
		for island_index in 0..<island_count {
			bodies_count := read_u32(&bytes, &pos);
			for body_index in 0..<bodies_count {
				position := read_vec3(&bytes, &pos);
				rotation := read_quat(&bytes, &pos);
				scale := read_vec3(&bytes, &pos);
				geometry_index := read_u32(&bytes, &pos);
				hull_count := read_u32(&bytes, &pos);

				for hull_index in 0..<hull_count {
					local_position := read_vec3(&bytes, &pos);
					local_rotation := read_quat(&bytes, &pos);
					local_scale := read_vec3(&bytes, &pos);
					hull_type := read_u32(&bytes, &pos);
				}

				mass := read_f32(&bytes, &pos);
				dimensions := read_vec3(&bytes, &pos);
				collision_exclude := cast(bool) read_u8(&bytes, &pos);

				body := entity.init_rigid_body_entity(position, rotation, scale, mass, dimensions);
				body.collision_exclude = collision_exclude;
			}
		}
	}
}