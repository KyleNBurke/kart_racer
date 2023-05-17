package main;

import "vendor:glfw";
import "core:math";
import "core:math/linalg";
import "core:math/rand";
import "math2";

@(private="file") FIRE_PARTICLE_LIFE_TIME: f32 : 0.2;
@(private="file") MAX_FIRE_PARTICLES :: 100;
@(private="file") TIME_BETWEEN_FIRE_PARTILCE_EMISSION :: FIRE_PARTICLE_LIFE_TIME / MAX_FIRE_PARTICLES;

@(private="file") SHOCK_PARTICLE_MAX_X :: 1.2;
@(private="file") SHOCK_PARTICLE_MAX_Y :: 1.0;
@(private="file") SHOCK_PARTICLE_MIN_Y :: -0.4;
@(private="file") SHOCK_PARTICLE_MAX_Z :: 1.8;
@(private="file") SHOCK_PARTICLE_MIN_Z :: -2.2;

@(private="file") MAX_SHOCK_PARTICLES :: 100;
@(private="file") SHOCK_PARTICLE_RAMP_DOWN_TIME: f32 : 1;
@(private="file") TIME_BETWEEN_SHOCK_PARTICLE_DESTRUCTION :: SHOCK_PARTICLE_RAMP_DOWN_TIME / MAX_SHOCK_PARTICLES;

SHOCK_PARTICLE_COLOR_FADE_TIME :: 2.0;
SHOCK_PARTICLE_SIZE :: 0.1;

Car_Helpers :: struct {
	front_tire_left_geo_lookup,
	back_tire_left_geo_lookup: Geometry_Lookup,
}

init_car_helpers :: proc() -> Car_Helpers {
	using car_helpers: Car_Helpers;

	front_tire_left_geo := init_empty_geometry("Front tire left visualizer");
	front_tire_left_geo_lookup = add_geometry(front_tire_left_geo, .KeepRender);

	back_tire_left_geo := init_empty_geometry("Back tire left visualizer");
	back_tire_left_geo_lookup = add_geometry(back_tire_left_geo, .KeepRender);

	return car_helpers;
}

shock_car :: proc(car: ^Car_Entity) {
	car.shock_remaining_time = 1;

	if !car.shocked {
		car.shocked = true;

		for _ in 0..<MAX_SHOCK_PARTICLES {
			particle: Game_Particle;
			particle.size = SHOCK_PARTICLE_SIZE;
			reset_shock_particle(car, &particle);
	
			append(&car.shock_particles, particle);
		}
	}
}

light_car_on_fire :: proc(car: ^Car_Entity) {
	car.on_fire_remaining_time = 10;

	if !car.on_fire {
		car.on_fire = true;
		car.on_fire_elapsed_ramp_up_time = 0;
	}
}

