package main;

import "core:math/linalg";
import "entity";
import "physics";
import "math2";

GRAVITY: f32 : -20.0;

simulate :: proc(game: ^Game, dt: f32) {
	for lookup in game.awake_rigid_body_lookups {
		rigid_body := entity.get_entity(&game.entities, entity.Rigid_Body_Entity, lookup);

		rigid_body.velocity.y += GRAVITY * dt;
		rigid_body.new_position = rigid_body.position + rigid_body.velocity * dt;

		w := cast(linalg.Quaternionf32) quaternion(0, rigid_body.angular_velocity.x, rigid_body.angular_velocity.y, rigid_body.angular_velocity.z)
		new_rotation := linalg.normalize(rigid_body.orientation + w * math2.quaternion_mul_f32(rigid_body.orientation, 0.5 * dt)); // #nocheckin new_orientation
		entity.update_rigid_body_inv_global_inertia_tensor(rigid_body, new_rotation);

		global_entity_transform := linalg.matrix4_from_trs(rigid_body.new_position, new_rotation, rigid_body.size);
		// collision_hull_grid::update_hull_global_transform_mat_and_bounds(&mut scene.collision_hull_grid, global_entity_transform_mat, &entity.collision_hull_indices);
		
		rigid_body.new_transform = global_entity_transform;
	}

	for lookup in game.awake_rigid_body_lookups {
		rigid_body := entity.get_entity(&game.entities, entity.Rigid_Body_Entity, lookup);

		rigid_body.position += rigid_body.velocity * dt;

		w := cast(linalg.Quaternionf32) quaternion(0, rigid_body.angular_velocity.x, rigid_body.angular_velocity.y, rigid_body.angular_velocity.z)
		rigid_body.orientation += math2.quaternion_mul_f32(w * rigid_body.orientation, 0.5 * dt);
		rigid_body.orientation = linalg.normalize0(rigid_body.orientation);
		
		entity.update_entity_transform(rigid_body);
	}
}