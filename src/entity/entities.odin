package entity;

import "core:math/linalg";

Entity :: struct {
	position: linalg.Vector3f32,
	orientation: linalg.Quaternionf32,
	size: linalg.Vector3f32,
	transform: linalg.Matrix4x4f32,
}

DEFAULT_ENTITY :: Entity {
	position = linalg.Vector3f32 {0.0, 0.0, 0.0 },
	orientation = linalg.QUATERNIONF32_IDENTITY,
	size = linalg.Vector3f32 {1.0, 1.0, 1.0},
	transform = linalg.MATRIX4F32_IDENTITY,
}

init_entity :: proc(
	position := linalg.Vector3f32 {0.0, 0.0, 0.0 },
	orientation := linalg.QUATERNIONF32_IDENTITY,
	size := linalg.Vector3f32 {1.0, 1.0, 1.0},
) -> Entity {
	transform := linalg.matrix4_from_trs_f32(position, orientation, size);

	return Entity {
		position,
		orientation,
		size,
		transform,
	};
}

update_transform_mat :: proc(using entity: ^Entity) {
	transform = linalg.matrix4_from_trs_f32(position, orientation, size);
}

InanimateEntity :: struct {
	using entity: Entity,
}