package main;

import "vendor:glfw";
import "core:math";
import "core:math/linalg";
import "core:math/rand";
import "math2";

import "core:fmt";

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

// There is another place we calculate the inertia tensor of the car. Here, we're calculating an inertia tensor
// with a car mass of 1. This is useful when I have calculations that should not depend on the mass of the car.
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

set_player_inputs :: proc(gamepad: ^Gamepad, window: glfw.WindowHandle, player: ^Car_Entity) {
	// #todo: When using keyboard and controller at same time, this would mess up the values.

	{ // Calculate a value between -1 and 1 to determine how much linear force to apply
		accel_multiplier: f32 = 0;

		if glfw.GetKey(window, glfw.KEY_W) == glfw.PRESS do accel_multiplier += 1;
		if glfw.GetKey(window, glfw.KEY_S) == glfw.PRESS do accel_multiplier -= 1;

		accel_multiplier += gamepad_trigger_pos(gamepad, 5);
		accel_multiplier -= gamepad_trigger_pos(gamepad, 4);

		player.input_accel_multiplier = accel_multiplier;
	}

	{ // Calculate a value between -1 and 1 to determine the desired cornering angle
		steer_multiplier: f32 = 0;

		if glfw.GetKey(window, glfw.KEY_A) == glfw.PRESS do steer_multiplier += 1;
		if glfw.GetKey(window, glfw.KEY_D) == glfw.PRESS do steer_multiplier -= 1;

		steer_multiplier += gamepad_stick_adjusted_pos(gamepad, 0);

		player.input_steer_multiplier = steer_multiplier;
	}
	
	player.input_handbreak = false;

	if glfw.GetKey(window, glfw.KEY_SPACE) == glfw.PRESS || gamepad_button_held(gamepad, glfw.GAMEPAD_BUTTON_A) {
		player.input_handbreak = true;
	}
}

move_players :: proc(players: []Entity_Lookup, dt: f32) {
	for lookup in players {
		car := get_entity(lookup).variant.(^Car_Entity);
		move_car(car, dt);
	}
}

CAR_TOP_SPEED: f32 : 35;

