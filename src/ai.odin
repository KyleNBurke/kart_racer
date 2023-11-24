package main;

import "core:math";
import "core:math/linalg";
import "core:thread";
import "core:sync";
import "core:slice";
import "math2";

import "core:fmt";

AI :: struct {
	thread: ^thread.Thread,
	semaphore: sync.Sema,
	elapsed_time: f32,
	left_path: [dynamic]Curve,
	right_path: [dynamic]Curve,
}

Curve :: struct {
	p0, p1, p2, p3: linalg.Vector3f32,
	length: f32,
}

Zone :: struct {
	start: bool,
	over_edge: bool,
	angle: f32,
}

RAY_COUNT :: 8;

calculate_curve_lengths :: proc(curves: []Curve) {
	INC :: 100;

	for &curve in curves {
		total_len: f32 = 0;
		p0 := curve.p0;
		p1: linalg.Vector3f32;

		for i in 1..<INC {
			t := f32(i) / (INC - 1);
			p1 = find_point_on_curve(&curve, t);
			total_len += linalg.length(p1 - p0);
			p0 = p1;
		}

		curve.length = total_len;
	}
}

ai_signal_update_if_ready :: proc(ai: ^AI, dt: f32) {
	UPDATE_INTERVAL: f32 : 1 / 30;

	ai.elapsed_time += dt;

	if ai.elapsed_time >= UPDATE_INTERVAL {
		sync.sema_post(&ai.semaphore);
		ai.elapsed_time = 0;
	}
}

ai_init :: proc(scene: ^Scene) {
	scene.ai.thread = thread.create_and_start_with_data(scene, ai_update_players);
}

ai_debug_cleanup :: proc(ai: ^AI) {
	thread.terminate(ai.thread, 0);
	thread.destroy(ai.thread);
	
	delete(ai.left_path);
	delete(ai.right_path);
}

ai_update_players :: proc(scene: rawptr) {
	scene := cast(^Scene) scene;
	ai := &scene.ai;
	
	for {
		sync.sema_wait(&ai.semaphore);
		
		for lookup in scene.all_players[1:] {
			update_player(lookup, ai.left_path[:], ai.right_path[:], &scene.entity_grid);
		}
	}
}

