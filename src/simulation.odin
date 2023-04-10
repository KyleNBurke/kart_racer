package main;

import "core:math";
import "core:math/linalg";
import "core:container/small_array";
import "core:slice";
import "math2";

import "core:fmt";

GRAVITY: f32 : -20.0;

simulate :: proc(game: ^Game, dt: f32) {
	{
		car := game.car;

		car.velocity.y += GRAVITY * dt;
		car.new_position = car.position + car.velocity * dt;

		new_orientation := math2.integrate_angular_velocity(car.angular_velocity, car.orientation, dt);
		car.inv_global_inertia_tensor = math2.calculate_inv_global_inertia_tensor(new_orientation, CAR_INV_LOCAL_INERTIA_TENSOR);

		car.new_transform = linalg.matrix4_from_trs(car.new_position, new_orientation, linalg.Vector3f32 {1, 1, 1});

		update_entity_hull_transforms_and_bounds(car, car.new_transform);
	}

	clear_islands(&game.islands);

	for lookup in game.awake_rigid_body_lookups {
		rigid_body := get_entity(lookup).variant.(^Rigid_Body_Entity);

		rigid_body.velocity.y += GRAVITY * dt;
		rigid_body.new_position = rigid_body.position + rigid_body.velocity * dt;

		new_orientation := math2.integrate_angular_velocity(rigid_body.angular_velocity, rigid_body.orientation, dt);
		rigid_body.inv_global_inertia_tensor = math2.calculate_inv_global_inertia_tensor(new_orientation, rigid_body.inv_local_inertia_tensor);

		tentative_transform := linalg.matrix4_from_trs(rigid_body.new_position, new_orientation, rigid_body.size);
		rigid_body.tentative_transform = tentative_transform;
		move_rigid_body_tentatively_in_grid(&game.entity_grid, rigid_body);

		rigid_body.checked_collision = false;
		init_island(&game.islands, lookup, rigid_body);
	}

	if config.contact_point_helpers {
		clear_contact_helpers(&game.contact_helpers);
	}
	
	clear_constraints(&game.constraints);
	find_spring_constraints(&game.ground_grid, &game.entity_grid, &game.constraints, game.car, dt);
	
	entities_woken_up := make([dynamic]Entity_Lookup, context.temp_allocator);

	// Car collisions
	{
		// Ground collisions
		nearby_triangle_indices := ground_grid_find_nearby_triangles(&game.ground_grid, game.car.bounds);

		for provoking_hull in &game.car.collision_hulls {
			for nearby_triangle_index in nearby_triangle_indices {
				nearby_triangle := ground_grid_get_triangle(&game.ground_grid, nearby_triangle_index);

				if manifold, ok := evaluate_ground_collision(game.ground_grid.positions[:], nearby_triangle, &provoking_hull).?; ok {
					add_car_fixed_constraint_set(&game.constraints, game.car, &manifold, dt);
				}
			}
		}

		// Collisions with other hulls
		nearby_lookups := find_nearby_entities_in_grid(&game.entity_grid, game.car.bounds);

		for provoking_hull in &game.car.collision_hulls {
			for nearby_lookup in nearby_lookups {
				nearby_entity := get_entity(nearby_lookup);

				for nearby_hull in &nearby_entity.collision_hulls {
					if manifold, ok := evaluate_entity_collision(&provoking_hull, &nearby_hull).?; ok {
						switch e in nearby_entity.variant {
						case ^Rigid_Body_Entity:
							add_car_movable_constraint_set(&game.constraints, game.car, e, &manifold, dt);
							car_collision_maybe_wake_island(&game.islands, &entities_woken_up, e);
							handle_status_effects(game.car, e);
						case ^Inanimate_Entity:
							// This could be a fixed constraint that doesn't rotate the car. We'd just have to keep in mind what would happen when the car lands upside down on an inanimate entity.
							// Maybe we could add a normal constraint if there are no spring constraints so it still rolls over when landing upside down.
							add_car_fixed_constraint_set(&game.constraints, game.car, &manifold, dt);
						case ^Car_Entity:
							unreachable();
						}
					}
				}
			}
		}
	}

	// Rigid body collisions
	for provoking_lookup, provoking_lookup_index in game.awake_rigid_body_lookups {
		provoking_rigid_body := get_entity(provoking_lookup).variant.(^Rigid_Body_Entity);

		// Collisions with the ground
		nearby_triangle_indices := ground_grid_find_nearby_triangles(&game.ground_grid, provoking_rigid_body.bounds);

		for provoking_hull in &provoking_rigid_body.collision_hulls {
			for nearby_triangle_index in nearby_triangle_indices {
				nearby_triangle := ground_grid_get_triangle(&game.ground_grid, nearby_triangle_index);

				if manifold, ok := evaluate_ground_collision(game.ground_grid.positions[:], nearby_triangle, &provoking_hull).?; ok {
					process_rigid_body_ground_collision(provoking_rigid_body, provoking_hull.kind, &game.constraints, &manifold, dt, &game.contact_helpers);
				}
			}
		}

		// Collisions with other hulls
		nearby_lookups := find_nearby_entities_in_grid(&game.entity_grid, provoking_rigid_body.bounds);

		for provoking_hull in &provoking_rigid_body.collision_hulls {
			for nearby_lookup in nearby_lookups {
				if provoking_lookup == nearby_lookup do continue;

				nearby_entity := get_entity(nearby_lookup);

				if nearby_rigid_body, ok := nearby_entity.variant.(^Rigid_Body_Entity); ok {
					if nearby_rigid_body.checked_collision do continue;
					if provoking_rigid_body.collision_exclude && nearby_rigid_body.collision_exclude do continue;
				}

				for nearby_hull in &nearby_entity.collision_hulls {
					if manifold, ok := evaluate_entity_collision(&provoking_hull, &nearby_hull).?; ok {
						switch e in nearby_entity.variant {
						case ^Rigid_Body_Entity:
							add_movable_constraint_set(&game.constraints, provoking_rigid_body, e, &manifold, dt);
							rigid_body_collision_merge_islands(&game.islands, &entities_woken_up, provoking_lookup, provoking_rigid_body, e);
						case ^Inanimate_Entity:
							add_fixed_constraint_set(&game.constraints, provoking_rigid_body, provoking_hull.kind, &manifold, dt);
						case ^Car_Entity:
							unreachable();
						}
					}
				}
			}
		}

		provoking_rigid_body.checked_collision = true;
	}

	if config.island_helpers {
		update_island_helpers(&game.islands);
	}
	
	car := game.car;
	solve_constraints(&game.constraints, car, dt);

	{
		car.position += car.velocity * dt;
		car.orientation = math2.integrate_angular_velocity(car.angular_velocity, car.orientation, dt);

		update_entity_transform(car);
	}
	
	append(&game.awake_rigid_body_lookups, ..entities_woken_up[:]);
	
	// Clear the entities woken up from awake islands colliding with asleep islands. We'll reuse this array to keep track
	// of entities woken up from exploding barrels.
	clear(&entities_woken_up);

	for i := len(game.awake_rigid_body_lookups) - 1; i >= 0; i -= 1 {
		lookup := game.awake_rigid_body_lookups[i];
		rigid_body := get_entity(lookup).variant.(^Rigid_Body_Entity);

		if rigid_body.exploding_health > 0 {
			old_position := rigid_body.position;
			rigid_body.position += rigid_body.velocity * dt;

			rigid_body.orientation = math2.integrate_angular_velocity(rigid_body.angular_velocity, rigid_body.orientation, dt);
		
			update_entity_transform(rigid_body);

			if linalg.length2(rigid_body.position - old_position) < 0.00005 {
				rigid_body.sleep_duration += dt;
			} else {
				rigid_body.sleep_duration = 0;
			}

			rigid_body.checked_collision = false;
		} else {
			// Remove from entity grid
			remove_entity_from_grid(&game.entity_grid, rigid_body);

			// Remove from islands
			remove_rigid_body_from_island(&game.islands, lookup, rigid_body);

			// Remove from awake rigid body lookups
			unordered_remove(&game.awake_rigid_body_lookups, i);

			// Remove from status effects entities list
			switch rigid_body.status_effect {
			case .Shock, .ExplodingShock:
				remove_from_shock_entites(&game.shock_entities, lookup);
			case .Fire:
				unimplemented();
			case .None:
				unreachable();
			}

			// Rmove from entity geos
			remove_entity(lookup);

			// Find nearby entities and add an explosion velocity to them
			center := math2.box_center(rigid_body.bounds);
			bounds := math2.Box3f32 { center - 5, center + 5 };
			nearby_lookups := find_nearby_entities_in_grid(&game.entity_grid, bounds);

			for lookup in nearby_lookups {
				nearby_rigid_body, ok := get_entity(lookup).variant.(^Rigid_Body_Entity);
				if !ok do continue;

				dir := linalg.normalize(nearby_rigid_body.position - rigid_body.position);
				nearby_rigid_body.velocity += dir * 50;

				maybe_wake_island_post_solve(&game.islands, nearby_rigid_body, &entities_woken_up)
			}
		}
	}

	sleep_islands(&game.islands, &game.awake_rigid_body_lookups);
	append(&game.awake_rigid_body_lookups, ..entities_woken_up[:]);
}