@(private = "file")
move_car :: proc(car: ^Car_Entity, dt: f32) {
	car_forward := math2.matrix4_forward(car.transform);
	car_up := math2.matrix4_up(car.transform);
	car_left := math2.matrix4_left(car.transform);

	car_vel := car.velocity;
	car_ang_vel := car.angular_velocity;
	car_tensor := calculate_car_inertia_tensor(car.orientation);

	// front_left_contact_normal, front_left_contact_normal_ok := car.wheels[0].contact_normal.?;
	// front_right_contact_normal, front_right_contact_normal_ok := car.wheels[1].contact_normal.?;
	// back_left_contact_normal, back_left_contact_normal_ok := car.wheels[2].contact_normal.?;
	// back_right_contact_normal, back_right_contact_normal_ok := car.wheels[3].contact_normal.?;

	if car.surface_normal != 0 {
		surface_forward := linalg.normalize(linalg.cross(car_left, car.surface_normal));

		vel := linalg.dot(surface_forward, car_vel);

		surface_velocity := car_vel - linalg.projection(car_vel, car.surface_normal); // project velocity onto surface plane
		surface_velocity_dir := linalg.normalize(surface_velocity);
		slip_angle := math.acos(linalg.dot(surface_velocity_dir, car_forward));

		if car.input_handbreak {
			car.handbrake_duration = 0; // #todo: Is this weird? Do I even need the bool?
		}

		handbraking := false;
		
		if car.handbrake_duration <= 0.3 {
			car.handbrake_duration += dt;
			handbraking = true;
		}

		if handbraking {
			if linalg.length(surface_velocity) > 2 {
				car.sliding = true;
				car.finished_slide = false; // We want the finished slide logic to start once the handbreaking period has ended.
			}
		} else {
			if car.sliding {
				if linalg.length(surface_velocity) < 2 || car.finished_slide {
					car.sliding = false;
					car.finished_slide = false;
				}
			} else {
				if linalg.length(surface_velocity) > 2 && slip_angle > 0.6 {
					car.sliding = true;
				}
			}
		}

		// This will decrease the forwards acceleration when the car is doing a sharp drift.
		accel_slide_multiplier: f32 = 1;

		if car.sliding {
			ANG_FRIC :: 6; // Rotational deceleration

			car.current_steer_angle = 0;
			ang_vel := linalg.dot(car_ang_vel, car.surface_normal);
			ang_accel: f32;
			
			if car.input_steer_multiplier == 0 {
				ang_accel = -clamp(ang_vel, -ANG_FRIC * dt, ANG_FRIC * dt);
			} else {
				MAX_ROTATION_SPEED :: 2;

				if abs(ang_vel) <= MAX_ROTATION_SPEED {
					ang_accel = math.sign(car.input_steer_multiplier) * min(MAX_ROTATION_SPEED - abs(ang_vel), 5 * abs(car.input_steer_multiplier) * dt);
				} else {
					// If you're spinning more than the max rotation speed and the steer angle is in the opposite direction, we could
					// apply a rotational acceleration in that direction to slow it down. Right now, we're just applying the friction.
					ang_accel = -clamp(ang_vel, -ANG_FRIC * dt, ANG_FRIC * dt);
				}
			}

			car.angular_velocity += car.surface_normal * ang_accel;

			lat_fric: f32 = 20; // Lateral deceleration

			// Increase the lateral deceleration when the speed is high.
			// This is for leaving the drift. Without it, the car takes a tad too long to leave the sliding state.
			// To prevent the super large lateral sliding when at a high speed, we could compare against the lateral
			// velocity, not the longitudinal.
			if vel > 25 {
				lat_fric_multiplier := clamp(vel / CAR_TOP_SPEED, 0, 1);
				lat_fric += 18 * lat_fric_multiplier;
			}

			surface_lat := linalg.normalize(linalg.cross(car_forward, car.surface_normal));
			lat_vel := linalg.dot(car_vel, surface_lat);
			lat_accel := clamp(lat_vel, -lat_fric * dt, lat_fric * dt);
			car.velocity -= surface_lat * lat_accel;

			accel_slide_multiplier = 0.5 + 0.5 * (1 - min(abs(lat_vel) / 20, 1));

			// If the lateral and angular velocities have been fully resolved, we're officially done sliding.
			if abs(lat_vel) <= lat_fric * dt && abs(ang_vel) <= ANG_FRIC * dt {
				car.finished_slide = true;
			}
		} else {
			front_surface_normal := linalg.normalize0(car.wheels[0].contact_normal + car.wheels[1].contact_normal);

			if front_surface_normal != 0 {
				LOW_SPEED :: 0.2;
				HIGH_SPEED :: 0.08;
				max_steer_angle := HIGH_SPEED + (LOW_SPEED - HIGH_SPEED) * clamp((CAR_TOP_SPEED - vel) / CAR_TOP_SPEED, 0, 1);

				target_steer_angle: f32 = max_steer_angle * car.input_steer_multiplier;
				car.current_steer_angle += clamp(target_steer_angle - car.current_steer_angle, -0.8 * dt, 0.8 * dt);

				tire_forward := math2.vector3_rotate(car_forward, car_up, car.current_steer_angle);
				tire_surface_left := linalg.normalize(linalg.cross(front_surface_normal, tire_forward));
				
				tire_vel := car_vel + linalg.cross(car_ang_vel, car_forward * SPRING_BODY_POINT_Z);
				tire_surface_left_vel := linalg.dot(tire_surface_left, tire_vel);
				tire_fric := tire_surface_left_vel / 2;

				car.velocity -= tire_surface_left * tire_fric;
				car.angular_velocity -= car_tensor * front_surface_normal * tire_fric;
			}

			back_surface_normal := linalg.normalize0(car.wheels[2].contact_normal + car.wheels[3].contact_normal);

			if back_surface_normal != 0 {
				tire_surface_left := linalg.normalize(linalg.cross(back_surface_normal, car_forward));
				
				tire_vel := car_vel + linalg.cross(car_ang_vel, -car_forward * SPRING_BODY_POINT_Z);
				tire_surface_left_vel := linalg.dot(tire_surface_left, tire_vel);
				tire_fric := tire_surface_left_vel / 2;

				car.velocity -= tire_surface_left * tire_fric;
				car.angular_velocity -= car_tensor * -back_surface_normal * tire_fric;
			}
		}

		BRAKE_FORCE: f32 : 30;
		accel: f32;

		if vel > CAR_TOP_SPEED {
			if car.input_accel_multiplier < 0 {
				// Apply brake force
				accel = -min(vel, -car.input_accel_multiplier * BRAKE_FORCE * dt);
			} else {
				// Apply drag to get car to top speed
				accel = -min(vel - CAR_TOP_SPEED, 20 * dt);
			}
		} else {
			if car.input_accel_multiplier > 0 {
				// Apply acceleration to get car to top speed
				accel = min(CAR_TOP_SPEED - vel, car.input_accel_multiplier * accel_slide_multiplier * 50 * dt);
			} else if car.input_accel_multiplier < 0 {
				// Apply brake force
				accel = -min(vel, -car.input_accel_multiplier * BRAKE_FORCE * dt);
			} else {
				// Apply drag
				accel = -clamp(vel, -20 * dt, 10 * dt);
			}
		}

		car.velocity += surface_forward * accel;

		{ // Set weight distribution multiplier
			v: f32 = clamp(vel / CAR_TOP_SPEED, 0, 1);

			if car.input_accel_multiplier > 0 {
				a := accel / (50 * dt);
				car.weight_distribution_multiplier = a * (1 - v);
			} else if car.input_accel_multiplier < 0 {
				a := accel / (BRAKE_FORCE * dt);
				car.weight_distribution_multiplier = a * v;
			}
		}

		if false {
			car_geo := get_geometry(car.geometry_lookup.?);

			color: [3]f32;
			if car.sliding {
				color = {0.5, 0.5, 0};
			} else {
				color = {0.2, 0.2, 0.2};
			}

			geometry_set_color(car_geo, color);
		}
	} else {
		/* #todo
		PITCH_DRAG :: 1.5;

		// Air controls
		pitch_multiplier := gamepad_stick_adjusted_pos(gamepad, 1);
		
		if glfw.GetKey(window, glfw.KEY_LEFT_SHIFT) == glfw.PRESS {
			if glfw.GetKey(window, glfw.KEY_W) == glfw.PRESS do pitch_multiplier += 1;
			if glfw.GetKey(window, glfw.KEY_S) == glfw.PRESS do pitch_multiplier -= 1;
		}

		pitch_ang_vel := linalg.dot(car_left, car.angular_velocity);

		pitch_accel: f32;

		if pitch_multiplier == 0 {
			pitch_accel = -clamp(pitch_ang_vel, -PITCH_DRAG * dt, PITCH_DRAG * dt);
		} else {
			pitch_accel = math.sign(pitch_multiplier) * min(2 - abs(pitch_ang_vel), 3 * abs(pitch_multiplier) * dt);
		}

		car.angular_velocity += car_left * pitch_accel;
		*/
	}
}

// #todo: Move this inside the other proc so that we're not recalculating the surface normal stuff
/*
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
*/

respawn_player :: proc(car: ^Car_Entity, position: linalg.Vector3f32, orientation: linalg.Quaternionf32) {
	car.position = position;
	car.orientation = orientation;

	car.velocity = VEC3_ZERO;
	car.angular_velocity = VEC3_ZERO;
}