@(private = "file")
update_player :: proc(player_lookup: Entity_Lookup, left_path, right_path: []Curve, entity_grid: ^Entity_Grid) {
	car := get_entity(player_lookup).variant.(^Car_Entity);

	if car.surface_normal == 0 {
		return;
	}

	car_left := math2.matrix4_left(car.transform);
	surface_forward := linalg.normalize(linalg.cross(car_left, car.surface_normal)); // #todo: Do once
	origin := car.position + surface_forward * 0.8;
	car.surface_forward = surface_forward;
	car.origin = origin;

	// Find extended point
	target_point, sharpness := find_target_point_on_path(origin, left_path, right_path, car);

	MAX_ANGLE :: 0.8;
	
	// Find nearby entities
	nearby_lookups: [dynamic]Entity_Lookup;
	{
		RAY_LEN :: 20;
		forward := origin + surface_forward * RAY_LEN;

		max_l_dir := math2.vector3_rotate(surface_forward, car.surface_normal, MAX_ANGLE);
		max_r_dir := math2.vector3_rotate(surface_forward, car.surface_normal, -MAX_ANGLE);
		max_l := origin + max_l_dir * RAY_LEN;
		max_r := origin + max_r_dir * RAY_LEN;
		car.max_l = max_l;
		car.max_r = max_r;

		bounds := math2.Box3f32 {
			math2.vector3_min(origin, forward, max_l, max_r),
			math2.vector3_max(origin, forward, max_l, max_r),
		};

		car.ray_bounds = bounds;

		// #todo: This query is returning back the human player car at the beggining, need to look into that.
		nearby_lookups = entity_grid_find_nearby_entities(entity_grid, bounds);
	}

	// Find all zones within the cone of the player
	zones := make([dynamic]Zone, context.temp_allocator);

	for nearby_lookup in nearby_lookups {
		if player_lookup == nearby_lookup do continue;

		nearby_entity := get_entity(nearby_lookup);

		// Ignore object if it's velocity is relatively the same
		// This duplicate code could get removed if I have Car's hold rigid bodies
		VEL_DIFF :: 5;
		#partial switch variant in nearby_entity.variant {
		case ^Rigid_Body_Entity:
			entity_vel := linalg.dot(surface_forward, variant.velocity);
			car_vel := linalg.dot(surface_forward, car.velocity);

			if entity_vel + VEL_DIFF >= car_vel {
				continue;
			}
		case ^Car_Entity:
			entity_vel := linalg.dot(surface_forward, variant.velocity);
			car_vel := linalg.dot(surface_forward, car.velocity);

			if entity_vel + VEL_DIFF >= car_vel {
				continue;
			}
		}

		for &hull in nearby_entity.collision_hulls {
			MAX_DIST :: 20;
			center_dir := math2.box_center(hull.global_bounds) - origin;

			// Should probably account for the center of the hull being far away but one of the closest points 
			// is within MAX_DIST
			if linalg.length2(center_dir) > MAX_DIST * MAX_DIST {
				continue;
			}

			PADDING :: 1.5;
			angle_l, angle_r: f32;
			
			{
				left_dir := linalg.cross(car.surface_normal, center_dir);
				p := furthest_point_hull(&hull, left_dir);
				p_dir := p - origin;

				left_dir = linalg.cross(car.surface_normal, p_dir);
				p = furthest_point_hull(&hull, left_dir);
				p_dir = p - origin;

				proj := p - linalg.dot(p_dir, car.surface_normal) * car.surface_normal;
				proj_dir := proj - origin;
				proj_pad_trans_dir := linalg.normalize(linalg.cross(car.surface_normal, proj_dir));
				proj_pad_p := proj + proj_pad_trans_dir * PADDING;
				proj_pad_dir := linalg.normalize(proj_pad_p - origin);
				angle_mag := math.acos(linalg.dot(proj_pad_dir, surface_forward));
				angle_sign := math.sign(linalg.dot(car_left, proj_pad_dir));
				angle_l = angle_mag * angle_sign;
			}

			if angle_l < -MAX_ANGLE do continue;

			{
				right_dir := linalg.cross(center_dir, car.surface_normal);
				p := furthest_point_hull(&hull, right_dir);
				p_dir := p - origin;

				right_dir = linalg.cross(p_dir, car.surface_normal);
				p = furthest_point_hull(&hull, right_dir);
				p_dir = p - origin;

				proj := p - linalg.dot(p_dir, car.surface_normal) * car.surface_normal;
				proj_dir := proj - origin;
				proj_pad_trans_dir := linalg.normalize(linalg.cross(proj_dir, car.surface_normal));
				proj_pad_p := proj + proj_pad_trans_dir * PADDING;
				proj_pad_dir := linalg.normalize(proj_pad_p - origin);
				angle_mag := math.acos(linalg.dot(proj_pad_dir, surface_forward));
				angle_sign := math.sign(linalg.dot(car_left, proj_pad_dir));
				angle_r = angle_mag * angle_sign;
			}

			if angle_r > MAX_ANGLE do continue;

			over_edge_l := false;
			if angle_l > MAX_ANGLE {
				over_edge_l = true;
				angle_l = MAX_ANGLE;
			}

			over_edge_r := false;
			if angle_r < -MAX_ANGLE {
				over_edge_r = true;
				angle_r = -MAX_ANGLE;
			}

			append(&zones, Zone { true,  over_edge_l, angle_l });
			append(&zones, Zone { false, over_edge_r, angle_r });
		}
	}

	// Calculate the target angle from target point
	target_angle: f32;
	{
		target_dir := linalg.normalize(target_point - origin);
		target_angle_mag := math.acos(linalg.dot(surface_forward, target_dir));
		target_angle_sign := math.sign(linalg.dot(car_left, target_dir));
		target_angle = target_angle_mag * target_angle_sign;
	}

	car.start_zone_angle = nil;
	car.end_zone_angle = nil;

	// Determine if the player is in a zone so we can move the target angle
	if len(zones) > 0 {
		// Sort
		order :: proc(a, b: Zone) -> bool {
			return a.angle >= b.angle;
		}

		slice.sort_by(zones[:], order);

		// Check if we're in a zone
		in_zone := false;
		start_angle, end_angle: f32;
		start_over_edge := false;
		end_over_edge := false;
		count: int;

		for &zone, i in zones {
			if zone.start {
				count += 1;
				
				if count == 1 {
					start_angle = zone.angle;
					start_over_edge = zone.over_edge;
				}
			} else {
				count -= 1;

				if count == 0 {
					end_angle = zone.angle;
					end_over_edge = zone.over_edge;

					if target_angle < start_angle && target_angle > end_angle {
						in_zone = true;
						break;
					}
				}
			}
		}

		// If the player is in a zone, move the target angle
		if in_zone {
			if start_over_edge {
				target_angle = end_angle;
			} else if end_over_edge {
				target_angle = start_angle;
			} else if start_over_edge && end_over_edge {
				// zone spans entire cone so don't change target angle
			} else {
				start := abs(start_angle);
				end := abs(end_angle);

				if start > end {
					target_angle = end_angle;
				} else {
					target_angle = start_angle;
				}
			}

			car.start_zone_angle = start_angle;
			car.end_zone_angle = end_angle;
		}
	}

	car.target_angle = target_angle;

	{ // Drive torwards the target angle
		// Steer multiplier
		mag := min(abs(target_angle), MAX_ANGLE);

		if car.sliding {
			// There is some small threshold we don't apply any input for because the car is
			// pretty much pointing the direction of the target angle.
			if abs(target_angle) > 0.15 {
				car.input_steer_multiplier = math.sign(target_angle);
			} else {
				car.input_steer_multiplier = 0;
			}
		} else {
			MAX_SMOOTH_ANGLE :: 0.3;
	
			if mag < MAX_SMOOTH_ANGLE {
				car.input_steer_multiplier = target_angle / MAX_SMOOTH_ANGLE;
			} else {
				car.input_steer_multiplier = math.sign(target_angle);
			}
		}

		// Accel multiplier
		target_speed: f32;

		if sharpness < 0.65 || mag > 0.6 {
			target_speed = 13;
		} else {
			target_speed = CAR_TOP_SPEED;
		}

		curr_speed := linalg.dot(surface_forward, car.velocity);
		car.input_accel_multiplier = math.sign(target_speed - curr_speed);
	}
}

