package main;

import "core:math";
import "core:math/linalg";

Camera :: struct {
	position: linalg.Vector3f32,
	orientation: linalg.Quaternionf32,
	transform: linalg.Matrix4f32,
	fov: f32,
	projection: linalg.Matrix4f32,
}

init_camera :: proc(aspect, fov: f32) -> Camera {
	return Camera {
		position = linalg.Vector3f32 {0.0, 0.0, 0.0},
		orientation = linalg.QUATERNIONF32_IDENTITY,
		transform = linalg.MATRIX4F32_IDENTITY,
		fov = fov,
		projection = create_perspective_matrix(aspect, fov),
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