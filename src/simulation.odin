package main;

import "core:math";
import "core:math/linalg";
import "core:container/small_array";
import "math2";

GRAVITY: f32 : -20.0;

simulate :: proc(using game: ^Game, dt: f32) {
	{
		car.velocity.y += GRAVITY * dt;
		car.new_position = car.position + car.velocity * dt;

		new_orientation := math2.integrate_angular_velocity(car.angular_velocity, car.orientation, dt);
		car.inv_global_inertia_tensor = math2.calculate_inv_global_inertia_tensor(new_orientation, CAR_INV_LOCAL_INERTIA_TENSOR);

		transform := linalg.matrix4_from_trs(car.new_position, new_orientation, linalg.Vector3f32 {1, 1, 1});
		collision_hull_grid_transform_entity(&collision_hull_grid, car.collision_hull_record_indices[:], transform);
		car.new_transform = transform;
	}

	clear_islands(&islands);

	for lookup in awake_rigid_body_lookups {
		rigid_body := get_entity(&entities_geos, lookup).variant.(^Rigid_Body_Entity);

		rigid_body.velocity.y += GRAVITY * dt;
		rigid_body.new_position = rigid_body.position + rigid_body.velocity * dt;

		new_orientation := math2.integrate_angular_velocity(rigid_body.angular_velocity, rigid_body.orientation, dt);
		rigid_body.inv_global_inertia_tensor = math2.calculate_inv_global_inertia_tensor(new_orientation, rigid_body.inv_local_inertia_tensor);

		transform := linalg.matrix4_from_trs(rigid_body.new_position, new_orientation, rigid_body.size);
		collision_hull_grid_transform_entity(&collision_hull_grid, rigid_body.collision_hull_record_indices[:], transform);

		init_island(&islands, lookup, rigid_body);
	}

	clear_constraints(&constraints);
	find_spring_constraints(game, dt);

	// Car collisions
	for hull_index in car.collision_hull_record_indices {
		provoking_hull_record := &collision_hull_grid.hull_records[hull_index];
		provoking_hull := &provoking_hull_record.hull;

		// Ground collisions
		nearby_triangle_indices := ground_grid_find_nearby_triangles(&ground_grid, provoking_hull.global_bounds);

		for nearby_triangle_index in nearby_triangle_indices {
			nearby_triangle := ground_grid_get_triangle(&ground_grid, nearby_triangle_index);

			if manifold, ok := evaluate_ground_collision(ground_grid.positions[:], nearby_triangle, provoking_hull).?; ok {
				add_car_fixed_constraint_set(&constraints, car, &manifold, dt);
			}
		}

		// Other hull collisions
		nearby_hull_indices := collision_hull_grid_find_nearby_hulls(&collision_hull_grid, provoking_hull.global_bounds);

		for nearby_hull_index in nearby_hull_indices {
			nearby_hull_record := &collision_hull_grid.hull_records[nearby_hull_index];
			nearby_lookup := nearby_hull_record.entity_lookup;

			provoking_lookup := provoking_hull_record.entity_lookup; // This would just been the car entity lookup which we don't save anywhere but could.
			if provoking_lookup == nearby_lookup do continue;

			nearby_hull := &nearby_hull_record.hull;

			if manifold, ok := evaluate_entity_collision(provoking_hull, nearby_hull).?; ok {
				nearby_entity := get_entity(&entities_geos, nearby_lookup);
				
				switch e in nearby_entity.variant {
					case ^Rigid_Body_Entity:
						unimplemented();
					case ^Inanimate_Entity:
						// This could be a fixed constraint that doesn't rotate the car. We'd just have to keep in mind what would happen when the car lands upside down on an inanimate entity.
						// Maybe we could add a normal constraint if there are no spring constraints so it still rolls over when landing upside down.
						add_car_fixed_constraint_set(&constraints, car, &manifold, dt);
					case ^Car_Entity:
						unreachable();
				}
			}
		}
	}

	// Other rigid body collisions
	checked_hulls := make([dynamic]bool, len(collision_hull_grid.hull_records), context.temp_allocator);
	entities_woken_up := make([dynamic]Entity_Lookup, context.temp_allocator);

	for provoking_lookup in awake_rigid_body_lookups {
		provoking_entity := get_entity(&entities_geos, provoking_lookup).variant.(^Rigid_Body_Entity);

		for provoking_hull_index in provoking_entity.collision_hull_record_indices {
			provoking_hull := &collision_hull_grid.hull_records[provoking_hull_index].hull;

			// Handle collisions with the ground
			nearby_triangle_indices := ground_grid_find_nearby_triangles(&ground_grid, provoking_hull.global_bounds);

			for nearby_triangle_index in nearby_triangle_indices {
				nearby_triangle := ground_grid_get_triangle(&ground_grid, nearby_triangle_index);

				if manifold, ok := evaluate_ground_collision(ground_grid.positions[:], nearby_triangle, provoking_hull).?; ok {
					add_fixed_constraint_set(&constraints, provoking_lookup, provoking_entity, &manifold, dt);
				}
			}

			// Handle collisions with other hulls
			nearby_hull_indices := collision_hull_grid_find_nearby_hulls(&collision_hull_grid, provoking_hull.global_bounds);

			for nearby_hull_index in nearby_hull_indices {
				if checked_hulls[nearby_hull_index] || provoking_hull_index == nearby_hull_index do continue;

				nearby_hull_record := &collision_hull_grid.hull_records[nearby_hull_index];
				nearby_lookup := nearby_hull_record.entity_lookup;

				if provoking_lookup == nearby_lookup do continue;

				nearby_entity := get_entity(&entities_geos, nearby_lookup);

				if nearby_rigid_body, ok := nearby_entity.variant.(^Rigid_Body_Entity); ok {
					if provoking_entity.collision_exclude && nearby_rigid_body.collision_exclude do continue;
				}
				
				nearby_hull := &nearby_hull_record.hull;

				if manifold, ok := evaluate_entity_collision(provoking_hull, nearby_hull).?; ok {
					switch e in nearby_entity.variant {
						case ^Rigid_Body_Entity:
							add_movable_constraint_set(&constraints, provoking_lookup, nearby_lookup, provoking_entity, e, &manifold, dt);
							merge_islands(&islands, &entities_geos, &entities_woken_up, provoking_entity, e);
						case ^Inanimate_Entity:
							add_fixed_constraint_set(&constraints, provoking_lookup, provoking_entity, &manifold, dt);
						case ^Car_Entity:
							// unreachable(); I don't see a need to have the car's hulls be in the collision hull grid. If we can remove them we can have this be unreachable.
							// Maybe the car can just own it's hulls because those are stored in the collision hull grid right now.
							continue;
					}
				}
			}

			checked_hulls[provoking_hull_index] = true;
		}
	}

	solve_constraints(&constraints, &entities_geos, car);
	append(&awake_rigid_body_lookups, ..entities_woken_up[:]);

	{
		car.position += car.velocity * dt;
		car.orientation = math2.integrate_angular_velocity(car.angular_velocity, car.orientation, dt);

		update_entity_transform(car);
	}

	for lookup in awake_rigid_body_lookups {
		rigid_body := get_entity(&entities_geos, lookup).variant.(^Rigid_Body_Entity);

		old_position := rigid_body.position;
		rigid_body.position += rigid_body.velocity * dt;

		rigid_body.orientation = math2.integrate_angular_velocity(rigid_body.angular_velocity, rigid_body.orientation, dt);
		
		update_entity_transform(rigid_body);

		if linalg.length2(rigid_body.position - old_position) < 0.00005 {
			rigid_body.sleep_duration += dt;
		} else {
			rigid_body.sleep_duration = 0;
		}
	}

	sleep_islands(&islands, &entities_geos, &awake_rigid_body_lookups);
}