ai_show_helpers :: proc(ai_players: []Entity_Lookup) {
	for lookup in ai_players {
		car := get_entity(lookup).variant.(^Car_Entity);

		for lookup in car.helpers {
			remove_geometry(lookup);
		}
	
		clear(&car.helpers);

		geo: ^Geometry;
		geo_lookup: Geometry_Lookup;

		if false {
			geo, geo_lookup = create_geometry("ai_helper", .KeepRender);
			geometry_make_line_helper_start_end(geo, car.origin, car.closest_left, BLUE);
			append(&car.helpers, geo_lookup);

			geo, geo_lookup = create_geometry("ai_helper", .KeepRender);
			geometry_make_line_helper_start_end(geo, car.origin, car.closest_right, BLUE);
			append(&car.helpers, geo_lookup);
		}

		if false {
			geo, geo_lookup = create_geometry("ai_helper", .KeepRender);
			geometry_make_line_helper_start_end(geo, car.origin, car.extended_left, BLUE);
			append(&car.helpers, geo_lookup);
	
			geo, geo_lookup = create_geometry("ai_helper", .KeepRender);
			geometry_make_line_helper_start_end(geo, car.origin, car.extended_right, BLUE);
			append(&car.helpers, geo_lookup);
		}

		geo, geo_lookup = create_geometry("ai_helper", .KeepRender);
		geometry_make_line_helper_start_end(geo, car.origin, car.target_point, BLUE);
		append(&car.helpers, geo_lookup);

		if true {
			geo, geo_lookup = create_geometry("ai_helper", .KeepRender);
			geometry_make_line_helper_origin_vector(geo, car.target_point, car.tangent_1 * 5, YELLOW);
			append(&car.helpers, geo_lookup);

			geo, geo_lookup = create_geometry("ai_helper", .KeepRender);
			geometry_make_line_helper_origin_vector(geo, car.target_point, car.tangent_2 * 5, YELLOW);
			append(&car.helpers, geo_lookup);
		}

		geo, geo_lookup = create_geometry("ai_helper", .KeepRender);
		geometry_make_line_helper_start_end(geo, car.origin, car.max_l);
		append(&car.helpers, geo_lookup);

		geo, geo_lookup = create_geometry("ai_helper", .KeepRender);
		geometry_make_line_helper_start_end(geo, car.origin, car.max_r);
		append(&car.helpers, geo_lookup);

		// geo, geo_lookup = create_geometry("ai_helper", .KeepRender);
		// geometry_make_box_helper(geo, player.bounds.min, player.bounds.max, PURPLE);
		// append(&player.helpers, geo_lookup);

		if angle, ok := car.start_zone_angle.?; ok {
			start_zone_dir := math2.vector3_rotate(car.surface_forward, car.surface_normal, angle);
			geo, geo_lookup = create_geometry("ai_helper", .KeepRender);
			geometry_make_line_helper_origin_vector(geo, car.origin, start_zone_dir * 20, RED);
			append(&car.helpers, geo_lookup);
		}

		if angle, ok := car.end_zone_angle.?; ok {
			end_zone_dir := math2.vector3_rotate(car.surface_forward, car.surface_normal, angle);
			geo, geo_lookup = create_geometry("ai_helper", .KeepRender);
			geometry_make_line_helper_origin_vector(geo, car.origin, end_zone_dir * 20, RED);
			append(&car.helpers, geo_lookup);
		}

		car_left := math2.matrix4_left(car.transform);
		surface_forward := linalg.normalize(linalg.cross(car_left, car.surface_normal));
		target_dir := math2.vector3_rotate(surface_forward, car.surface_normal, car.target_angle);
		geo, geo_lookup = create_geometry("ai_helper", .KeepRender);
		geometry_make_line_helper_origin_vector(geo, car.origin, target_dir * 10, GREEN);
		append(&car.helpers, geo_lookup);

		if true {
			// #todo: 0.8 should be MAX_ANGLE
			input_steer_dir := math2.vector3_rotate(surface_forward, car.surface_normal, car.input_steer_multiplier * 0.8);
			geo, geo_lookup = create_geometry("ai_helper", .KeepRender);
			geometry_make_line_helper_origin_vector(geo, car.origin, input_steer_dir * 10, PURPLE);
			append(&car.helpers, geo_lookup);
		}

		// #cleanup: This has nothing to do with AI
		/*if car.sliding {
			geo, geo_lookup = create_geometry("car_helper_sliding", .KeepRender);
			geometry_make_line_helper_origin_vector(geo, car.origin, linalg.VECTOR3F32_Y_AXIS * 5, PURPLE);
			append(&car.helpers, geo_lookup);
		}*/
	}
}

