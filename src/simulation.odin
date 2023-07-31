package main;

import "core:math";
import "core:math/linalg";
import "core:container/small_array";
import "core:slice";
import "core:math/rand";
import "math2";

GRAVITY: f32 : -20.0;
EXPLOSION_RADIUS :: 10;

simulate :: proc(car: ^Car_Entity, scene: ^Scene, runtime_assets: ^Runtime_Assets, dt: f32) {
	{ // Tentatively step the car forward
		car.velocity.y += GRAVITY * dt;
		car.tentative_position = car.position + car.velocity * dt;

		tentative_orientation := math2.integrate_angular_velocity(car.angular_velocity, car.orientation, dt);
		car.tentative_inv_global_inertia_tensor = math2.calculate_inv_global_inertia_tensor(tentative_orientation, CAR_INV_LOCAL_INERTIA_TENSOR);

		car.tentative_transform = linalg.matrix4_from_trs(car.tentative_position, tentative_orientation, linalg.Vector3f32 {1, 1, 1});

		update_entity_hull_transforms_and_bounds(car, tentative_orientation, car.tentative_transform);
	}

	clear_islands(&scene.islands);

	for lookup in scene.awake_rigid_bodies {
		rigid_body := get_entity(lookup).variant.(^Rigid_Body_Entity);

		rigid_body.velocity.y += GRAVITY * dt;
		rigid_body.tentative_position = rigid_body.position + rigid_body.velocity * dt;

		rigid_body.tentative_orientation = math2.integrate_angular_velocity(rigid_body.angular_velocity, rigid_body.orientation, dt);
		rigid_body.tentative_inv_global_inertia_tensor = math2.calculate_inv_global_inertia_tensor(rigid_body.tentative_orientation, rigid_body.inv_local_inertia_tensor);

		rigid_body.tentative_transform = linalg.matrix4_from_trs(rigid_body.tentative_position, rigid_body.tentative_orientation, rigid_body.size);
		entity_grid_move_rigid_body_tentatively(&scene.entity_grid, lookup, rigid_body);

		rigid_body.checked_collision = false;
		init_island(&scene.islands, lookup, rigid_body);
	}

	if config.contact_point_helpers {
		clear_contact_helpers(&scene.contact_helpers);
	}
	
	clear_constraints(&scene.constraints);
	find_car_spring_constraints_and_surface_type(&scene.ground_grid, &scene.entity_grid, &scene.constraints, car, dt, scene.oil_slicks[:]);
	
	additional_awake_entities := make([dynamic]Entity_Lookup, context.temp_allocator);

	{ // Car collisions
		provoking_hull := &car.collision_hulls[0];

		// Ground collisions
		nearby_triangle_indices := ground_grid_find_nearby_triangles(&scene.ground_grid, car.bounds);

		for &provoking_hull in car.collision_hulls {
			for nearby_triangle_index in nearby_triangle_indices {
				nearby_triangle := ground_grid_form_triangle(&scene.ground_grid, nearby_triangle_index);

				if manifold, ok := evaluate_ground_collision(scene.ground_grid.positions[:], &nearby_triangle, &provoking_hull).?; ok {
					add_car_fixed_constraint_set(&scene.constraints, car, &manifold, dt);
				}
			}
		}

		// Collisions with other hulls
		nearby_lookups := entity_grid_find_nearby_entities(&scene.entity_grid, car.bounds);

		for nearby_lookup in nearby_lookups {
			nearby_entity := get_entity(nearby_lookup);

			for nearby_hull in &nearby_entity.collision_hulls {
				simplex, colliding := hulls_colliding(provoking_hull, &nearby_hull).?;
				if !colliding do continue;

				switch e in nearby_entity.variant {
				case ^Cloud_Entity:
					shock_car(car);
					continue;

				case ^Bumper_Entity:
					// #todo Should there be an explosion constraint? I.e. a constraint that tries to get the car to a target velocity? (Is this what a motor constraint is?)
					dir := linalg.normalize(car.position - e.position);
					car.velocity = dir * 30;

					e.animating = true;
					e.animation_duration = 0;
					continue;
				
				case ^Boost_Jet_Entity:
					dir := linalg.normalize(math2.matrix4_forward(e.transform));
					car.velocity += dir * 150 * dt;
					continue;

				case ^Car_Entity, ^Oil_Slick_Entity:
					unreachable();

				case ^Inanimate_Entity, ^Rigid_Body_Entity:
				}

				manifold, has_manifold := hulls_find_collision_manifold(provoking_hull, &nearby_hull, simplex).?;
				if !has_manifold do continue;

				switch e in nearby_entity.variant {
				case ^Rigid_Body_Entity:
					add_car_movable_constraint_set(&scene.constraints, car, e, &manifold, dt);
					car_collision_maybe_wake_island(&scene.islands, &additional_awake_entities, e);
					handle_status_effects(car, e);

				case ^Inanimate_Entity:
					// This could be a fixed constraint that doesn't rotate the car. We'd just have to keep in mind what would happen when the car lands upside down on an inanimate entity.
					// Maybe we could add a normal constraint if there are no spring constraints so it still rolls over when landing upside down.
					add_car_fixed_constraint_set(&scene.constraints, car, &manifold, dt);

				case ^Car_Entity, ^Cloud_Entity, ^Oil_Slick_Entity, ^Bumper_Entity, ^Boost_Jet_Entity:
					unreachable();
				}
			}
		}
	}

	// Rigid body collisions
	for provoking_lookup, provoking_lookup_index in scene.awake_rigid_bodies {
		provoking_rigid_body := get_entity(provoking_lookup).variant.(^Rigid_Body_Entity);

		// Collisions with the ground
		nearby_triangle_indices := ground_grid_find_nearby_triangles(&scene.ground_grid, provoking_rigid_body.bounds);

		for provoking_hull in &provoking_rigid_body.collision_hulls {
			for nearby_triangle_index in nearby_triangle_indices {
				nearby_triangle := ground_grid_form_triangle(&scene.ground_grid, nearby_triangle_index);

				if manifold, ok := evaluate_ground_collision(scene.ground_grid.positions[:], &nearby_triangle, &provoking_hull).?; ok {
					process_rigid_body_ground_collision(provoking_rigid_body, provoking_hull.kind, &scene.constraints, &manifold, dt, &scene.contact_helpers);
				}
			}
		}

		// Collisions with other hulls
		nearby_lookups := entity_grid_find_nearby_entities(&scene.entity_grid, provoking_rigid_body.bounds);

		for provoking_hull in &provoking_rigid_body.collision_hulls {
			for nearby_lookup in nearby_lookups {
				if provoking_lookup == nearby_lookup do continue;

				nearby_entity := get_entity(nearby_lookup);

				if nearby_rigid_body, ok := nearby_entity.variant.(^Rigid_Body_Entity); ok {
					if nearby_rigid_body.checked_collision do continue;
					if provoking_rigid_body.collision_exclude && nearby_rigid_body.collision_exclude do continue;
				}

				for nearby_hull in &nearby_entity.collision_hulls {
					simplex, colliding := hulls_colliding(&provoking_hull, &nearby_hull).?;
					if !colliding do continue;

					if _, is_cloud_entity := nearby_entity.variant.(^Cloud_Entity); is_cloud_entity {
						continue;
					}

					manifold, has_manifold := hulls_find_collision_manifold(&provoking_hull, &nearby_hull, simplex).?;
					if !has_manifold do continue;

					switch e in nearby_entity.variant {
					case ^Rigid_Body_Entity:
						add_movable_constraint_set(&scene.constraints, provoking_rigid_body, e, &manifold, dt);
						rigid_body_collision_merge_islands(&scene.islands, &additional_awake_entities, provoking_lookup, provoking_rigid_body, e);
					
					case ^Inanimate_Entity:
						add_fixed_constraint_set(&scene.constraints, provoking_rigid_body, provoking_hull.kind, &manifold, dt);
					
					case ^Car_Entity, ^Oil_Slick_Entity:
						unreachable();
					
					case ^Cloud_Entity:
						unimplemented();

					case ^Boost_Jet_Entity:
						dir := linalg.normalize(math2.matrix4_forward(e.transform));
						provoking_rigid_body.velocity += dir * 50 * dt;

					case ^Bumper_Entity:
						dir := linalg.normalize(provoking_rigid_body.position - e.position);
						provoking_rigid_body.velocity = dir * 30;

						e.animating = true;
						e.animation_duration = 0;
					}
				}
			}
		}

		provoking_rigid_body.checked_collision = true;
	}

	if config.island_helpers {
		update_island_helpers(&scene.islands);
	}
	
	solve_constraints(&scene.constraints, car, dt);

	{
		car.position += (car.velocity + car.bias_velocity) * dt;
		car.orientation = math2.integrate_angular_velocity(car.angular_velocity + car.bias_angular_velocity, car.orientation, dt);

		car.bias_velocity = VEC3_ZERO;
		car.bias_angular_velocity = VEC3_ZERO;

		update_entity_transform(car);
	}
	
	append(&scene.awake_rigid_bodies, ..additional_awake_entities[:]);
	
	// Clear the entities woken up from awake islands colliding with asleep islands. We'll reuse this array to keep track
	// of entities woken up from exploding barrels.
	clear(&additional_awake_entities);

	for i := len(scene.awake_rigid_bodies) - 1; i >= 0; i -= 1 {
		lookup := scene.awake_rigid_bodies[i];
		rigid_body := get_entity(lookup).variant.(^Rigid_Body_Entity);

		if rigid_body.exploding_health > 0 {
			old_position := rigid_body.position;
			rigid_body.position += (rigid_body.velocity + rigid_body.bias_velocity) * dt;

			rigid_body.orientation = math2.integrate_angular_velocity(rigid_body.angular_velocity + rigid_body.bias_angular_velocity, rigid_body.orientation, dt);

			rigid_body.bias_velocity = VEC3_ZERO;
			rigid_body.bias_angular_velocity = VEC3_ZERO;
		
			update_entity_transform(rigid_body);

			if linalg.length2(rigid_body.position - old_position) < 0.00005 {
				rigid_body.sleep_duration += dt;
			} else {
				rigid_body.sleep_duration = 0;
			}

			rigid_body.checked_collision = false;
		} else {
			// Remove from entity grid
			// remove_entity_from_grid(&game.entity_grid, lookup, rigid_body);
			entity_grid_remove(&scene.entity_grid, lookup, rigid_body);

			// Remove from islands
			remove_rigid_body_from_island(&scene.islands, lookup, rigid_body);

			// Remove from awake rigid body lookups
			unordered_remove(&scene.awake_rigid_bodies, i);

			// Remove from status effects entities list
			switch rigid_body.status_effect {
			case .ExplodingShock:
				i, ok := slice.linear_search(scene.shock_entities[:], lookup);
				assert(ok);
				unordered_remove(&scene.shock_entities, i);
			case .ExplodingFire:
				i, ok := slice.linear_search(scene.fire_entities[:], lookup);
				assert(ok);
				unordered_remove(&scene.fire_entities, i);
			case .None, .Shock, .Fire:
				unreachable();
			}

			// Create explosion bounds
			center := math2.box_center(rigid_body.bounds);
			bounds := math2.Box3f32 { center - EXPLOSION_RADIUS, center + EXPLOSION_RADIUS };
			
			// Appy explosion impulse to car if nearby
			if math2.box_intersects(bounds, car.bounds) {
				dir := linalg.normalize(car.position - rigid_body.position);
				car.velocity += dir * 30;
			}
			
			// Apply explosion impulse to nearby rigid bodies
			// nearby_lookups := find_nearby_entities_in_grid(&game.entity_grid, bounds);
			nearby_lookups := entity_grid_find_nearby_entities(&scene.entity_grid, bounds);

			for lookup in nearby_lookups {
				nearby_rigid_body, ok := get_entity(lookup).variant.(^Rigid_Body_Entity);
				if !ok do continue;

				dir := linalg.normalize(nearby_rigid_body.position - rigid_body.position);
				nearby_rigid_body.velocity += dir * 30;

				maybe_wake_island_post_solve(&scene.islands, nearby_rigid_body, &additional_awake_entities)
			}

			// Spawn shrapnel pieces
			for shrapnel in &runtime_assets.shock_barrel_shrapnel {
				shrapnel_rigid_body, shrapnel_lookup := create_entity("shrapnel", shrapnel.geometry_lookup, Rigid_Body_Entity);
				shrapnel_rigid_body.scene_associated = true;

				shrapnel_rigid_body.position = math2.matrix4_transform_point(rigid_body.transform, shrapnel.position);
				shrapnel_rigid_body.orientation = rigid_body.orientation * shrapnel.orientation;
				shrapnel_rigid_body.size = rigid_body.size * shrapnel.size;
				shrapnel_rigid_body.collision_exclude = true;

				init_rigid_body_entity(shrapnel_rigid_body, 1, shrapnel.dimensions);
				update_entity_transform(shrapnel_rigid_body);

				hull := init_collision_hull(shrapnel.hull_local_position, shrapnel.hull_local_orientation, shrapnel.hull_local_size, .Box);
				append(&shrapnel_rigid_body.collision_hulls, hull);
				update_entity_hull_transforms_and_bounds(shrapnel_rigid_body, shrapnel_rigid_body.orientation, shrapnel_rigid_body.transform);
				entity_grid_insert(&scene.entity_grid, shrapnel_lookup, shrapnel_rigid_body);

				append(&additional_awake_entities, shrapnel_lookup);
				
				dir := linalg.normalize(shrapnel_rigid_body.position - rigid_body.position);
				shrapnel_rigid_body.velocity = dir * 30;
			}
			
			switch rigid_body.status_effect {
			case .ExplodingShock:
				cloud, cloud_lookup := create_entity("shock cloud", nil, Cloud_Entity);
				cloud.scene_associated = true;
				cloud.position = rigid_body.position;
				cloud.status_effect =.Shock;
				update_entity_transform(cloud);


				HULL_POSITION :: linalg.Vector3f32 {0, 0.5, 0};
				HULL_SIZE :: linalg.Vector3f32 {4, 2, 4};

				hull := init_collision_hull(HULL_POSITION, linalg.QUATERNIONF32_IDENTITY, HULL_SIZE, .Sphere);
				append(&cloud.collision_hulls, hull);
				update_entity_hull_transforms_and_bounds(cloud, cloud.orientation, cloud.transform);
				entity_grid_insert(&scene.entity_grid, cloud_lookup, cloud);

				append(&scene.status_effect_clouds, cloud_lookup);
			
			case .ExplodingFire:
				// #performance: There is some code in here that iterates over all the oil slicks. We could use some spatial partitioning
				// data structure to make that more efficient. All or most of this could also be done in a separate thread. The types of
				// things in here don't need to be done all in a frame. They could finish in some time and they we display the results. It
				// takes time for oil slick blobs to hit the floor so I think it would be fine.

				{ // Light nearby oil slicks on fire
					center := math2.box_center(rigid_body.bounds);
					explosion_bounds := math2.Box3f32 { center - EXPLOSION_RADIUS, center + EXPLOSION_RADIUS };

					for oil_slick_lookup in scene.oil_slicks {
						oil_slick := get_entity(oil_slick_lookup).variant.(^Oil_Slick_Entity);

						if math2.box_intersects(oil_slick.bounds, explosion_bounds) {
							oil_slick.on_fire = true;
							append(&scene.on_fire_oil_slicks, oil_slick_lookup);
						}
					}
				}

				origin := rigid_body.position + linalg.Vector3f32 {0, 3, 0};

				HEIGHT :: 10;
				RADIUS :: 8;

				bounds := math2.Box3f32 {
					origin - linalg.Vector3f32 { RADIUS, HEIGHT, RADIUS },
					origin + linalg.Vector3f32 { RADIUS, 0, RADIUS },
				};

				if config.explosion_helpers {
					geometry, _ := create_geometry("explosion helper", .KeepRender);
					geometry_make_box_helper(geometry, bounds.min, bounds.max);
				}

				ground_triangle_indices := ground_grid_find_nearby_triangles(&scene.ground_grid, bounds);

				SQUARES :: 4;
				for x in 0..<SQUARES {
					for z in 0..<SQUARES {
						SQUARE_SIZE: f32 : f32(RADIUS * 2) / f32(SQUARES);

						// Skip the squares whos centers are oustide the circle
						square_center_x := -RADIUS + (SQUARE_SIZE / 2) + SQUARE_SIZE * f32(x);
						square_center_z := -RADIUS + (SQUARE_SIZE / 2) + SQUARE_SIZE * f32(z);
						if square_center_x * square_center_x + square_center_z * square_center_z > RADIUS * RADIUS {
							continue;
						}

						x := rand.float32() * SQUARE_SIZE + bounds.min.x + f32(x) * SQUARE_SIZE;
						z := rand.float32() * SQUARE_SIZE + bounds.min.z + f32(z) * SQUARE_SIZE;
						y := bounds.min.y
						p := linalg.Vector3f32 { x, y, z };

						for ground_triangle_index in ground_triangle_indices {
							segment := p - origin;
							ray_direction := linalg.normalize(p - origin);
							ray_length := linalg.length(segment);

							ground_triangle := ground_grid_form_triangle(&scene.ground_grid, ground_triangle_index);

							intersection_length := math2.ray_intersects_triangle(origin, ray_direction, ground_triangle.a, ground_triangle.b, ground_triangle.c);
							if intersection_length <= 0 || intersection_length > ray_length {
								continue;
							}
							
							if config.explosion_helpers {
								geometry, _ := create_geometry("explosion helper", .KeepRender);
								geometry_make_line_helper(geometry, origin, segment);
							}

							intersection_point := origin + ray_direction * intersection_length;
							i := rand.int_max(len(runtime_assets.oil_slicks));
							oil_slick_asset := &runtime_assets.oil_slicks[i];

							oil_slick_entity, oil_slick_entity_lookup := create_entity("oil slick", oil_slick_asset.geometry_lookup, Oil_Slick_Entity);
							oil_slick_entity.scene_associated = true;
							
							orientation := linalg.quaternion_between_two_vector3(linalg.VECTOR3F32_Y_AXIS, ground_triangle.normal);

							oil_slick_entity.position = intersection_point;
							oil_slick_entity.orientation = orientation;
							oil_slick_entity.on_fire = true;
							oil_slick_entity.desired_fire_particles = 13;
							update_entity_transform(oil_slick_entity);
							
							hull_indices_copy := slice.clone_to_dynamic(oil_slick_asset.hull_indices[:]);
							hull_positions_copy := slice.clone_to_dynamic(oil_slick_asset.hull_positions[:]);
							hull := init_collision_hull(oil_slick_asset.hull_local_position, oil_slick_asset.hull_local_orientation, oil_slick_asset.hull_local_size, .Mesh, hull_indices_copy, hull_positions_copy);
							append(&oil_slick_entity.collision_hulls, hull);

							update_entity_hull_transforms_and_bounds(oil_slick_entity, oil_slick_entity.orientation, oil_slick_entity.transform);
							append(&scene.oil_slicks, oil_slick_entity_lookup);
							append(&scene.on_fire_oil_slicks, oil_slick_entity_lookup);

							break;
						}
					}
				}

			case .None, .Shock, .Fire:
				unreachable();
			}

			// Rmove from entity geos
			remove_entity(lookup);
		}
	}

	sleep_islands(&scene.islands, &scene.awake_rigid_bodies);
	append(&scene.awake_rigid_bodies, ..additional_awake_entities[:]);
}