Spring_Contact_Manifold :: struct {
	normal: linalg.Vector3f32,
	contacts: small_array.Small_Array(4, Spring_Contact),
}

Spring_Contact :: struct {
	body_point: linalg.Vector3f32,
	length: f32,
}

SPRING_BODY_POINT_Z: f32 : 1.1;

find_spring_constraints :: proc(using game: ^Game, dt: f32) {
	extension_dir := -math2.matrix4_up(car.new_transform);

	SPRING_BODY_POINT_X: f32 : 0.8;
	SPRING_BODY_POINT_Y: f32 : -0.35

	SPRING_BODY_POINT_LOCAL_FL :: linalg.Vector3f32 {SPRING_BODY_POINT_X, SPRING_BODY_POINT_Y, SPRING_BODY_POINT_Z};
	SPRING_BODY_POINT_LOCAL_FR :: linalg.Vector3f32 {-SPRING_BODY_POINT_X, SPRING_BODY_POINT_Y, SPRING_BODY_POINT_Z};
	SPRING_BODY_POINT_LOCAL_BL :: linalg.Vector3f32 {SPRING_BODY_POINT_X, SPRING_BODY_POINT_Y, -SPRING_BODY_POINT_Z};
	SPRING_BODY_POINT_LOCAL_BR :: linalg.Vector3f32 {-SPRING_BODY_POINT_X, SPRING_BODY_POINT_Y, -SPRING_BODY_POINT_Z};

	spring_body_point_fl := math2.matrix4_transform_point(car.new_transform, SPRING_BODY_POINT_LOCAL_FL);
	spring_body_point_fr := math2.matrix4_transform_point(car.new_transform, SPRING_BODY_POINT_LOCAL_FR);
	spring_body_point_bl := math2.matrix4_transform_point(car.new_transform, SPRING_BODY_POINT_LOCAL_BL);
	spring_body_point_br := math2.matrix4_transform_point(car.new_transform, SPRING_BODY_POINT_LOCAL_BR);

	SPRING_MAX_LENGTH: f32 : 0.8;

	spring_wheel_point_fl := spring_body_point_fl + extension_dir * SPRING_MAX_LENGTH;
	spring_wheel_point_fr := spring_body_point_fr + extension_dir * SPRING_MAX_LENGTH;
	spring_wheel_point_bl := spring_body_point_bl + extension_dir * SPRING_MAX_LENGTH;
	spring_wheel_point_br := spring_body_point_br + extension_dir * SPRING_MAX_LENGTH;

	spring_bounds_fl := math2.Box3f32 {linalg.min(spring_body_point_fl, spring_wheel_point_fl), linalg.max(spring_body_point_fl, spring_wheel_point_fl)};
	spring_bounds_fr := math2.Box3f32 {linalg.min(spring_body_point_fr, spring_wheel_point_fr), linalg.max(spring_body_point_fr, spring_wheel_point_fr)};
	spring_bounds_bl := math2.Box3f32 {linalg.min(spring_body_point_bl, spring_wheel_point_bl), linalg.max(spring_body_point_bl, spring_wheel_point_bl)};
	spring_bounds_br := math2.Box3f32 {linalg.min(spring_body_point_br, spring_wheel_point_br), linalg.max(spring_body_point_br, spring_wheel_point_br)};

	spring_bounds := math2.box_union(spring_bounds_fl, spring_bounds_fr, spring_bounds_bl, spring_bounds_br);

	triangle_indices := ground_grid_find_nearby_triangles(&ground_grid, spring_bounds);
	hull_indices := collision_hull_grid_find_nearby_hulls(&collision_hull_grid, spring_bounds);

	manifold := Spring_Contact_Manifold {
		normal = -extension_dir,
	};

	spring_body_points := [?]linalg.Vector3f32 {spring_body_point_fl, spring_body_point_fr, spring_body_point_bl, spring_body_point_br};

	for spring_index in 0..<4 {
		best_spring_contact := Spring_Contact_Intermediary {
			length = max(f32),
		};

		spring_body_point := spring_body_points[spring_index];

		for triangle_index in triangle_indices {
			triangle := ground_grid_get_triangle(&ground_grid, triangle_index);

			a_index := triangle.indices[0] * 3;
			b_index := triangle.indices[1] * 3;
			c_index := triangle.indices[2] * 3;	

			positions := &ground_grid.positions;
			a := linalg.Vector3f32 {positions[a_index], positions[a_index + 1], positions[a_index + 2]};
			b := linalg.Vector3f32 {positions[b_index], positions[b_index + 1], positions[b_index + 2]};
			c := linalg.Vector3f32 {positions[c_index], positions[c_index + 1], positions[c_index + 2]};

			if contact, ok := spring_intersects_triangle(spring_body_point, extension_dir, SPRING_MAX_LENGTH, a, b, c).?; ok {
				if math.acos(linalg.dot(-extension_dir, contact.normal)) > math.PI / 4 {
					continue;
				}

				if contact.length < best_spring_contact.length {
					best_spring_contact = contact;
				}
			}
		}

		wheel := Wheel {
			spring_body_point,
			nil,
		};

		if best_spring_contact.length != max(f32) {
			small_array.append(&manifold.contacts, Spring_Contact {
				spring_body_point,
				best_spring_contact.length,
			});

			wheel.contact = Wheel_Contact {
				best_spring_contact.normal,
				best_spring_contact.length,
			};
		}

		car.wheels[spring_index] = wheel;
	}

	if small_array.len(manifold.contacts) > 0 {
		set_spring_constraint_set(&constraints, car, &manifold, dt);
	}
}

Spring_Contact_Intermediary :: struct {
	normal: linalg.Vector3f32,
	length: f32,
}

spring_intersects_triangle :: proc(origin: linalg.Vector3f32, direction: linalg.Vector3f32, length: f32, a, b, c: linalg.Vector3f32) -> Maybe(Spring_Contact_Intermediary) {
	ab := b - a;
	ac := c - a;

	p := linalg.cross(direction, ac);
	det := linalg.dot(p, ab);

	if det < 0 {
		return nil;
	}
	
	t := origin - a;
	u := linalg.dot(p, t);

	if u < 0 || u > det {
		return nil;
	}

	q := linalg.cross(t, ab);
	v := linalg.dot(q, direction);

	if v < 0 || u + v > det {
		return nil;
	}

	dist := (1 / det) * linalg.dot(q, ac);

	if dist > length {
		return nil;
	}

	n := linalg.normalize(linalg.cross(ab, ac));
	return Spring_Contact_Intermediary {n, dist};
}