update_car_status_effects_and_particles :: proc(car: ^Car_Entity, camera_trans: linalg.Matrix4f32, dt: f32) {
	if car.shocked {
		car.shock_remaining_time -= dt;

		if car.shock_remaining_time <= 0 {
			car.shocked = false;
			car.shock_elapsed_ramp_down_time = 0;
		}
	}

	if car.on_fire {
		if len(car.fire_particles) < MAX_FIRE_PARTICLES {
			desired_particles := min(cast(int) math.ceil(car.on_fire_elapsed_ramp_up_time / TIME_BETWEEN_FIRE_PARTILCE_EMISSION), MAX_FIRE_PARTICLES);
			particles_to_add := desired_particles - len(car.fire_particles);

			for _ in 0..<particles_to_add {
				particle: Game_Particle;
				reset_fire_particle(car, &particle);
				append(&car.fire_particles, particle);
			}

			car.on_fire_elapsed_ramp_up_time += dt;
		}

		car.on_fire_remaining_time -= dt;

		if car.on_fire_remaining_time <= 0 {
			car.on_fire = false;
		}
	}

	for i := len(car.shock_particles) - 1; i >= 0; i -= 1 {
		particle := &car.shock_particles[i];

		car_left    := math2.matrix4_left(car.transform);
		car_up      := math2.matrix4_up(car.transform);
		car_forward := math2.matrix4_forward(car.transform);
		
		dist := particle.position - car.position;

		x_dist := linalg.dot(car_left, dist);
		y_dist := linalg.dot(car_up, dist);
		z_dist := linalg.dot(car_forward, dist);

		if abs(x_dist) > SHOCK_PARTICLE_MAX_X || y_dist < SHOCK_PARTICLE_MIN_Y || y_dist > SHOCK_PARTICLE_MAX_Y || z_dist < SHOCK_PARTICLE_MIN_Z || z_dist > SHOCK_PARTICLE_MAX_Z {
			reset_shock_particle(car, particle);
		}

		update_shock_particle(car.velocity, particle, dt);
	}

	if !car.shocked && len(car.shock_particles) > 0 {
		desired_particles := max(MAX_SHOCK_PARTICLES - cast(int) math.floor(car.shock_elapsed_ramp_down_time / TIME_BETWEEN_SHOCK_PARTICLE_DESTRUCTION), 0);
		resize(&car.shock_particles, desired_particles);
		car.shock_elapsed_ramp_down_time += dt;
	}

	for i := len(car.fire_particles) - 1; i >= 0; i -= 1 {
		particle := &car.fire_particles[i];

		if particle.time_alive >= particle.life_time {
			if car.on_fire {
				reset_fire_particle(car, particle);
			} else {
				unordered_remove(&car.fire_particles, i);
			}
		}

		update_rigid_body_fire_particle(particle, dt);
	}
}

@(private="file")
reset_shock_particle :: proc(car: ^Car_Entity, particle: ^Game_Particle) {
	car_left    := math2.matrix4_left(car.transform);
	car_up      := math2.matrix4_up(car.transform);
	car_forward := math2.matrix4_forward(car.transform);

	offset_left    := car_left    * rand.float32_range(-SHOCK_PARTICLE_MAX_X, SHOCK_PARTICLE_MAX_X);
	offset_up      := car_up      * rand.float32_range(SHOCK_PARTICLE_MIN_Y, SHOCK_PARTICLE_MAX_Y);
	offset_forward := car_forward * rand.float32_range(SHOCK_PARTICLE_MIN_Z, SHOCK_PARTICLE_MAX_Z);
	particle.position = car.position + offset_left + offset_up + offset_forward;

	particle.time_alive = rand.float32_range(0, SHOCK_PARTICLE_COLOR_FADE_TIME);
}

@(private="file")
reset_fire_particle :: proc(car: ^Car_Entity, particle: ^Game_Particle) {
	left := math2.matrix4_left(car.transform);
	forward := math2.matrix4_forward(car.transform);

	offset_left := left * rand.float32_range(-1, 1);
	offset_up := linalg.Vector3f32 {0, -0.4, 0};
	offset_forward := forward * rand.float32_range(-2.2, 1.8);
	particle.position = car.position + offset_left + offset_forward + offset_up;

	particle.velocity = car.velocity;
	particle.velocity.y += 5;

	life_time_offset := rand.float32_range(-0.2, 0.2);
	particle.life_time = FIRE_PARTICLE_LIFE_TIME + life_time_offset;

	particle.time_alive = 0;
}

draw_car_status_effects :: proc(vulkan: ^Vulkan, car: ^Car_Entity) {
	for particle in &car.shock_particles {
		draw_particle(vulkan, &particle);
	}

	for particle in &car.fire_particles {
		draw_particle(vulkan, &particle);
	}
}

@(private="file")
calculate_car_inertia_tensor :: proc(orientation: linalg.Quaternionf32) -> linalg.Matrix3f32 {
	M :: 1.0 / 12.0;
	CAR_W :: M * (CAR_DEPTH * CAR_DEPTH + CAR_HEIGHT * CAR_HEIGHT);
	CAR_H :: M * (CAR_WIDTH * CAR_WIDTH + CAR_DEPTH * CAR_DEPTH);
	CAR_D :: M * (CAR_WIDTH * CAR_WIDTH + CAR_HEIGHT * CAR_HEIGHT);

	INV_LOCAL_INERTIA_TENSOR :: linalg.Matrix3f32 {
		1.0 / CAR_W, 0.0, 0.0,
		0.0, 1.0 / CAR_H, 0.0,
		0.0, 0.0, 1.0 / CAR_D,
	};

	return math2.calculate_inv_global_inertia_tensor(orientation, INV_LOCAL_INERTIA_TENSOR);
}

