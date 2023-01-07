package main;

import "core:math/linalg";

Entity :: struct {
	position: linalg.Vector3f32,
	orientation: linalg.Quaternionf32,
	size: linalg.Vector3f32,
	transform: linalg.Matrix4x4f32,
	collision_hull_record_indices: [dynamic]int,
	variant: union {^Inanimate_Entity, ^Rigid_Body_Entity},
}

Inanimate_Entity :: struct {
	using entity: Entity,
}

Rigid_Body_Entity :: struct {
	using entity: Entity,
	mass: f32,
	inv_local_inertia_tensor: linalg.Matrix3f32,
	inv_global_inertia_tensor: linalg.Matrix3f32,
	velocity: linalg.Vector3f32,
	angular_velocity: linalg.Vector3f32,
	new_position: linalg.Vector3f32,
	new_transform: linalg.Matrix4f32,
	collision_exclude: bool,
}

update_entity_transform :: proc(using entity: ^Entity) {
	transform = linalg.matrix4_from_trs(position, orientation, size);
}

new_inanimate_entity :: proc(
	position := linalg.Vector3f32 {0.0, 0.0, 0.0},
	orientation := linalg.QUATERNIONF32_IDENTITY,
	size := linalg.Vector3f32 {1.0, 1.0, 1.0},
) -> ^Inanimate_Entity {
	e := new(Inanimate_Entity);
	e.position = position;
	e.orientation = orientation;
	e.size = size;
	e.transform = linalg.matrix4_from_trs(position, orientation, size);
	e.variant = e;

	return e;
}

new_rigid_body_entity :: proc(
	position := linalg.Vector3f32 {0.0, 0.0, 0.0 },
	orientation := linalg.QUATERNIONF32_IDENTITY,
	size := linalg.Vector3f32 {1.0, 1.0, 1.0},
	mass: f32,
	dimensions: linalg.Vector3f32,
) -> ^Rigid_Body_Entity {
	k := mass / 12.0;
	width  := dimensions.x;
	height := dimensions.y;
	depth  := dimensions.z;

	w := k * (depth * depth + height * height);
	h := k * (width * width + depth * depth);
	d := k * (width * width + height * height);

	inv_local_inertia_tensor := linalg.Matrix3f32 {
		1.0 / w, 0.0, 0.0,
		0.0, 1.0 / h, 0.0,
		0.0, 0.0, 1.0 / d,
	};

	e := new(Rigid_Body_Entity);
	e.position = position;
	e.orientation = orientation;
	e.size = size;
	e.transform = linalg.matrix4_from_trs_f32(position, orientation, size);
	e.variant = e;
	e.mass = mass;
	e.inv_local_inertia_tensor = inv_local_inertia_tensor;
	e.inv_global_inertia_tensor = linalg.MATRIX3F32_IDENTITY;
	e.new_transform = linalg.MATRIX4F32_IDENTITY;

	return e;
}

update_rigid_body_inv_global_inertia_tensor :: proc(using rigid_body: ^Rigid_Body_Entity, orientation: linalg.Quaternionf32) {
	m := linalg.matrix3_from_quaternion(orientation);
	inv_global_inertia_tensor = m * inv_local_inertia_tensor * linalg.transpose(m);
}