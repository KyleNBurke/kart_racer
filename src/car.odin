package main;

import "vendor:glfw";
import "core:math";
import "core:math/linalg";
import "math2";

import "core:fmt"; //

Car_Helpers :: struct {
	forward_geo_lookup,
	front_tire_dir_geo_lookup: Geometry_Lookup,
}

init_car_helpers :: proc(entities_geos: ^Entities_Geos) -> Car_Helpers {
	using car_helpers: Car_Helpers;

	forward_geo: Geometry;
	forward_geo_lookup = add_geometry(entities_geos, forward_geo, .Render);

	front_tire_dir_geo: Geometry;
	front_tire_dir_geo_lookup = add_geometry(entities_geos, front_tire_dir_geo, .Render);

	return car_helpers;
}

move_car :: proc(window: glfw.WindowHandle, car: ^Car_Entity, dt: f32, entities_geos: ^Entities_Geos, car_helpers: ^Car_Helpers) {
	M :: 1.0 / 12.0;
	CAR_W :: M * (CAR_DEPTH * CAR_DEPTH + CAR_HEIGHT * CAR_HEIGHT);
	CAR_H :: M * (CAR_WIDTH * CAR_WIDTH + CAR_DEPTH * CAR_DEPTH);
	CAR_D :: M * (CAR_WIDTH * CAR_WIDTH + CAR_HEIGHT * CAR_HEIGHT);

	INV_LOCAL_INERTIA_TENSOR :: linalg.Matrix3f32 {
		1.0 / CAR_W, 0.0, 0.0,
		0.0, 1.0 / CAR_H, 0.0,
		0.0, 0.0, 1.0 / CAR_D,
	};

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

	{ // Calculate a value between -1 and 1 to determine the desired cornering angle
		if glfw.GetKey(window, glfw.KEY_A) == glfw.PRESS do steer_multiplier += 1;
		if glfw.GetKey(window, glfw.KEY_D) == glfw.PRESS do steer_multiplier -= 1;

		if len(axes) > 0 {
			left_stick_pos := axes[0];

			if abs(left_stick_pos) > 0.25 {
				steer_multiplier = -(left_stick_pos - 0.25 * math.sign(left_stick_pos)) / 0.75;
			}
		}
	}

	body_forward := math2.matrix4_forward(car.transform);
	body_up := math2.matrix4_up(car.transform);
	body_velocity := car.velocity;
	body_angular_velocity := car.angular_velocity;
	global_inv_inertia_tensor := math2.calculate_inv_global_inertia_tensor(car.orientation, INV_LOCAL_INERTIA_TENSOR);
	MAX_FRICTION: f32 : 30;

	front_left_contact, front_left_contact_ok := car.wheels[0].contact.?;
	front_right_contact, front_right_contact_ok := car.wheels[1].contact.?;

	if front_left_contact_ok || front_right_contact_ok {
		front_surface_normal := linalg.normalize(front_left_contact.normal + front_right_contact.normal);

		car.steer_angle = steer_multiplier * 0.2;
		front_tire_dir := math2.vector_rotate(body_forward, body_up, car.steer_angle);
		front_tire_lat_dir := linalg.normalize(linalg.cross(front_surface_normal, front_tire_dir));
		front_tire_vel := body_velocity + linalg.cross(body_angular_velocity, body_forward * SPRING_BODY_POINT_Z);
		front_tire_lat_vel := linalg.dot(front_tire_vel, front_tire_lat_dir);
		front_tire_fric := clamp(-front_tire_lat_vel / 2 / dt, -MAX_FRICTION, MAX_FRICTION) * dt;

		car.velocity += front_tire_lat_dir * front_tire_fric;
		car.angular_velocity += global_inv_inertia_tensor * body_up * front_tire_fric;
		
		front_tire_dir_helper_geo := get_geometry(entities_geos, car_helpers.front_tire_dir_geo_lookup);
		set_line_helper(front_tire_dir_helper_geo,car.position, front_tire_dir * 3);
	}

	back_left_contact, back_left_contact_ok := car.wheels[2].contact.?;
	back_right_contact, back_right_contact_ok := car.wheels[3].contact.?;

	if back_left_contact_ok || back_right_contact_ok {
		back_surface_normal := linalg.normalize(back_left_contact.normal + back_right_contact.normal);

		back_tire_lat_dir := linalg.normalize(linalg.cross(back_surface_normal, body_forward));
		back_tire_vel := body_velocity + linalg.cross(body_angular_velocity, -body_forward * SPRING_BODY_POINT_Z);
		back_tire_lat_vel := linalg.dot(back_tire_vel, back_tire_lat_dir);
		back_tire_fric := clamp(-back_tire_lat_vel / 2 / dt, -MAX_FRICTION, MAX_FRICTION) * dt;

		car.velocity += back_tire_lat_dir * back_tire_fric;
		car.angular_velocity += global_inv_inertia_tensor * -body_up * back_tire_fric;
	}

	car.velocity += body_forward * accel_multiplier * 20.0 * dt;

	forward_helper_geo := get_geometry(entities_geos, car_helpers.forward_geo_lookup);
	set_line_helper(forward_helper_geo, car.position, body_forward * 3);
}