@(private = "file")
find_target_point_on_path :: proc(origin: linalg.Vector3f32, left_path, right_path: []Curve, player: ^Car_Entity) -> (linalg.Vector3f32, f32) {
	closest_left_curve_index, closest_left_t, closest_left_point := find_closest_point_on_curve(origin, left_path, player.left_segment);
	closest_right_curve_index, closest_right_t, closest_right_point := find_closest_point_on_curve(origin, right_path, player.right_segment);

	player.left_segment = closest_left_curve_index;
	player.right_segment = closest_right_curve_index;

	extended_left_curve_index, extended_left_t, extended_left_point := move_point_down_path(left_path, closest_left_curve_index, closest_left_t, 15);
	extended_right_curve_index, extended_right_t, extended_right_point := move_point_down_path(right_path, closest_right_curve_index, closest_right_t, 15);

	// Calculate the target point
	target_point := extended_left_point + (extended_right_point - extended_left_point) * player.center_multiplier;

	// Calculate sharpness
	sharpness: f32;

	{
		_, _, end_left_point := move_point_down_path(left_path, closest_left_curve_index, closest_left_t, 30);
		_, _, end_right_point := move_point_down_path(right_path, closest_right_curve_index, closest_right_t, 30);

		closest_dir := linalg.normalize(closest_right_point - closest_left_point);
		end_dir := linalg.normalize(end_right_point - end_left_point);
		sharpness = linalg.dot(closest_dir, end_dir);

		player.tangent_1 = closest_dir;
		player.tangent_2 = end_dir;
	}
	
	// For debugging
	player.closest_left = closest_left_point;
	player.closest_right = closest_right_point;
	player.extended_left = extended_left_point;
	player.extended_right = extended_right_point;
	player.target_point = target_point;

	return target_point, sharpness;
}

