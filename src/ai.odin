package main;

import "core:math";
import "core:math/linalg";
import "core:thread";
import "core:sync";
import "core:slice";
import "math2";

import "core:fmt";

AI_PLAYERS_COUNT :: 1;

AI :: struct {
	semaphore: sync.Sema,
	elapsed_time: f32,
	path: [dynamic]Curve,
	players: [AI_PLAYERS_COUNT]AI_Player,
}

AI_Player :: struct {
	lookup: Entity_Lookup,
	
	helpers: [dynamic]Geometry_Lookup,
	origin,
	closest_point,
	extended_point,
	max_l, max_r: linalg.Vector3f32,
	bounds: math2.Box3f32,
	start_zone_angle, end_zone_angle: Maybe(f32),
	surface_forward: linalg.Vector3f32,
	target_angle: f32,
}

Curve :: struct {
	p0, p1, p2, p3: linalg.Vector3f32,
	length: f32,
}

Zone :: struct {
	start: bool,
	angle: f32,
}

RAY_COUNT :: 8;

calculate_curve_lengths :: proc(curves: []Curve) {
	p0 := curves[0].p0;
	p1: linalg.Vector3f32;

	for &curve in curves {
		total_len: f32 = 0;
		POINTS :: 20;

		for i in 1..<POINTS {
			t := f32(i) * 1 / (POINTS - 1);
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
	thread.create_and_start_with_data(scene, ai_update_players);
}

ai_update_players :: proc(scene: rawptr) {
	scene := cast(^Scene) scene;
	ai := &scene.ai;
	
	for {
		sync.sema_wait(&ai.semaphore);
		
		for &player in ai.players {
			update_player_new(&player, ai.path[:], &scene.entity_grid);
		}
	}
}

@(private = "file")
update_player_new :: proc(player: ^AI_Player, path: []Curve, entity_grid: ^Entity_Grid) {
	car := get_entity(player.lookup).variant.(^Car_Entity);

	car_left := math2.matrix4_left(car.transform);
	surface_forward := linalg.normalize(linalg.cross(car_left, car.surface_normal)); // #todo: Do once
	origin := car.position + surface_forward * 0.8;
	player.surface_forward = surface_forward;
	player.origin = origin;

	// Find extended point
	closest_point, extended_point := find_target_point_on_path_2(origin, path);
	player.closest_point = closest_point;
	player.extended_point = extended_point;

	RAY_LEN :: 20;
	MAX_ANGLE :: 0.8;
	
	nearby_lookups: [dynamic]Entity_Lookup;
	{
		forward := origin + surface_forward * RAY_LEN;

		max_l_dir := math2.vector3_rotate(surface_forward, car.surface_normal, MAX_ANGLE);
		max_r_dir := math2.vector3_rotate(surface_forward, car.surface_normal, -MAX_ANGLE);
		max_l := origin + max_l_dir * RAY_LEN;
		max_r := origin + max_r_dir * RAY_LEN;
		player.max_l = max_l;
		player.max_r = max_r;

		bounds := math2.Box3f32 {
			math2.vector3_min(origin, forward, max_l, max_r),
			math2.vector3_max(origin, forward, max_l, max_r),
		};

		player.bounds = bounds;

		// This query is returning back the car at the beggining, need to look into that.
		nearby_lookups = entity_grid_find_nearby_entities(entity_grid, bounds);
	}

	zones := make([dynamic]Zone, context.temp_allocator);

	for nearby_lookup in nearby_lookups {
		if player.lookup == nearby_lookup do continue;

		nearby_entity := get_entity(nearby_lookup);

		for &hull in nearby_entity.collision_hulls {
			center_dir := math2.box_center(hull.global_bounds) - origin;
			left_dir := linalg.cross(car.surface_normal, center_dir);
			right_dir := linalg.cross(center_dir, car.surface_normal);

			PADDING :: 1;

			// #todo: Consider the length of the point?

			l_p := furthest_point_hull(&hull, left_dir);
			l_dir := l_p - origin;
			l_proj := l_p - linalg.dot(l_dir, car.surface_normal) * car.surface_normal;
			l_proj_dir := l_proj - origin;
			l_proj_pad_trans_dir := linalg.normalize(linalg.cross(car.surface_normal, l_proj_dir));
			l_proj_pad_p := l_proj + l_proj_pad_trans_dir * PADDING;
			l_proj_pad_dir := linalg.normalize(l_proj_pad_p - origin);
			l_proj_pad_angle_mag := math.acos(linalg.dot(l_proj_pad_dir, surface_forward));
			l_proj_pad_angle_sign := math.sign(linalg.dot(car_left, l_proj_pad_dir));
			l_proj_pad_angle := l_proj_pad_angle_mag * l_proj_pad_angle_sign;

			r_p := furthest_point_hull(&hull, right_dir);
			r_dir := r_p - origin;
			r_proj := r_p - linalg.dot(r_dir, car.surface_normal) * car.surface_normal;
			r_proj_dir := r_proj - origin;
			r_proj_pad_trans_dir := linalg.normalize(linalg.cross(r_proj_dir, car.surface_normal));
			r_proj_pad_p := r_proj + r_proj_pad_trans_dir * PADDING;
			r_proj_pad_dir := linalg.normalize(r_proj_pad_p - origin);
			r_proj_pad_angle_mag := math.acos(linalg.dot(r_proj_pad_dir, surface_forward));
			r_proj_pad_angle_sign := math.sign(linalg.dot(car_left, r_proj_pad_dir));
			r_proj_pad_angle := r_proj_pad_angle_mag * r_proj_pad_angle_sign;

			if abs(l_proj_pad_angle) < MAX_ANGLE || abs(r_proj_pad_angle) < MAX_ANGLE {
				l_proj_pad_angle_clamped := math.clamp(l_proj_pad_angle, -MAX_ANGLE, MAX_ANGLE);
				r_proj_pad_angle_clmaped := math.clamp(r_proj_pad_angle, -MAX_ANGLE, MAX_ANGLE);

				append(&zones, Zone { true, l_proj_pad_angle_clamped });
				append(&zones, Zone { false, r_proj_pad_angle_clmaped });
			}
		}
	}

	// Calculate the target angle from extended point
	target_angle: f32;
	{
		target_dir := linalg.normalize(extended_point - origin);
		target_angle_mag := math.acos(linalg.dot(surface_forward, target_dir));
		target_angle_sign := math.sign(linalg.dot(car_left, target_dir));
		target_angle = target_angle_mag * target_angle_sign;
	}

	player.start_zone_angle = nil;
	player.end_zone_angle = nil;

	if len(zones) > 0 {
		// Sort
		order :: proc(a, b: Zone) -> bool {
			return a.angle >= b.angle;
		}

		slice.sort_by(zones[:], order);

		// Check if we're in a zone
		in_zone := false;
		start_angle, end_angle: f32;
		start_index, end_index: int;
		count: int;

		for &zone, i in zones {
			if zone.start {
				count += 1;
				
				if count == 1 {
					start_angle = zone.angle;
					start_index = i;
				}
			} else {
				count -= 1;

				if count == 0 {
					end_angle = zone.angle;
					end_index = i;

					if target_angle < start_angle && target_angle > end_angle {
						in_zone = true;
						break;
					}
				}
			}
		}

		if in_zone {
			// Move target angle
			if start_index == 0 {
				target_angle = end_angle;
			} else if end_index == len(zones) - 1 {
				target_angle = start_angle;
			} else {
				angle_to_left := start_angle - target_angle;
				angle_to_right := target_angle - end_angle;

				assert(angle_to_left >= 0);
				assert(angle_to_right >= 0);

				if angle_to_left < angle_to_right {
					target_angle = start_angle;
				} else {
					target_angle = end_angle;
				}
			}

			player.start_zone_angle = start_angle;
			player.end_zone_angle = end_angle;
		}
	}

	{ // Drive torwards the target angle
		MAX_SMOOTH_ANGLE :: 0.3;
		mag := abs(target_angle);

		if mag < MAX_SMOOTH_ANGLE {
			car.input_steer_multiplier = target_angle / MAX_SMOOTH_ANGLE;
		} else {
			car.input_steer_multiplier = math.sign(target_angle);
		}
	}

	car.input_accel_multiplier = 0.1;
}

ai_show_helpers :: proc(ai: ^AI) {
	for &player in ai.players {
		for lookup in player.helpers {
			remove_geometry(lookup);
		}
	
		clear(&player.helpers);

		geo, geo_lookup := create_geometry("ai_helper", .KeepRender);
		geometry_make_line_helper_start_end(geo, player.origin, player.closest_point, BLUE);
		append(&player.helpers, geo_lookup);

		geo, geo_lookup = create_geometry("ai_helper", .KeepRender);
		geometry_make_line_helper_start_end(geo, player.origin, player.extended_point, BLUE);
		append(&player.helpers, geo_lookup);

		geo, geo_lookup = create_geometry("ai_helper", .KeepRender);
		geometry_make_line_helper_start_end(geo, player.origin, player.max_l);
		append(&player.helpers, geo_lookup);

		geo, geo_lookup = create_geometry("ai_helper", .KeepRender);
		geometry_make_line_helper_start_end(geo, player.origin, player.max_r);
		append(&player.helpers, geo_lookup);

		// geo, geo_lookup = create_geometry("ai_helper", .KeepRender);
		// geometry_make_box_helper(geo, player.bounds.min, player.bounds.max);
		// append(&player.helpers, geo_lookup);

		car := get_entity(player.lookup).variant.(^Car_Entity);

		if angle, ok := player.start_zone_angle.?; ok {
			start_zone_dir := math2.vector3_rotate(player.surface_forward, car.surface_normal, angle);
			geo, geo_lookup = create_geometry("ai_helper", .KeepRender);
			geometry_make_line_helper_origin_vector(geo, player.origin, start_zone_dir * 20, RED);
			append(&player.helpers, geo_lookup);
		}

		if angle, ok := player.end_zone_angle.?; ok {
			end_zone_dir := math2.vector3_rotate(player.surface_forward, car.surface_normal, angle);
			geo, geo_lookup = create_geometry("ai_helper", .KeepRender);
			geometry_make_line_helper_origin_vector(geo, player.origin, end_zone_dir * 20, RED);
			append(&player.helpers, geo_lookup);
		}

		car_left := math2.matrix4_left(car.transform);
		surface_forward := linalg.normalize(linalg.cross(car_left, car.surface_normal));
		target_dir := math2.vector3_rotate(surface_forward, car.surface_normal, player.target_angle);
		geo, geo_lookup = create_geometry("ai_helper", .KeepRender);
		geometry_make_line_helper_origin_vector(geo, player.origin, target_dir * 10, GREEN);
		append(&player.helpers, geo_lookup);
	}
}

// #todo: Figure out how I want to find the closest point, got 2 procs here

// We're returning back the closest point for visualizing it only
@(private = "file")
find_target_point_on_path :: proc(origin: linalg.Vector3f32, path: []Curve) -> (closest_point, target_point: linalg.Vector3f32) {
	// Find the cloest point on the entine path
	closest_t: f32;
	closest_dist_sq := max(f32);
	closest_curve_index: int;

	for &curve, curve_index in path {
		closest_curve_t: f32;
		closest_curve_p: linalg.Vector3f32;
		closest_curve_dist_sq := max(f32);

		// Comment
		for i in 0..<5 {
			t := f32(i) * 1 / 4
			p := find_point_on_curve(&curve, t);
			d_sq := linalg.length2(origin - p);
			
			if d_sq < closest_curve_dist_sq {
				closest_curve_t = t;
				closest_curve_p = p;
				closest_curve_dist_sq = d_sq;
			}
		}

		INC :: 0.25 / 3;

		// 2 checks above closest t
		if closest_curve_t < 1 {
			for i in 0..<2 {
				t := closest_curve_t + f32(i + 1) * INC;
				p := find_point_on_curve(&curve, t);
				dist_sq := linalg.length2(origin - p);

				if dist_sq < closest_curve_dist_sq {
					closest_curve_t = t;
					closest_curve_dist_sq = dist_sq;
					closest_curve_p = p;
				}
			}
		}

		// 2 checks below closest t
		if closest_curve_t > 0 {
			for i in 0..<2 {
				t := closest_curve_t + f32(i + 1) * -INC;
				p := find_point_on_curve(&curve, t);
				dist_sq := linalg.length2(origin - p);

				if dist_sq < closest_curve_dist_sq {
					closest_curve_t = t;
					closest_curve_dist_sq = dist_sq;
					closest_curve_p = p;
				}
			}
		}

		if closest_curve_dist_sq < closest_dist_sq {
			closest_t = closest_curve_t;
			closest_dist_sq = closest_curve_dist_sq;
			closest_point = closest_curve_p;
			closest_curve_index = curve_index;
		}
	}

	assert(closest_dist_sq != max(f32));

	{ // Move the closest point forwards along the path
		curve := &path[closest_curve_index];
		target_t := closest_t + 10 / curve.length;

		if target_t > 1 {
			// Need to the convert the remaining length in this curve's space to a t value in the next curve's space
			remaining_t := target_t - 1;
			remaining_len := remaining_t * curve.length;

			next_curve := &path[(closest_curve_index + 1) % len(path)];
			next_t := remaining_len / next_curve.length;
			assert(next_t <= 1); // Will never trigger if distance we move the point along the curve is less than the length of every curve. #todo: Make an assert in the curve length calcs?

			target_point = find_point_on_curve(next_curve, next_t);
		} else {
			target_point = find_point_on_curve(curve, target_t);
		}
	}

	return;
}

@(private = "file")
find_target_point_on_path_2 :: proc(origin: linalg.Vector3f32, path: []Curve) -> (closest_point, target_point: linalg.Vector3f32) {
	// Find the cloest point on the entine path
	closest_t: f32;
	closest_dist_sq := max(f32);
	closest_curve_index: int;

	for &curve, curve_index in path {
		DIV :: 50;

		// Comment
		for i in 0..<DIV {
			t := f32(i) * 1 / (DIV - 1);
			p := find_point_on_curve(&curve, t);
			d_sq := linalg.length2(origin - p);
			
			if d_sq < closest_dist_sq {
				closest_t = t;
				closest_point = p;
				closest_dist_sq = d_sq;
				closest_curve_index = curve_index;
			}
		}
	}
	
	{ // Move the closest point forwards along the path
		curve := &path[closest_curve_index];
		target_t := closest_t + 15 / curve.length;

		if target_t > 1 {
			// Need to the convert the remaining length in this curve's space to a t value in the next curve's space
			remaining_t := target_t - 1;
			remaining_len := remaining_t * curve.length;

			next_curve := &path[(closest_curve_index + 1) % len(path)];
			next_t := remaining_len / next_curve.length;
			assert(next_t <= 1); // Will never trigger if distance we move the point along the curve is less than the length of every curve. #todo: Make an assert in the curve length calcs?

			target_point = find_point_on_curve(next_curve, next_t);
		} else {
			target_point = find_point_on_curve(curve, target_t);
		}
	}

	return;
}

@(private = "file")
find_point_on_curve :: proc(curve: ^Curve, t: f32) -> linalg.Vector3f32 {
	c := f32(1) - t;
	
	return (c * c * c * curve.p0) + (3 * c * c * t * curve.p1) + (3 * c * t * t * curve.p2) + (t * t * t * curve.p3);
}

ai_show_path_helper :: proc(ai: ^AI) {
	geometry, _ := create_geometry("AI_line_helper", .KeepRender);

	INCREMENTS :: 20;
	points := make([dynamic]f32, context.temp_allocator);

	for &curve in ai.path {

		for i in 0..<INCREMENTS {
			t := f32(i) * (1 / f32(INCREMENTS - 1));
			p := find_point_on_curve(&curve, t);
			append(&points, p[0], p[1], p[2]);
		}
	}

	geometry_make_line_helper_points_strip(geometry, points[:], RED);
}