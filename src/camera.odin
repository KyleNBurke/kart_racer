package main;

import "core:math";
import "core:math/linalg";
import "vendor:glfw";
import "math2";

TRANSLATION_SPEED :: 10.0;
ROTATION_SPEED :: 0.003;
MAX_VERTICAL_ROTATION_ANGLE :: 1.57;

HALO_RADIUS: f32 : 7.5;
HALO_HEIGHT: f32 : 10.0;
DOWNWARD_ANGLE: f32 : 0.6;

CLOSE_HALO_RADIUS: f32 : 6.0;
CLOSE_HALO_HEIGHT: f32 : 2.0;
CLOSE_DOWNWARD_ANGLE: f32 : 0.3;

Camera :: struct {
	position: linalg.Vector3f32,
	transform: linalg.Matrix4f32,
	fov: f32,
	projection: linalg.Matrix4f32,
	state: Camera_State,
	prev_mouse_pos_x: f32,
	prev_mouse_pos_y: f32,
	orientation_x: f32,
	orientation_y: f32,
	current_angle: f32,
}

Camera_State :: enum {
	Follow_Car,
	First_Person,
	Frozen,
}

init_camera :: proc(aspect, fov: f32, window: glfw.WindowHandle) -> Camera {
	mouse_pos_x, mouse_pos_y := glfw.GetCursorPos(window);

	return Camera {
		position = linalg.Vector3f32 {0.0, 0.0, 0.0},
		transform = linalg.MATRIX4F32_IDENTITY,
		fov = fov,
		projection = create_perspective_matrix(aspect, fov),
		state = .Follow_Car,
		prev_mouse_pos_x = f32(mouse_pos_x),
		prev_mouse_pos_y = f32(mouse_pos_y),
	};
}

create_perspective_matrix :: proc(aspect, fov: f32) -> linalg.Matrix4f32 {
	near: f32 : 0.1;
	far: f32 : 2000.0;

	f := math.tan(fov / 2.0 * math.PI / 180.0);
	d :: far - near;

	return linalg.Matrix4f32 {
		-1.0 / (f * aspect), 0.0, 0.0, 0.0,
		0.0, -1.0 / f, 0.0, 0.0,
		0.0, 0.0, far / d, -(far * near) / d,
		0.0, 0.0, 1.0, 0.0,
	};
}

update_aspect_ratio :: proc(using camera: ^Camera, aspect: f32) {
	projection = create_perspective_matrix(aspect, fov);
}

camera_handle_key_press :: proc(using camera: ^Camera, key: i32, window: glfw.WindowHandle) {
	switch key {
		case glfw.KEY_F1:
			state = .Follow_Car;
			glfw.SetInputMode(window, glfw.CURSOR, glfw.CURSOR_NORMAL);
		
		case glfw.KEY_F2:
			state = .First_Person;
			glfw.SetInputMode(window, glfw.CURSOR, glfw.CURSOR_DISABLED);

			mouse_pos_x, mouse_pos_y := glfw.GetCursorPos(window);
			prev_mouse_pos_x = f32(mouse_pos_x);
			prev_mouse_pos_y = f32(mouse_pos_y);
		
		case glfw.KEY_F3:
			state = .Frozen;
			glfw.SetInputMode(window, glfw.CURSOR, glfw.CURSOR_NORMAL);
	}
}

