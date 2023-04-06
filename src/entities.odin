package main;

import "core:math/linalg";
import "core:slice";
import "core:math";
import "math2";

Entity :: struct {
	position: linalg.Vector3f32,
	orientation: linalg.Quaternionf32,
	size: linalg.Vector3f32,
	transform: linalg.Matrix4x4f32,
	collision_hulls: [dynamic]Collision_Hull,
	bounds: math2.Box3f32,
	query_run: u32,
	variant: union {^Inanimate_Entity, ^Rigid_Body_Entity, ^Car_Entity},
}

Inanimate_Entity :: struct {
	using entity: Entity,
}

// Rename?
Status_Effect :: enum {
	None,
	Shock,
	Fire,
	ExplodingShock,
}

Rigid_Body_Entity :: struct {
	using entity: Entity,
	checked_collision: bool,
	mass: f32,
	tentative_transform: linalg.Matrix4f32,
	inv_local_inertia_tensor: linalg.Matrix3f32,
	inv_global_inertia_tensor: linalg.Matrix3f32,
	velocity: linalg.Vector3f32,
	angular_velocity: linalg.Vector3f32,
	new_position: linalg.Vector3f32,
	collision_exclude: bool,
	island_index: int,
	sleep_duration: f32,

	// I get not wanting to separate shock cubes from shock barrels due to the [dynamic]particle needed to be in both but what if I pull out the things below this into Rigid_Body_Status_Effect_Entity?
	// We should hold off on this because we may want status effects for inanimate entities which would mean putting these things into the Entity anyway.
	status_effect: Status_Effect,
	shock_particles: [dynamic]Shock_Particle,
	fire_particles: [dynamic]Fire_Particle,
	exploding_health: f32,
}

Car_Entity :: struct {
	using entity: Entity,
	inv_global_inertia_tensor: linalg.Matrix3f32,
	velocity: linalg.Vector3f32,
	angular_velocity: linalg.Vector3f32,
	new_position: linalg.Vector3f32,
	new_transform: linalg.Matrix4f32,
	shocked: bool,
	shock_remaining_time: f32,
	on_fire: bool,
	on_fire_remaining_time: f32,
	shock_elapsed_ramp_down_time: f32,
	on_fire_elapsed_ramp_up_time: f32,
	wheel_radius: f32,
	wheels: [4]Wheel,
	current_steer_angle: f32,
	front_wheel_angular_velocity,
	back_wheel_angular_velocity,
	front_wheel_orientation,
	back_wheel_orientation: f32,
	shock_particles: [dynamic]Shock_Particle,
	fire_particles: [dynamic]Fire_Particle,

	forward_helper_geo,
	steer_angle_helper_geo: Geometry_Lookup,
}

Wheel :: struct {
	entity_lookup: Entity_Lookup,
	body_point: linalg.Vector3f32,
	contact_normal: Maybe(linalg.Vector3f32),
	spring_length: f32,
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
	position := linalg.Vector3f32 {0.0, 0.0, 0.0},
	orientation := linalg.QUATERNIONF32_IDENTITY,
	size := linalg.Vector3f32 {1.0, 1.0, 1.0},
	mass: f32,
	dimensions: linalg.Vector3f32,
	status_effect: Status_Effect = .None,
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
	e.island_index = -1;
	e.status_effect = status_effect;
	e.exploding_health = 100;

	return e;
}

CAR_MASS: f32 : 1000;
CAR_K :: CAR_MASS / 12;
CAR_WIDTH :: 2.0;
CAR_HEIGHT :: 1.2;
CAR_DEPTH :: 3.5;

CAR_W :: CAR_K * (CAR_DEPTH * CAR_DEPTH + CAR_HEIGHT * CAR_HEIGHT);
CAR_H :: CAR_K * (CAR_WIDTH * CAR_WIDTH + CAR_DEPTH * CAR_DEPTH);
CAR_D :: CAR_K * (CAR_WIDTH * CAR_WIDTH + CAR_HEIGHT * CAR_HEIGHT);

CAR_INV_LOCAL_INERTIA_TENSOR :: linalg.Matrix3f32 {
	1.0 / CAR_W, 0.0, 0.0,
	0.0, 1.0 / CAR_H, 0.0,
	0.0, 0.0, 1.0 / CAR_D,
};

new_car_entity :: proc(position: linalg.Vector3f32, orientation: linalg.Quaternionf32) -> ^Car_Entity {
	e := new(Car_Entity);
	e.position = position;
	e.orientation =  orientation;
	e.size = linalg.Vector3f32 {1, 1, 1};
	e.transform = linalg.matrix4_from_trs_f32(position, orientation, linalg.Vector3f32 {1, 1, 1});
	e.variant = e;
	e.inv_global_inertia_tensor = linalg.MATRIX3F32_IDENTITY;
	e.new_transform = linalg.MATRIX4F32_IDENTITY;

	return e;
}

// add_hull_to_rigid_body :: proc(lookup: Entity_Lookup, collision_hull_grid: ^Collision_Hull_Grid, rigid_body: ^Rigid_Body_Entity, hull: Collision_Hull) {
// 	append(&rigid_body.collision_hulls, hull);
// 	hull_ptr := slice.last_ptr(rigid_body.collision_hulls[:]);
// 	hull_record := insert_into_collision_hull_grid(collision_hull_grid, lookup, hull_ptr);
// 	append(&rigid_body.collision_hull_record_indices, hull_record);
// }