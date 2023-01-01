package entity;

import "core:math/linalg";

Entity :: struct {
	position: linalg.Vector3f32,
	orientation: linalg.Quaternionf32,
	size: linalg.Vector3f32,
	transform: linalg.Matrix4x4f32,
}

// Remove this
DEFAULT_ENTITY :: Entity {
	position = linalg.Vector3f32 {0.0, 0.0, 0.0},
	orientation = linalg.QUATERNIONF32_IDENTITY,
	size = linalg.Vector3f32 {1.0, 1.0, 1.0},
	transform = linalg.MATRIX4F32_IDENTITY,
}

// Remove this
init_entity :: proc(
	position := linalg.Vector3f32 {0.0, 0.0, 0.0},
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

update_entity_transform_mat :: proc(using entity: ^Entity) {
	transform = linalg.matrix4_from_trs_f32(position, orientation, size);
}

InanimateEntity :: distinct Entity;

RigidBodyEntity :: struct {
	using entity: Entity,
	mass: f32,
	inv_local_inertia_tensor: linalg.Matrix3f32,
	inv_global_inertia_tensor: linalg.Matrix3f32,
	velocity: linalg.Vector3f32,
	angular_velocity: linalg.Vector3f32,
	new_position: linalg.Vector3f32,
	collision_exclude: bool,
}

init_inanimate_entity :: proc(
	position := linalg.Vector3f32 {0.0, 0.0, 0.0},
	orientation := linalg.QUATERNIONF32_IDENTITY,
	size := linalg.Vector3f32 {1.0, 1.0, 1.0},
) -> InanimateEntity {
	transform := linalg.matrix4_from_trs_f32(position, orientation, size);

	return InanimateEntity {
		position,
		orientation,
		size,
		transform,
	};
}

init_rigid_body_entity :: proc(
	position := linalg.Vector3f32 {0.0, 0.0, 0.0 },
	orientation := linalg.QUATERNIONF32_IDENTITY,
	size := linalg.Vector3f32 {1.0, 1.0, 1.0},
	mass: f32,
	dimensions: linalg.Vector3f32,
) -> RigidBodyEntity {
	transform := linalg.matrix4_from_trs_f32(position, orientation, size);

	e := mass / 12.0;
	width  := dimensions.x;
	height := dimensions.y;
	depth  := dimensions.z;

	w := e * (depth * depth + height * height);
	h := e * (width * width + depth * depth);
	d := e * (width * width + height * height);

	inv_local_inertia_tensor := linalg.Matrix3f32 {
		1.0 / w, 0.0, 0.0,
		0.0, 1.0 / h, 0.0,
		0.0, 0.0, 1.0 / d,
	};

	return RigidBodyEntity {
		entity = Entity {
			position = position,
			orientation = orientation,
			size = size,
			transform = transform,
		},
		mass = mass,
		inv_local_inertia_tensor = inv_local_inertia_tensor,
		inv_global_inertia_tensor = linalg.MATRIX3F32_IDENTITY,
		velocity = linalg.Vector3f32 {0.0, 0.0, 0.0},
		angular_velocity = linalg.Vector3f32 {0.0, 0.0, 0.0},
		new_position = linalg.Vector3f32 {0.0, 0.0, 0.0},
		collision_exclude = false,
	};
}

update_rigid_body_inv_global_inertia_tensor :: proc(using rigid_body: ^RigidBodyEntity, rotation: linalg.Quaternionf32) {
	m := linalg.matrix3_from_quaternion(rotation);
	inv_global_inertia_tensor = m * inv_local_inertia_tensor * linalg.transpose(m);
}