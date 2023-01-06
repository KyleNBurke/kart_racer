package main;

import "core:math";
import "core:math/linalg";
import "vendor:glfw";

TRANSLATION_SPEED :: 10.0;
ROTATION_SPEED :: 0.003;
MAX_VERTICAL_ROTATION_ANGLE :: 1.57;

Camera :: struct {
	position: linalg.Vector3f32,
	transform: linalg.Matrix4f32,
	fov: f32,
	projection: linalg.Matrix4f32,
	prev_mouse_pos_x: f32,
	prev_mouse_pos_y: f32,
	orientation_x: f32,
	orientation_y: f32,
}

init_camera :: proc(aspect, fov: f32, window: glfw.WindowHandle) -> Camera {
	mouse_pos_x, mouse_pos_y := glfw.GetCursorPos(window);

	return Camera {
		position = linalg.Vector3f32 {0.0, 0.0, 0.0},
		transform = linalg.MATRIX4F32_IDENTITY,
		fov = fov,
		projection = create_perspective_matrix(aspect, fov),
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

move_camera :: proc(using camera: ^Camera, window: glfw.WindowHandle, dt: f32) {
	// Rotate
	mouse_pos_x_f64, mouse_pos_y_f64 := glfw.GetCursorPos(window);
	mouse_pos_x := f32(mouse_pos_x_f64);
	mouse_pos_y := f32(mouse_pos_y_f64);
	mouse_pos_diff_x := mouse_pos_x - prev_mouse_pos_x;
	mouse_pos_diff_y := mouse_pos_y - prev_mouse_pos_y;

	orientation_y -= mouse_pos_diff_x * ROTATION_SPEED;
	orientation_x += mouse_pos_diff_y * ROTATION_SPEED;
	orientation_x = clamp(orientation_x, -MAX_VERTICAL_ROTATION_ANGLE, MAX_VERTICAL_ROTATION_ANGLE);

	orientation := linalg.quaternion_from_euler_angles(orientation_y, orientation_x, 0.0, .YXZ);

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

	if linalg.length(dir) != 0.0 {
		dir_norm := linalg.normalize(dir);
		position += quaternion_transform_direction(orientation, dir_norm) * TRANSLATION_SPEED * dt;
	}

	transform = linalg.matrix4_from_trs_f32(position, orientation, linalg.Vector3f32 {1.0, 1.0, 1.0});
}