process_rigid_body_ground_collision :: proc(
	provoking_rigid_body: ^Rigid_Body_Entity,
	provoking_hull_kind: Hull_Kind,
	constraints: ^Constraints,
	manifold: ^Contact_Manifold,
	dt: f32,
	contact_helpers: ^[dynamic]Geometry_Lookup,
) {
	if provoking_rigid_body.status_effect == .ExplodingShock {
		// Check if we already exploded the barrel so we don't try to do it twice
		if provoking_rigid_body.exploding_health <= 0 {
			return;
		}

		velocity_diff := abs(linalg.dot(manifold.normal, provoking_rigid_body.velocity));
		provoking_rigid_body.exploding_health -= velocity_diff;

		if provoking_rigid_body.exploding_health > 0 {
			add_fixed_constraint_set(constraints, provoking_rigid_body, provoking_hull_kind, manifold, dt);
			
			if config.contact_point_helpers {
				add_contact_helper(contact_helpers, manifold);
			}
		}
	} else {
		add_fixed_constraint_set(constraints, provoking_rigid_body, provoking_hull_kind, manifold, dt);

		if config.contact_point_helpers {
			add_contact_helper(contact_helpers, manifold);
		}
	}
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
SPRING_MAX_LENGTH: f32 : 0.8;

find_spring_constraints :: proc(ground_grid: ^Ground_Grid, entity_grid: ^Entity_Grid, constraints: ^Constraints, car: ^Car_Entity, dt: f32) {
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

	spring_wheel_point_fl := spring_body_point_fl + extension_dir * SPRING_MAX_LENGTH;
	spring_wheel_point_fr := spring_body_point_fr + extension_dir * SPRING_MAX_LENGTH;
	spring_wheel_point_bl := spring_body_point_bl + extension_dir * SPRING_MAX_LENGTH;
	spring_wheel_point_br := spring_body_point_br + extension_dir * SPRING_MAX_LENGTH;

	spring_bounds_fl := math2.Box3f32 {linalg.min(spring_body_point_fl, spring_wheel_point_fl), linalg.max(spring_body_point_fl, spring_wheel_point_fl)};
	spring_bounds_fr := math2.Box3f32 {linalg.min(spring_body_point_fr, spring_wheel_point_fr), linalg.max(spring_body_point_fr, spring_wheel_point_fr)};
	spring_bounds_bl := math2.Box3f32 {linalg.min(spring_body_point_bl, spring_wheel_point_bl), linalg.max(spring_body_point_bl, spring_wheel_point_bl)};
	spring_bounds_br := math2.Box3f32 {linalg.min(spring_body_point_br, spring_wheel_point_br), linalg.max(spring_body_point_br, spring_wheel_point_br)};

	spring_bounds := math2.box_union(spring_bounds_fl, spring_bounds_fr, spring_bounds_bl, spring_bounds_br);

	triangle_indices := ground_grid_find_nearby_triangles(ground_grid, spring_bounds);
	nearby_lookups := find_nearby_entities_in_grid(entity_grid, spring_bounds);

	manifold := Spring_Contact_Manifold {
		normal = -extension_dir,
	};

	spring_body_points := [?]linalg.Vector3f32 {spring_body_point_fl, spring_body_point_fr, spring_body_point_bl, spring_body_point_br};
	MAX_COLLISION_NORMAL_ANGLE: f32 : math.PI / 4;

	for spring_index in 0..<4 {
		best_spring_contact := Spring_Contact_Intermediary {
			length = max(f32),
		};

		spring_body_point := spring_body_points[spring_index];

		for triangle_index in triangle_indices {
			triangle := ground_grid_get_triangle(ground_grid, triangle_index);

			a_index := triangle.indices[0] * 3;
			b_index := triangle.indices[1] * 3;
			c_index := triangle.indices[2] * 3;

			positions := &ground_grid.positions;
			a := linalg.Vector3f32 {positions[a_index], positions[a_index + 1], positions[a_index + 2]};
			b := linalg.Vector3f32 {positions[b_index], positions[b_index + 1], positions[b_index + 2]};
			c := linalg.Vector3f32 {positions[c_index], positions[c_index + 1], positions[c_index + 2]};

			if contact, ok := spring_intersects_triangle(spring_body_point, extension_dir, a, b, c).?; ok {
				if math.acos(linalg.dot(-extension_dir, contact.normal)) > MAX_COLLISION_NORMAL_ANGLE {
					continue;
				}

				if contact.length < best_spring_contact.length {
					best_spring_contact = contact;
				}
			}
		}

		for nearby_lookup in nearby_lookups {
			nearby_entity := get_entity(nearby_lookup);

			for nearby_hull in &nearby_entity.collision_hulls {
				if !math2.box_intersects(spring_bounds, nearby_hull.global_bounds) do continue;

				if contact, ok := spring_intersects_hull(spring_body_point, extension_dir, &nearby_hull).?; ok {
					if math.acos(linalg.dot(-extension_dir, contact.normal)) > MAX_COLLISION_NORMAL_ANGLE {
						continue;
					}

					if contact.length < best_spring_contact.length {
						best_spring_contact = contact;
					}
				}
			}
		}

		wheel := &car.wheels[spring_index];
		wheel.body_point = spring_body_point;

		if best_spring_contact.length == max(f32) {
			wheel.contact_normal = nil;
			wheel.spring_length = SPRING_MAX_LENGTH;
		} else {
			small_array.append(&manifold.contacts, Spring_Contact {
				spring_body_point,
				best_spring_contact.length,
			});

			wheel.contact_normal = best_spring_contact.normal;
			wheel.spring_length = best_spring_contact.length;
		}
	}

	if small_array.len(manifold.contacts) > 0 {
		set_spring_constraint_set(constraints, car, &manifold, dt);
	}
}

Spring_Contact_Intermediary :: struct {
	normal: linalg.Vector3f32,
	length: f32,
}

spring_intersects_triangle :: proc(origin, direction: linalg.Vector3f32, a, b, c: linalg.Vector3f32) -> Maybe(Spring_Contact_Intermediary) {
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

	if dist <= 0 || dist > SPRING_MAX_LENGTH {
		return nil;
	}

	n := linalg.normalize(linalg.cross(ab, ac));
	return Spring_Contact_Intermediary {n, dist};
}

spring_intersects_hull :: proc(origin, direction: linalg.Vector3f32, hull: ^Collision_Hull) -> Maybe(Spring_Contact_Intermediary) {
	local_origin := math2.matrix4_transform_point(hull.inv_global_transform, origin);

	// If the hull has a scale this will not be normalized. I think normalizing it changes the "scale" or "reference view" of the t value
	// in the cylinder case so they are smaller than what they should be. That can probably be corrected somehow but this doesn't seem to
	// need to be normalized so we can simply leave it unnormalized.
	local_direction := math2.matrix4_transform_direction(hull.inv_global_transform, direction);

	local_normal: linalg.Vector3f32;
	length: f32 = max(f32);

	switch hull.kind {
	case .Box:
		// We could probably take another look at this and try to improve it. It would be nice if we could generate the faces to check.
		// Just remember, you cannot use the direction of the ray to derive the exact face the ray will pass through. You can use it
		// to find the faces which have normals poiting in the same direction.
		// Why are we doing best length here? The unbounded ray would pass through 2 faces but the backside is already being ignored.

		best_normal: linalg.Vector3f32;
		best_length := max(f32);
		
		face_normals :: [6]linalg.Vector3f32 {
			linalg.Vector3f32 {  1,  0,  0 },
			linalg.Vector3f32 { -1,  0,  0 },
			linalg.Vector3f32 {  0,  1,  0 },
			linalg.Vector3f32 {  0, -1,  0 },
			linalg.Vector3f32 {  0,  0,  1 },
			linalg.Vector3f32 {  0,  0, -1 },
		};

		for face_normal in face_normals {
			dot := linalg.dot(local_direction, face_normal);

			// If the dot product is greator than zero, the ray would pass through the backside.
			if dot >= 0 do continue;

			face_point := face_normal;
			t := linalg.dot((face_point - local_origin), face_normal) / dot;
			if abs(t) > SPRING_MAX_LENGTH do continue;
			p := local_origin + local_direction * t;
			intersecting := false;

			switch face_normal {
			case linalg.Vector3f32 { 1, 0, 0 }, linalg.Vector3f32 { -1, 0, 0 }:
				if p.z < 1 && p.z > -1 && p.y < 1 && p.y > -1 {
					intersecting = true;
				}
			
			case linalg.Vector3f32 { 0, 1, 0 }, linalg.Vector3f32 { 0, -1, 0 }:
				if p.x < 1 && p.x > -1 && p.z < 1 && p.z > -1 {
					intersecting = true;
				}
			
			case linalg.Vector3f32 { 0, 0, 1 }, linalg.Vector3f32 { 0, 0, -1 }:
				if p.x < 1 && p.x > -1 && p.y < 1 && p.y > -1 {
					intersecting = true;
				}

			case:
				unreachable();
			}

			if intersecting && t < best_length {
				best_normal = face_normal;
				best_length = t;
			}
		}

		if best_length != max(f32) {
			local_normal = best_normal;
			length = best_length;
		}

	case .Cylinder:
		s := local_origin;
		e := local_origin + local_direction * SPRING_MAX_LENGTH;

		top_bot: {
			// If the y value of the ray is 0 then it's horizontal.
			if local_direction.y == 0 do break top_bot;

			y := math.sign(local_direction.y);
			depth_s := abs(s.y) - 1; // The - 1 is the distance to the horizontal plane
			depth_e := abs(e.y) - 1;

			if depth_s * depth_e < 0 {
				t := depth_s / (depth_s - depth_e);
				p := s + local_direction * t;

				if p.x * p.x + p.z * p.z >= 1 do break top_bot;
				
				local_normal = linalg.Vector3f32 {0, -y, 0};
				length = t;
				break;
			}
		}

		sides: {
			// If the y value of the ray is 1 or -1 then it's vertical.
			if abs(local_direction.y) == 1 do break sides;

			v := local_direction;
			a := v.x * v.x + v.z * v.z;
			b := 2 * s.x * v.x + 2 * s.z * v.z;
			c := s.x * s.x + s.z * s.z - 1;

			j := b * b - 4 * a * c;
			if j < 0 do break sides;
			k := math.sqrt(b * b - 4 * a * c);
			q := 2 * a;

			t1 := (-b + k) / q;
			t2 := (-b - k) / q;
			t := min(t1, t2);

			if t <= 0 || t >= SPRING_MAX_LENGTH {
				break sides;
			}

			p := s + t * v;
			if abs(p.y) >= 1 do break sides;

			local_normal = linalg.Vector3f32 {p.x, 0, p.z};
			length = t;
		}

	case .Mesh:
		unimplemented();
	}

	if length == max(f32) {
		return nil;
	} else {
		global_normal := linalg.normalize(math2.matrix4_transform_direction(hull.global_transform, local_normal));
		return Spring_Contact_Intermediary { global_normal, length };
	}
}

@(private="file")
handle_status_effects :: proc(car: ^Car_Entity, rigid_body: ^Rigid_Body_Entity) {
	#partial switch rigid_body.status_effect {
	case .Shock, .ExplodingShock:
		shock_car(car);
	case .Fire:
		light_car_on_fire(car);
	}
}

clear_contact_helpers :: proc(contact_helpers: ^[dynamic]Geometry_Lookup) {
	for lookup in contact_helpers {
		remove_geometry(lookup);
	}

	clear(contact_helpers);
}

add_contact_helper :: proc(contact_helpers: ^[dynamic]Geometry_Lookup, manifold: ^Contact_Manifold) {
	for contact in small_array.slice(&manifold.contacts) {
		geo := init_line_helper("contact_helper", contact.position_b, manifold.normal * 3);
		geo_lookup := add_geometry(geo, .KeepRender);
		append(contact_helpers, geo_lookup);
	}
}