move_car :: proc(window: glfw.WindowHandle, car: ^Car_Entity, dt: f32, car_helpers: ^Car_Helpers) {
	axes := glfw.GetJoystickAxes(glfw.JOYSTICK_1);
	accel_multiplier: f32 = 0;
	steer_multiplier: f32 = 0;
	
	{ // Calculate a value between -1 and 1 to determine how much linear force to apply
		if glfw.GetKey(window, glfw.KEY_W) == glfw.PRESS do accel_multiplier += 1;
		if glfw.GetKey(window, glfw.KEY_S) == glfw.PRESS do accel_multiplier -= 1;

		if len(axes) > 0 {
			accel_multiplier += (axes[5] + 1.0) / 2.0;
			accel_multiplier -= (axes[4] + 1.0) / 2.0;
		}
	}

	cornering_angle: { // Calculate a value between -1 and 1 to determine the desired cornering angle
		if car.shocked {
			break cornering_angle;
		}

		if glfw.GetKey(window, glfw.KEY_A) == glfw.PRESS do steer_multiplier += 1;
		if glfw.GetKey(window, glfw.KEY_D) == glfw.PRESS do steer_multiplier -= 1;

		if len(axes) > 0 {
			steer_multiplier = adjust_stick_pos_for_deadzone(axes[0]);
		}
	}

	body_forward := math2.matrix4_forward(car.transform);
	body_up := math2.matrix4_up(car.transform);
	body_left := math2.matrix4_left(car.transform);

	body_velocity := car.velocity;
	body_angular_velocity := car.angular_velocity;
	body_tensor := calculate_car_inertia_tensor(car.orientation);

	front_left_contact_normal, front_left_contact_normal_ok := car.wheels[0].contact_normal.?;
	front_right_contact_normal, front_right_contact_normal_ok := car.wheels[1].contact_normal.?;
	back_left_contact_normal, back_left_contact_normal_ok := car.wheels[2].contact_normal.?;
	back_right_contact_normal, back_right_contact_normal_ok := car.wheels[3].contact_normal.?;

	if front_left_contact_normal_ok || front_right_contact_normal_ok || back_left_contact_normal_ok || back_right_contact_normal_ok {
		surface_normal := linalg.normalize(front_left_contact_normal + front_right_contact_normal + back_left_contact_normal + back_right_contact_normal);
		
		ang_vel := linalg.dot(body_angular_velocity, surface_normal);
		
		body_surface_lat_dir := linalg.normalize(linalg.cross(surface_normal, body_forward));
		lat_vel := linalg.dot(body_velocity, body_surface_lat_dir);

		lat_slip_threshold,
		ang_slip_threshold,
		slipping_max_lat_fric,
		slipping_max_ang_fric: f32;
		
		switch car.surface_type {
		case .Normal:
			lat_slip_threshold = 3;
			ang_slip_threshold = 5;
			slipping_max_lat_fric = 20;
			slipping_max_ang_fric = 2;
		case .Oil:
			lat_slip_threshold = 3;
			ang_slip_threshold = 5;
			slipping_max_lat_fric = 0;
			slipping_max_ang_fric = 0;
		}

		slipping := false;

		buttons := glfw.GetJoystickButtons(glfw.JOYSTICK_1);
		if len(buttons) > 0 {
			if buttons[0] == glfw.PRESS {
				slipping = true;
			}
		}

		if abs(lat_vel) > lat_slip_threshold || abs(ang_vel) > ang_slip_threshold {
			slipping = true;
		}

		full_grip_top_speed: f32 = 20 if car.on_fire else 35;

		top_speed: f32;

		if slipping {
			car.current_steer_angle = 0;

			ang_fric := -clamp(ang_vel, -slipping_max_ang_fric * dt, slipping_max_ang_fric * dt);
			ang_fric += 3.0 * steer_multiplier * dt;
			car.angular_velocity += surface_normal * ang_fric;

			fric := clamp(lat_vel, -slipping_max_lat_fric * dt, slipping_max_lat_fric * dt);
			car.velocity -= body_surface_lat_dir * fric;

			top_speed_multiplier := max((20 - abs(lat_vel)) / 20, 0);
			top_speed = (full_grip_top_speed - 10) * top_speed_multiplier + 10;

			// front_tire_left_geo := get_geometry(car_helpers.front_tire_left_geo_lookup);
			// set_line_helper(front_tire_left_geo, car.position + body_forward * SPRING_BODY_POINT_Z, body_left * 2, YELLOW);

			// back_tire_left_geo := get_geometry(car_helpers.back_tire_left_geo_lookup);
			// set_line_helper(back_tire_left_geo, car.position + body_forward * -SPRING_BODY_POINT_Z, body_left * 2, YELLOW);
		} else {
			if front_left_contact_normal_ok || front_right_contact_normal_ok {
				surface_normal := linalg.normalize(front_left_contact_normal + front_right_contact_normal);
				body_surface_long_dir := linalg.normalize(linalg.cross(body_left, surface_normal));
				body_surface_long_vel := linalg.dot(body_velocity, body_surface_long_dir);
				body_surface_long_forward_vel := max(body_surface_long_vel, 0);
				max_steer_angle := 0.05 + 0.195 * max(full_grip_top_speed - body_surface_long_forward_vel, 0) / full_grip_top_speed;
	
				target_steer_angle := max_steer_angle * steer_multiplier;
				car.current_steer_angle += clamp(target_steer_angle - car.current_steer_angle, -0.8 * dt, 0.8 * dt);
				tire_long_dir := math2.vector3_rotate(body_forward, body_up, car.current_steer_angle);
				tire_lat_dir := linalg.normalize(linalg.cross(surface_normal, tire_long_dir));
				tire_vel := body_velocity + linalg.cross(body_angular_velocity, body_forward * SPRING_BODY_POINT_Z);
				tire_lat_vel := linalg.dot(tire_vel, tire_lat_dir);
				tire_fric := tire_lat_vel / 2;
	
				car.velocity -= tire_lat_dir * tire_fric;
				car.angular_velocity -= body_tensor * body_up * tire_fric;
	
				// front_tire_left_geo := get_geometry(car_helpers.front_tire_left_geo_lookup);
				// set_line_helper(front_tire_left_geo, car.position + body_forward * SPRING_BODY_POINT_Z, tire_lat_dir * 2, GREEN);
			}

			if back_left_contact_normal_ok || back_right_contact_normal_ok {
				surface_normal := linalg.normalize(back_left_contact_normal + back_right_contact_normal);
				body_surface_lat_dir := linalg.normalize(linalg.cross(surface_normal, body_forward));
				tire_vel := body_velocity + linalg.cross(body_angular_velocity, -body_forward * SPRING_BODY_POINT_Z);
				tire_lat_vel := linalg.dot(tire_vel, body_surface_lat_dir);
				tire_fric := tire_lat_vel / 2;
	
				car.velocity -= body_surface_lat_dir * tire_fric;
				car.angular_velocity -= body_tensor * -body_up * tire_fric;

				// back_tire_left_geo := get_geometry(car_helpers.back_tire_left_geo_lookup);
				// set_line_helper(back_tire_left_geo, car.position + body_forward * -SPRING_BODY_POINT_Z, body_left * 2, GREEN);
			}

			top_speed = full_grip_top_speed;
		}

		body_surface_long_dir := linalg.normalize(linalg.cross(body_left, surface_normal));
		body_surface_long_vel := linalg.dot(body_velocity, body_surface_long_dir);

		DRAG: f32 : 5;
		REVERSE_TOP_SPEED: f32 : 15;

		drag_accel := clamp(body_surface_long_vel, -DRAG * dt, DRAG * dt);
		long_vel := body_surface_long_vel - drag_accel;
		accel := -drag_accel;

		if accel_multiplier > 0 {
			if long_vel < top_speed {
				accel += min(top_speed - long_vel, 50 * dt);
			}
		} else if accel_multiplier < 0 {
			if long_vel > 1e-4 {
				accel -= min(long_vel, -accel_multiplier * 20 * dt);
			} else {
				if abs(long_vel) < REVERSE_TOP_SPEED {
					accel -= min(REVERSE_TOP_SPEED - abs(long_vel), 40 * dt);
				}
			}
		}

		car.velocity += body_surface_long_dir * accel;
	} else {
		pitch_multiplier: f32 = 0;

		if len(axes) > 0 {
			pitch_multiplier = adjust_stick_pos_for_deadzone(axes[1]);
		}

		if pitch_multiplier == 0 {
			AIR_PITCH_DRAG :: 2;

			ang_vel_pitch := linalg.dot(body_left, car.angular_velocity);
			fric := clamp(ang_vel_pitch, -AIR_PITCH_DRAG * dt, AIR_PITCH_DRAG * dt);
			car.angular_velocity += body_left * -fric;
		} else {
			AIR_PITCH_ACCEL :: 3;
			
			car.angular_velocity += body_left * pitch_multiplier * AIR_PITCH_ACCEL * dt;
		}
	}
}

