package main;

import "core:math";
import "core:math/linalg";
import "core:thread";
import "core:sync";
import "math2";

import "core:fmt";

AI_PLAYERS_COUNT :: 1;

AI :: struct {
	semaphore: sync.Sema,
	elapsed_time: f32,
	path: [dynamic]Curve,
	players: [AI_PLAYERS_COUNT]AI_Player,
	closest_point_line_geo_helper: Geometry_Lookup,
	target_point_line_geo_helper: Geometry_Lookup,
}

AI_Player :: struct {
	lookup: Entity_Lookup,
	target_point: linalg.Vector3f32,
}

Curve :: struct {
	p0, p1, p2, p3: linalg.Vector3f32,
	length: f32,
}

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
	UPDATE_INTERVAL: f32 : 1 / 100;

	ai.elapsed_time += dt;

	if ai.elapsed_time >= UPDATE_INTERVAL {
		sync.sema_post(&ai.semaphore);
		ai.elapsed_time = 0;
	}
}

ai_init :: proc(ai: ^AI) {
	geometry, geometry_lookup := create_geometry("ai_line_helper", .KeepRender);
	geometry_make_line_helper_origin_vector(geometry, {0, 0, 0}, {0, 0, 1}); // #todo: Hate that I have to do this.
	ai.closest_point_line_geo_helper = geometry_lookup;

	geometry, geometry_lookup = create_geometry("ai_tangent_line_helper", .KeepRender);
	geometry_make_line_helper_origin_vector(geometry, {0, 0, 0}, {0, 0, 1}); // #todo: Hate that I have to do this.
	ai.target_point_line_geo_helper = geometry_lookup;

	thread.create_and_start_with_data(ai, ai_update_players);
}

ai_update_players :: proc(ai: rawptr) {
	ai := cast(^AI) ai;
	
	for {
		sync.sema_wait(&ai.semaphore);
		
		for &player in ai.players {
			car := get_entity(player.lookup).variant.(^Car_Entity);

			closest_point, target_point := find_target_point_on_path(car.position, ai.path[:]);
			player.target_point = target_point;
		}
	}
}

set_ai_player_inputs :: proc(ai: ^AI) {
	for &player in ai.players {
		car := get_entity(player.lookup).variant.(^Car_Entity);

		current_heading := math2.matrix4_forward(car.transform);
		target_heading := linalg.normalize(player.target_point - car.position);
		heading_diff := linalg.dot(current_heading, target_heading);
		
		{ // Steer angle
			plane_normal := linalg.cross(target_heading, linalg.Vector3f32 {0, 1, 0});
			steer_angle_dir := math.sign(linalg.dot(plane_normal, current_heading));
			
			MAX_DIFF :: 0.9;
			steer_angle_mag: f32

			if heading_diff > MAX_DIFF {
				steer_angle_mag = 1 - (heading_diff - MAX_DIFF) / (1 - MAX_DIFF);
			} else {
				steer_angle_mag = 1;
			}
			
			car.input_steer_multiplier = steer_angle_dir * steer_angle_mag;
		}

		{ // Acceleration/braking
			HIGH_DIFF :: 0.95;
			LOW_DIFF :: 0.7;
			LOW_SPEED :: 15;

			target_speed: f32;
			if heading_diff > HIGH_DIFF {
				target_speed = CAR_TOP_SPEED;
			} else if heading_diff < LOW_DIFF {
				target_speed = LOW_SPEED;
			} else {
				target_speed = math.remap(heading_diff, LOW_DIFF, HIGH_DIFF, LOW_SPEED, CAR_TOP_SPEED);
			}

			current_speed := linalg.dot(current_heading, car.velocity);
			
			car.input_accel_multiplier = (target_speed - current_speed) / 10;
		}

		// Ehh don't like this here but also it's just some debug shit
		target_line_helper_geometry := get_geometry(ai.target_point_line_geo_helper);
		geometry_make_line_helper_start_end(target_line_helper_geometry, car.position, player.target_point, BLUE);
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
		closest_curve_t: f32;
		closest_curve_p: linalg.Vector3f32;
		closest_curve_dist_sq := max(f32);

		DIV :: 50;

		// Comment
		for i in 0..<DIV {
			t := f32(i) * 1 / (DIV - 1);
			p := find_point_on_curve(&curve, t);
			d_sq := linalg.length2(origin - p);
			
			if d_sq < closest_curve_dist_sq {
				closest_curve_t = t;
				closest_curve_p = p;
				closest_curve_dist_sq = d_sq;
			}
		}
	}

	
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