// #todo: Make this more efficient
// We'll want to be careful with this prev_segment stuff. It makes finding the closest point no long a global search which
// may be an issue when players get knocked out of bounds.
find_closest_point_on_curve :: proc(origin: linalg.Vector3f32, path: []Curve, prev_segment: int) -> (int, f32, linalg.Vector3f32) {
	closest_curve_index: int;
	closest_t: f32;
	closest_point: linalg.Vector3f32;
	closest_dist_sq := max(f32);
	INC :: 50;

	for i in prev_segment..<prev_segment + 3 {
		curve_index := i % len(path);
		curve := &path[curve_index];
		
		for j in 0..<INC {
			t := f32(j) * 1 / (INC - 1);
			p := find_point_on_curve(curve, t);
			d_sq := linalg.length2(origin - p);
			
			if d_sq < closest_dist_sq {
				closest_t = t;
				closest_point = p;
				closest_dist_sq = d_sq;
				closest_curve_index = curve_index;
			}
		}
	}

	return closest_curve_index, closest_t, closest_point;
}

move_point_down_path :: proc(path: []Curve, curve_index: int, t, dist: f32) -> (int, f32, linalg.Vector3f32) {
	curve := &path[curve_index];
	extended_curve_index := curve_index;
	extended_t := t + dist / curve.length;

	if extended_t > 1 {
		remaining_t := extended_t - 1;
		remaining_len := remaining_t * curve.length;

		next_curve_index := (extended_curve_index + 1) % len(path);
		next_curve := &path[next_curve_index];
		next_t := remaining_len / next_curve.length;
		// assert(next_t <= 1); #todo

		extended_curve_index = next_curve_index;
		extended_t = next_t;
	}

	extended_curve := &path[extended_curve_index];
	extended_point := find_point_on_curve(extended_curve, extended_t);

	return extended_curve_index, extended_t, extended_point;
}

@(private = "file")
find_point_on_curve :: proc(curve: ^Curve, t: f32) -> linalg.Vector3f32 {
	c := f32(1) - t;
	
	return (c * c * c * curve.p0) + (3 * c * c * t * curve.p1) + (3 * c * t * t * curve.p2) + (t * t * t * curve.p3);
}

ai_show_path_helpers :: proc(ai: ^AI) {
	create_path_helper :: proc(path: []Curve) {
		INC :: 20;

		geometry, _ := create_geometry("AI_line_helper", .KeepRender);
		indices := make([dynamic]u16, context.temp_allocator);
		attributes := make([dynamic]f32, context.temp_allocator);

		for &curve, curve_index in path {
			for inc_index in 0..<INC {
				t := f32(inc_index) * (1 / f32(INC - 1));
				p := find_point_on_curve(&curve, t);
				append(&attributes, p[0], p[1], p[2], RED[0], RED[1], RED[2]);

				if inc_index != 0 {
					index := u16(curve_index * INC + inc_index);
					append(&indices, index - 1, index);
				}
			}
		}

		geometry_make_line_mesh(geometry, indices[:], attributes[:]);
	}

	create_path_helper(ai.left_path[:]);
	create_path_helper(ai.right_path[:]);
}