adjust_stick_pos_for_deadzone :: proc(pos: f32) -> f32 {
	adjusted_pos: f32 = 0;

	if abs(pos) > 0.25 {
		adjusted_pos = -(pos - 0.25 * math.sign(pos)) / 0.75;
	}

	return adjusted_pos;
}

position_and_orient_wheels :: proc(car: ^Car_Entity, dt: f32) {
	// Calculate wheel orientations
	body_left := math2.matrix4_left(car.transform);

	front_left_contact_normal, front_left_contact_normal_ok := car.wheels[0].contact_normal.?;
	front_right_contact_normal, front_right_contact_normal_ok := car.wheels[1].contact_normal.?;

	if front_left_contact_normal_ok || front_right_contact_normal_ok {
		surface_normal := linalg.normalize(front_left_contact_normal + front_right_contact_normal);
		surface_forward := linalg.normalize(linalg.cross(body_left, surface_normal));
		surface_forward_vel := linalg.dot(surface_forward, car.velocity);
		car.front_wheel_angular_velocity = surface_forward_vel / car.wheel_radius;
	}

	car.front_wheel_orientation = math.mod(car.front_wheel_orientation + car.front_wheel_angular_velocity * dt, math.TAU);

	back_left_contact_normal, back_left_contact_normal_ok := car.wheels[2].contact_normal.?;
	back_right_contact_normal, back_right_contact_normal_ok := car.wheels[3].contact_normal.?;

	if back_left_contact_normal_ok || back_right_contact_normal_ok {
		surface_normal := linalg.normalize(back_left_contact_normal + back_right_contact_normal);
		surface_forward := linalg.normalize(linalg.cross(body_left, surface_normal));
		surface_forward_vel := linalg.dot(surface_forward, car.velocity);
		car.back_wheel_angular_velocity = surface_forward_vel / car.wheel_radius;
	}

	car.back_wheel_orientation = math.mod(car.back_wheel_orientation + car.back_wheel_angular_velocity * dt, math.TAU);

	// Position and orient wheels
	body_down := -math2.matrix4_up(car.transform);

	for wheel, wheel_index in &car.wheels {
		wheel_entity := get_entity(wheel.entity_lookup);
		wheel_entity.position = wheel.body_point + body_down * (wheel.spring_length - car.wheel_radius);
		
		body_euler_y, body_euler_z, _ := linalg.euler_angles_yzx_from_quaternion(car.orientation);

		if wheel_index == 0 || wheel_index == 1 {
			wheel_entity.orientation = linalg.quaternion_from_euler_angles(body_euler_y + car.current_steer_angle, body_euler_z, car.front_wheel_orientation, .YZX);
		} else {
			wheel_entity.orientation = linalg.quaternion_from_euler_angles(body_euler_y, body_euler_z, car.back_wheel_orientation, .YZX);
		}

		update_entity_transform(wheel_entity); 
	}
}