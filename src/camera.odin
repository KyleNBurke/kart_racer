package main;

import "core:math";
import "core:math/linalg";
import "vendor:glfw";
import "math2";

TRANSLATION_SPEED :: 10.0;
ROTATION_SPEED :: 0.003;
MAX_VERTICAL_ROTATION_ANGLE :: 1.57;

HALO_RADIUS: f32 : 8.0;
HALO_HEIGHT: f32 : 15.0;
DOWNWARD_ANGLE: f32 : 0.7;

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

move_camera :: proc(using camera: ^Camera, window: glfw.WindowHandle, car: ^Car_Entity, dt: f32) {
	show_close_view :: proc() -> Maybe(f32) {
		axes := glfw.GetJoystickAxes(glfw.JOYSTICK_1);
	
		if len(axes) == 0 {
			return nil;
		}
	
		x := axes[2];
		y := axes[3];
	
		if x * x + y * y < 0.25 {
			return nil;
		}
	
		return math.atan2(-x, y) - math.PI;
	}

	#partial switch state {
	case .Follow_Car:
		halo_radius, halo_height, downward_angle: f32;

		forward := math2.matrix4_forward(car.transform);
		projection := linalg.normalize(linalg.Vector2f32 {forward.x, forward.z});

		if angle, ok := show_close_view().?; ok {
			halo_radius = CLOSE_HALO_RADIUS;
			halo_height = CLOSE_HALO_HEIGHT;
			downward_angle = CLOSE_DOWNWARD_ANGLE;

			projection = math2.vector2_rotate(projection, angle);
		} else {
			halo_radius = HALO_RADIUS;
			halo_height = HALO_HEIGHT;
			downward_angle = DOWNWARD_ANGLE;
		}

		halo_position := linalg.Vector3f32{-projection.x * halo_radius, halo_height, -projection.y * halo_radius};
		position = car.position + halo_position;

		angle := math.atan2(projection.x, projection.y);
		orientation_x = downward_angle;
		orientation_y = angle;
		orientation := linalg.quaternion_from_euler_angles(orientation_y, orientation_x, 0, .YXZ);

		transform = linalg.matrix4_from_trs_f32(position, orientation, linalg.Vector3f32 {1, 1, 1});
	
	case .First_Person:
		// Rotate
		mouse_pos_x_f64, mouse_pos_y_f64 := glfw.GetCursorPos(window);
		mouse_pos_x := f32(mouse_pos_x_f64);
		mouse_pos_y := f32(mouse_pos_y_f64);
		mouse_pos_diff_x := mouse_pos_x - prev_mouse_pos_x;
		mouse_pos_diff_y := mouse_pos_y - prev_mouse_pos_y;

		orientation_y -= mouse_pos_diff_x * ROTATION_SPEED;
		orientation_x += mouse_pos_diff_y * ROTATION_SPEED;
		orientation_x = clamp(orientation_x, -MAX_VERTICAL_ROTATION_ANGLE, MAX_VERTICAL_ROTATION_ANGLE);

		orientation := linalg.quaternion_from_euler_angles(orientation_y, orientation_x, 0, .YXZ);

		prev_mouse_pos_x = mouse_pos_x;
		prev_mouse_pos_y = mouse_pos_y;

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
			position += quaternion_transform_direction(orientation, dir_norm) * TRANSLATION_SPEED * dt;
		}

		transform = linalg.matrix4_from_trs_f32(position, orientation, linalg.Vector3f32 {1, 1, 1});
	}
}