process_rigid_body_ground_collision :: proc(
	provoking_rigid_body: ^Rigid_Body_Entity,
	provoking_hull_kind: Hull_Kind,
	constraints: ^Constraints,
	manifold: ^Contact_Manifold,
	dt: f32,
	contact_helpers: ^[dynamic]Geometry_Lookup,
) {
	status_effect := provoking_rigid_body.status_effect;
	if status_effect == .ExplodingShock || status_effect == .ExplodingFire {
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

Spring_Contact_Intermediary :: struct {
	length: f32,
	normal: linalg.Vector3f32,
}

SPRING_BODY_POINT_Z: f32 : 1.1;
SPRING_MAX_LENGTH: f32 : 0.8;

find_car_spring_constraints_and_surface_type :: proc(ground_grid: ^Ground_Grid, entity_grid: ^Entity_Grid, constraints: ^Constraints, car: ^Car_Entity, dt: f32, oil_slicks: []Entity_Lookup) {
	extension_dir := -math2.matrix4_up(car.tentative_transform);

	SPRING_BODY_POINT_X: f32 : 0.8;
	SPRING_BODY_POINT_Y: f32 : 0.35

	SPRING_BODY_POINT_LOCAL_FL :: linalg.Vector3f32 { SPRING_BODY_POINT_X, -SPRING_BODY_POINT_Y,  SPRING_BODY_POINT_Z};
	SPRING_BODY_POINT_LOCAL_FR :: linalg.Vector3f32 {-SPRING_BODY_POINT_X, -SPRING_BODY_POINT_Y,  SPRING_BODY_POINT_Z};
	SPRING_BODY_POINT_LOCAL_BL :: linalg.Vector3f32 { SPRING_BODY_POINT_X, -SPRING_BODY_POINT_Y, -SPRING_BODY_POINT_Z};
	SPRING_BODY_POINT_LOCAL_BR :: linalg.Vector3f32 {-SPRING_BODY_POINT_X, -SPRING_BODY_POINT_Y, -SPRING_BODY_POINT_Z};

	spring_body_point_fl := math2.matrix4_transform_point(car.tentative_transform, SPRING_BODY_POINT_LOCAL_FL);
	spring_body_point_fr := math2.matrix4_transform_point(car.tentative_transform, SPRING_BODY_POINT_LOCAL_FR);
	spring_body_point_bl := math2.matrix4_transform_point(car.tentative_transform, SPRING_BODY_POINT_LOCAL_BL);
	spring_body_point_br := math2.matrix4_transform_point(car.tentative_transform, SPRING_BODY_POINT_LOCAL_BR);

	spring_wheel_point_fl := spring_body_point_fl + extension_dir * SPRING_MAX_LENGTH;
	spring_wheel_point_fr := spring_body_point_fr + extension_dir * SPRING_MAX_LENGTH;
	spring_wheel_point_bl := spring_body_point_bl + extension_dir * SPRING_MAX_LENGTH;
	spring_wheel_point_br := spring_body_point_br + extension_dir * SPRING_MAX_LENGTH;

	spring_bounds_fl := math2.Box3f32 {linalg.min(spring_body_point_fl, spring_wheel_point_fl), linalg.max(spring_body_point_fl, spring_wheel_point_fl)};
	spring_bounds_fr := math2.Box3f32 {linalg.min(spring_body_point_fr, spring_wheel_point_fr), linalg.max(spring_body_point_fr, spring_wheel_point_fr)};
	spring_bounds_bl := math2.Box3f32 {linalg.min(spring_body_point_bl, spring_wheel_point_bl), linalg.max(spring_body_point_bl, spring_wheel_point_bl)};
	spring_bounds_br := math2.Box3f32 {linalg.min(spring_body_point_br, spring_wheel_point_br), linalg.max(spring_body_point_br, spring_wheel_point_br)};

	spring_bounds := math2.box_union(spring_bounds_fl, spring_bounds_fr, spring_bounds_bl, spring_bounds_br);

	nearby_triangle_indices := ground_grid_find_nearby_triangles(ground_grid, spring_bounds);
	nearby_lookups := entity_grid_find_nearby_entities(entity_grid, spring_bounds);

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

		for nearby_triangle_index in nearby_triangle_indices {
			nearby_triangle := ground_grid_form_triangle(ground_grid, nearby_triangle_index);

			intersection_length := math2.ray_intersects_triangle(spring_body_point, extension_dir, nearby_triangle.a, nearby_triangle.b, nearby_triangle.c);
			if intersection_length <= 0 || intersection_length > SPRING_MAX_LENGTH {
				continue;
			}

			if math.acos(linalg.dot(-extension_dir, nearby_triangle.normal)) > MAX_COLLISION_NORMAL_ANGLE {
				continue;
			}

			if intersection_length < best_spring_contact.length {
				best_spring_contact = Spring_Contact_Intermediary {
					intersection_length,
					nearby_triangle.normal,
				};
			}
		}

		for nearby_lookup in nearby_lookups {
			nearby_entity := get_entity(nearby_lookup);

			if _, is_cloud_entity := nearby_entity.variant.(^Cloud_Entity); is_cloud_entity {
				continue;
			}

			switch _ in nearby_entity.variant {
			case ^Rigid_Body_Entity, ^Cloud_Entity, ^Oil_Slick_Entity, ^Bumper_Entity, ^Boost_Jet_Entity:
				continue;

			case ^Car_Entity:
				unreachable();

			case ^Inanimate_Entity:
			}

			for nearby_hull in &nearby_entity.collision_hulls {
				if !math2.box_intersects(spring_bounds, nearby_hull.global_bounds) {
					continue;
				}

				contact, ok := spring_intersects_hull(spring_body_point, extension_dir, &nearby_hull).?;
				if !ok {
					continue;
				}

				if math.acos(linalg.dot(-extension_dir, contact.normal)) > MAX_COLLISION_NORMAL_ANGLE {
					continue;
				}

				if contact.length < best_spring_contact.length {
					best_spring_contact = contact;
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

	car.surface_type = .Normal;

	if small_array.len(manifold.contacts) > 0 {
		set_spring_constraint_set(constraints, car, &manifold, dt);

		// Check if car is on an oil slick
		probe_start := car.position + extension_dir * SPRING_BODY_POINT_Y;
		probe_end := probe_start + extension_dir * SPRING_MAX_LENGTH;
		
		probe_bounds_min := linalg.min(probe_start, probe_end);
		probe_bounds_max := linalg.max(probe_start, probe_end);
		probe_bounds := math2.Box3f32 { probe_bounds_min, probe_bounds_max };

		// #performance
		// Here, we're iterating over all the oil slicks and doing AABB checks against the oil slick probe. Perhaps we could use
		// a spacial grid to only iterate over the nearby ones.
		oil_slick_loop: for oil_slick_lookup in oil_slicks {
			oil_slick := get_entity(oil_slick_lookup).variant.(^Oil_Slick_Entity);

			if math2.box_intersects(probe_bounds, oil_slick.bounds) {
				oil_slick_hull := &oil_slick.collision_hulls[0];
				indices := &oil_slick_hull.indices;
				positions := &oil_slick_hull.positions;

				for triangle_index in 0..<len(indices) / 3 {
					a, b, c := math2.triangle_index_to_points(triangle_index, indices[:], positions[:]);

					global_a := math2.matrix4_transform_point(oil_slick_hull.global_transform, a);
					global_b := math2.matrix4_transform_point(oil_slick_hull.global_transform, b);
					global_c := math2.matrix4_transform_point(oil_slick_hull.global_transform, c);

					intersection_length := math2.ray_intersects_triangle(probe_start, extension_dir, global_a, global_b, global_c);
					if intersection_length <= 0 || intersection_length > SPRING_MAX_LENGTH {
						continue;
					}

					car.surface_type = .Oil;

					if oil_slick.on_fire {
						light_car_on_fire(car);
					}
					
					break oil_slick_loop;
				}
			}
		}
	}
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
			{  1,  0,  0 },
			{ -1,  0,  0 },
			{  0,  1,  0 },
			{  0, -1,  0 },
			{  0,  0,  1 },
			{  0,  0, -1 },
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
			case { 1, 0, 0 }, { -1, 0, 0 }:
				if p.z < 1 && p.z > -1 && p.y < 1 && p.y > -1 {
					intersecting = true;
				}
			
			case { 0, 1, 0 }, { 0, -1, 0 }:
				if p.x < 1 && p.x > -1 && p.z < 1 && p.z > -1 {
					intersecting = true;
				}
			
			case { 0, 0, 1 }, { 0, 0, -1 }:
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
				
				local_normal = { 0, -y, 0 };
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

			local_normal = { p.x, 0, p.z };
			length = t;
		}
	
	case .Sphere:
		unreachable();

	case .Mesh:
		unimplemented();
	}

	if length == max(f32) {
		return nil;
	} else {
		global_normal := linalg.normalize(math2.matrix4_transform_direction(hull.global_transform, local_normal));
		return Spring_Contact_Intermediary { length, global_normal };
	}
}

@(private="file")
handle_status_effects :: proc(car: ^Car_Entity, rigid_body: ^Rigid_Body_Entity) {
	switch rigid_body.status_effect {
	case .Shock, .ExplodingShock:
		shock_car(car);
	case .Fire, .ExplodingFire:
		light_car_on_fire(car);
	case .None:
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
		geometry, geometry_lookup := create_geometry("contact helper", .KeepRender);
		geometry_make_line_helper(geometry, contact.position_b, manifold.normal * 3);
		append(contact_helpers, geometry_lookup);
	}
}