move_camera :: proc(camera: ^Camera, gamepad: ^Gamepad, window: glfw.WindowHandle, car: ^Car_Entity, dt: f32) {
	#partial switch camera.state {
	case .Follow_Car:
		close_angle: f32;
		{
			x := gamepad_axis_raw_pos(gamepad, 2);
			y := gamepad_axis_raw_pos(gamepad, 3);

			if x * x + y * y > 0.7 * 0.7 {
				close_angle = math.atan2(-x, y) - math.PI;
			}
		}

		position: linalg.Vector3f32;
		orientation: linalg.Quaternionf32;

		if close_angle == 0 {
			camera_forward := math2.matrix4_forward(camera.transform);
			camera_forward_proj := linalg.normalize(linalg.Vector2f32 {camera_forward.x, camera_forward.z});
			halo_position := linalg.Vector3f32{-camera_forward_proj.x * HALO_RADIUS, HALO_HEIGHT, -camera_forward_proj.y * HALO_RADIUS};
			position = car.position + halo_position;

			car_forward := math2.matrix4_forward(car.transform);
			car_forward_proj := linalg.normalize(linalg.Vector2f32 {car_forward.x, car_forward.z});
			target_angle := math.atan2(car_forward_proj.x, car_forward_proj.y);

			if abs(camera.current_angle) > math.PI / 2 {
				if target_angle > 0 && camera.current_angle < 0 {
					camera.current_angle += math.TAU;
				} else if target_angle < 0 && camera.current_angle > 0 {
					camera.current_angle -= math.TAU;
				}
			}
			
			camera.current_angle += (target_angle - camera.current_angle) * 7 * dt;
			orientation = linalg.quaternion_from_euler_angles(camera.current_angle, DOWNWARD_ANGLE, 0, .YXZ);

			// For transitioning to first person controls
			camera.position = position;
			camera.orientation_x = DOWNWARD_ANGLE;
			camera.orientation_y = camera.current_angle;
			
		} else {
			camera_forward := math2.matrix4_forward(car.transform);
			camera_forward_proj := linalg.normalize(linalg.Vector2f32 {camera_forward.x, camera_forward.z});
			camera_forward_proj = math2.vector2_rotate(camera_forward_proj, close_angle);
			halo_position := linalg.Vector3f32{-camera_forward_proj.x * CLOSE_HALO_RADIUS, CLOSE_HALO_HEIGHT, -camera_forward_proj.y * CLOSE_HALO_RADIUS};
			position = car.position + halo_position;

			angle := math.atan2(camera_forward_proj.x, camera_forward_proj.y);
			orientation = linalg.quaternion_from_euler_angles(angle, CLOSE_DOWNWARD_ANGLE, 0, .YXZ);
		}

		camera.transform = linalg.matrix4_from_trs_f32(position, orientation, linalg.Vector3f32 {1, 1, 1});
	
	case .First_Person:
		// Rotate
		mouse_pos_x_f64, mouse_pos_y_f64 := glfw.GetCursorPos(window);
		mouse_pos_x := f32(mouse_pos_x_f64);
		mouse_pos_y := f32(mouse_pos_y_f64);
		mouse_pos_diff_x := mouse_pos_x - camera.prev_mouse_pos_x;
		mouse_pos_diff_y := mouse_pos_y - camera.prev_mouse_pos_y;

		camera.orientation_y -= mouse_pos_diff_x * ROTATION_SPEED;
		camera.orientation_x += mouse_pos_diff_y * ROTATION_SPEED;
		camera.orientation_x = clamp(camera.orientation_x, -MAX_VERTICAL_ROTATION_ANGLE, MAX_VERTICAL_ROTATION_ANGLE);

		orientation := linalg.quaternion_from_euler_angles(camera.orientation_y, camera.orientation_x, 0, .YXZ);

		camera.prev_mouse_pos_x = mouse_pos_x;
		camera.prev_mouse_pos_y = mouse_pos_y;

		// Translate
		dir := linalg.Vector3f32 {};

		if glfw.GetKey(window, glfw.KEY_W) == glfw.PRESS {
			dir.z += 1.0;
		}

		if glfw.GetKey(window, glfw.KEY_S) == glfw.PRESS {
			dir.z -= 1.0;
		}

		if glfw.GetKey(window, glfw.KEY_A) == glfw.PRESS {
			dir.x += 1.0;
		}

		if glfw.GetKey(window, glfw.KEY_D) == glfw.PRESS {
			dir.x -= 1.0;
		}

		if glfw.GetKey(window, glfw.KEY_E) == glfw.PRESS {
			dir.y += 1.0;
		}

		if glfw.GetKey(window, glfw.KEY_Q) == glfw.PRESS {
			dir.y -= 1.0;
		}

		if linalg.length2(dir) != 0.0 {
			dir_norm := linalg.normalize(dir);
			camera.position += math2.quaternion_transform_direction(orientation, dir_norm) * TRANSLATION_SPEED * dt;
		}

		camera.transform = linalg.matrix4_from_trs_f32(camera.position, orientation, linalg.Vector3f32 {1, 1, 1});
	}
}