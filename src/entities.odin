package main;

import "core:math/linalg";
import "core:strings";
import "math2";

Entity :: struct {
	lookup: Entity_Lookup,
	name: string,
	position: linalg.Vector3f32,
	orientation: linalg.Quaternionf32,
	size: linalg.Vector3f32,
	transform: linalg.Matrix4x4f32,
	collision_hulls: [dynamic]Collision_Hull,
	bounds: math2.Box3f32,
	query_run: u32,
	variant: union {^Inanimate_Entity, ^Rigid_Body_Entity, ^Car_Entity, ^Cloud_Entity, ^Oil_Slick_Entity},
}

Inanimate_Entity :: struct {
	using entity: Entity,
}

Cloud_Entity :: struct {
	using entity: Entity,
	status_effect: Cloud_Status_Effect,
	particles: [dynamic]Status_Effect_Particle,
	ramp_up_duration: f32,
}

Cloud_Status_Effect :: enum { Shock }

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
	shock_particles: [dynamic]Status_Effect_Particle,
	fire_particles: [dynamic]Status_Effect_Particle,
	exploding_health: f32,
}

Status_Effect :: enum {
	None,
	Shock,
	Fire,
	ExplodingShock,
	ExplodingFire,
}

Surface_Type :: enum { Normal, Oil }

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
	shock_particles: [dynamic]Status_Effect_Particle,
	fire_particles: [dynamic]Status_Effect_Particle,
	surface_type: Surface_Type,

	forward_helper_geo,
	steer_angle_helper_geo: Geometry_Lookup,
}

Wheel :: struct {
	entity_lookup: Entity_Lookup,
	body_point: linalg.Vector3f32,
	contact_normal: Maybe(linalg.Vector3f32),
	spring_length: f32,
}

Oil_Slick_Entity :: struct {
	using entity: Entity,
	on_fire: bool,
	fire_particles: [dynamic]Status_Effect_Particle,
	ramp_up_duration: f32,
	desired_fire_particles: int,
}

init_entity :: proc(e: ^Entity, name: string, position: linalg.Vector3f32, orientation: linalg.Quaternionf32, size: linalg.Vector3f32) {
	e.name = strings.clone(name);
	e.position = position;
	e.orientation = orientation;
	e.size = size;
	e.transform = linalg.matrix4_from_trs(position, orientation, size);
}

update_entity_transform :: proc(using entity: ^Entity) {
	transform = linalg.matrix4_from_trs(position, orientation, size);
}

new_inanimate_entity :: proc(
	name: string,
	position := linalg.Vector3f32 {0.0, 0.0, 0.0},
	orientation := linalg.QUATERNIONF32_IDENTITY,
	size := linalg.Vector3f32 {1.0, 1.0, 1.0},
) -> ^Inanimate_Entity {
	e := new(Inanimate_Entity);
	e.variant = e;
	init_entity(e, name, position, orientation, size);

	return e;
}

new_cloud_entity :: proc(position: linalg.Vector3f32, status_effect: Cloud_Status_Effect) -> ^Cloud_Entity {
	e := new(Cloud_Entity);
	e.variant = e;
	init_entity(e, "cloud", position, linalg.QUATERNIONF32_IDENTITY, linalg.Vector3f32 {1, 1, 1});

	e.status_effect = status_effect;

	return e;
}

new_rigid_body_entity :: proc(
	name: string,
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
	e.variant = e;
	init_entity(e, name, position, orientation, size);
	
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
	e.variant = e;
	init_entity(e, "car", position, orientation, linalg.Vector3f32 {1, 1, 1});
	
	e.inv_global_inertia_tensor = linalg.MATRIX3F32_IDENTITY;
	e.new_transform = linalg.MATRIX4F32_IDENTITY;

	return e;
}

new_oil_slick_entity :: proc(
	name: string,
	position: linalg.Vector3f32,
	orientation: linalg.Quaternionf32,
	size: linalg.Vector3f32,
	desired_fire_paricles: int,
) -> ^Oil_Slick_Entity {
	e := new(Oil_Slick_Entity);
	e.variant = e;
	init_entity(e, name, position, orientation, size);

	e.desired_fire_particles = desired_fire_paricles;

	return e;
}