package main;

import "core:math/linalg";
import "math2";
import "core:fmt";

GRAVITY: f32 : -20.0;

simulate :: proc(game: ^Game, dt: f32) {
	for lookup in game.awake_rigid_body_lookups {
		rigid_body := get_entity(&game.entities, Rigid_Body_Entity, lookup);

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

	for provoking_lookup in game.awake_rigid_body_lookups {
		provoking_entity := get_entity(&game.entities, Rigid_Body_Entity, provoking_lookup);

		for provoking_hull_record_index in provoking_entity.collision_hull_record_indices {
			provoking_hull := collision_hull_grid_get_collision_hull(&game.collision_hull_grid, provoking_hull_record_index);

			// Handle collisions with the ground
			nearby_triangle_indices := ground_grid_find_nearby_triangles(&game.ground_grid, provoking_hull.global_bounds);

			for nearby_triangle_index in nearby_triangle_indices {
				nearby_triangle := ground_grid_get_triangle(&game.ground_grid, nearby_triangle_index);

				if manifold, ok := evaluate_ground_collision(game.ground_grid.positions[:], nearby_triangle, provoking_hull).?; ok {
					add_fixed_constraint_set(&game.constraints, provoking_lookup, provoking_entity, &manifold, dt);
				}
			}

			// Handle collisions with other hulls
		}
	}

	solve_constraints(&game.constraints, &game.entities);

	for lookup in game.awake_rigid_body_lookups {
		rigid_body := get_entity(&game.entities, Rigid_Body_Entity, lookup);

		rigid_body.position += rigid_body.velocity * dt;

		w := cast(linalg.Quaternionf32) quaternion(0, rigid_body.angular_velocity.x, rigid_body.angular_velocity.y, rigid_body.angular_velocity.z)
		rigid_body.orientation += math2.quaternion_mul_f32(w * rigid_body.orientation, 0.5 * dt);
		rigid_body.orientation = linalg.normalize(rigid_body.orientation);
		
		update_entity_transform(rigid_body);
	}
}