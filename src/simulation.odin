package main;

import "core:math/linalg";
import "math2";
import "core:fmt";

GRAVITY: f32 : -20.0;

simulate :: proc(game: ^Game, dt: f32) {
	for lookup in game.awake_rigid_body_lookups {
		rigid_body := get_entity(&game.entities, lookup).variant.(^Rigid_Body_Entity);

		rigid_body.velocity.y += GRAVITY * dt;
		rigid_body.new_position = rigid_body.position + rigid_body.velocity * dt;

		w := cast(linalg.Quaternionf32) quaternion(0, rigid_body.angular_velocity.x, rigid_body.angular_velocity.y, rigid_body.angular_velocity.z)
		new_orientation := linalg.normalize(rigid_body.orientation + math2.quaternion_mul_f32(w * rigid_body.orientation, 0.5 * dt));
		update_rigid_body_inv_global_inertia_tensor(rigid_body, new_orientation);

		global_entity_transform := linalg.matrix4_from_trs(rigid_body.new_position, new_orientation, rigid_body.size);
		collision_hull_grid_transform_entity(&game.collision_hull_grid, rigid_body.collision_hull_record_indices[:], global_entity_transform);
		
		rigid_body.new_transform = global_entity_transform;
	}

	clear_constraints(&game.constraints);

	checked_hulls := make([dynamic]bool, len(game.collision_hull_grid.hull_records), context.temp_allocator);

	for provoking_lookup in game.awake_rigid_body_lookups {
		provoking_entity := get_entity(&game.entities, provoking_lookup).variant.(^Rigid_Body_Entity);

		for provoking_hull_index in provoking_entity.collision_hull_record_indices {
			provoking_hull := &game.collision_hull_grid.hull_records[provoking_hull_index].hull;

			// Handle collisions with the ground
			nearby_triangle_indices := ground_grid_find_nearby_triangles(&game.ground_grid, provoking_hull.global_bounds);

			for nearby_triangle_index in nearby_triangle_indices {
				nearby_triangle := ground_grid_get_triangle(&game.ground_grid, nearby_triangle_index);

				if manifold, ok := evaluate_ground_collision(game.ground_grid.positions[:], nearby_triangle, provoking_hull).?; ok {
					add_fixed_constraint_set(&game.constraints, provoking_lookup, provoking_entity, &manifold, dt);
				}
			}

			// Handle collisions with other hulls
			nearby_hull_indices := collision_hull_grid_find_nearby_hulls(&game.collision_hull_grid, provoking_hull.global_bounds);

			for nearby_hull_index in nearby_hull_indices {
				if checked_hulls[nearby_hull_index] || provoking_hull_index == nearby_hull_index do continue;

				nearby_hull_record := &game.collision_hull_grid.hull_records[nearby_hull_index];
				nearby_lookup := nearby_hull_record.entity_lookup;
				nearby_hull := &nearby_hull_record.hull;

				if provoking_lookup == nearby_lookup do continue;

				nearby_entity := get_entity(&game.entities, nearby_lookup);

				if nearby_rigid_body, ok := nearby_entity.variant.(^Rigid_Body_Entity); ok {
					if provoking_entity.collision_exclude && nearby_rigid_body.collision_exclude do continue;
				}

				if manifold, ok := evaluate_entity_collision(provoking_hull, nearby_hull).?; ok {
					switch e in nearby_entity.variant {
						case ^Rigid_Body_Entity:
							add_movable_constraint_set(&game.constraints, provoking_lookup, nearby_lookup, provoking_entity, e, &manifold, dt);
						case ^Inanimate_Entity:
							add_fixed_constraint_set(&game.constraints, provoking_lookup, provoking_entity, &manifold, dt);
					}
				}
			}

			checked_hulls[provoking_hull_index] = true;
		}
	}

	solve_constraints(&game.constraints, &game.entities);

	for lookup in game.awake_rigid_body_lookups {
		rigid_body := get_entity(&game.entities, lookup).variant.(^Rigid_Body_Entity);

		rigid_body.position += rigid_body.velocity * dt;

		w := cast(linalg.Quaternionf32) quaternion(0, rigid_body.angular_velocity.x, rigid_body.angular_velocity.y, rigid_body.angular_velocity.z)
		rigid_body.orientation += math2.quaternion_mul_f32(w * rigid_body.orientation, 0.5 * dt);
		rigid_body.orientation = linalg.normalize(rigid_body.orientation);
		
		update_entity_transform(rigid_body);
	}
}