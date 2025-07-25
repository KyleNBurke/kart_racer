package main;

import "core:math/linalg";
import "core:strings";
import "math2";

Entity :: struct {
	name: string,
	free: bool,
	generation: u32,
	geometry_lookup: Maybe(Geometry_Lookup),
	scene_associated: bool,
	position: linalg.Vector3f32,
	orientation: linalg.Quaternionf32,
	size: linalg.Vector3f32,
	transform: linalg.Matrix4x4f32,
	collision_hulls: [dynamic]Collision_Hull,
	bounds: math2.Box3f32,
	query_run: u32,
	variant: union {
		^Inanimate_Entity,
		^Rigid_Body_Entity,
		^Car_Entity,
		^Cloud_Entity,
		^Oil_Slick_Entity,
		^Bumper_Entity,
		^Boost_Jet_Entity,
	},
}

Inanimate_Entity :: struct {
	using entity: Entity,
}

Cloud_Entity :: struct {
	using entity: Entity,
	status_effect: Cloud_Status_Effect,
	particles: [dynamic]Particle,
	ramp_up_duration: f32,
}

Cloud_Status_Effect :: enum { Shock }

Rigid_Body_Entity :: struct {
	using entity: Entity,
	checked_collision: bool,
	mass: f32,
	tentative_position: linalg.Vector3f32,
	tentative_transform: linalg.Matrix4f32,
	inv_local_inertia_tensor: linalg.Matrix3f32,
	tentative_inv_global_inertia_tensor: linalg.Matrix3f32,
	velocity: linalg.Vector3f32,
	angular_velocity: linalg.Vector3f32,
	bias_velocity: linalg.Vector3f32,
	bias_angular_velocity: linalg.Vector3f32,
	collision_exclude: bool,
	island_index: int,
	sleep_duration: f32,

	status_effect: Status_Effect,
	particles: [dynamic]Particle,
	exploding_health: int,
	emissive_color: [3]f32,
	emissive_pulse_duration: f32,
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
	checked_collision: bool,
	tentative_inv_global_inertia_tensor: linalg.Matrix3f32,
	velocity: linalg.Vector3f32,
	angular_velocity: linalg.Vector3f32,
	bias_velocity: linalg.Vector3f32,
	bias_angular_velocity: linalg.Vector3f32,
	tentative_position: linalg.Vector3f32,
	tentative_transform: linalg.Matrix4f32,
	weight_distribution_multiplier: f32,
	shocked: bool,
	shock_remaining_time: f32,
	on_fire: bool,
	on_fire_remaining_time: f32,
	shock_elapsed_ramp_down_time: f32,
	on_fire_elapsed_ramp_up_time: f32,
	wheel_radius: f32, // #todo: Pull this out
	wheels: [4]Wheel,
	surface_normal: linalg.Vector3f32,
	input_accel_multiplier: f32,
	input_steer_multiplier: f32,
	input_handbreak: bool,
	sliding: bool,
	handbrake_duration: f32,
	finished_slide: bool,
	current_steer_angle: f32,
	wheel_orientation: f32,
	shock_particles: [dynamic]Particle,
	fire_particles: [dynamic]Particle,
	surface_type: Surface_Type,
	left_segment: int,
	right_segment: int,

	// AI
	center_multiplier: f32, // [0, 1]

	// Helpers
	forward_helper_geo,
	steer_angle_helper_geo: Geometry_Lookup,
	helpers: [dynamic]Geometry_Lookup,
	origin,
	closest_left, closest_right,
	extended_left, extended_right,
	target_point,
	tangent_1, tangent_2,
	max_l, max_r: linalg.Vector3f32,
	ray_bounds: math2.Box3f32,
	start_zone_angle, end_zone_angle: Maybe(f32),
	surface_forward: linalg.Vector3f32,
	target_angle: f32,
}

Wheel :: struct {
	entity_lookup: Entity_Lookup,
	body_point: linalg.Vector3f32,
	contact_normal: linalg.Vector3f32,
	spring_length: f32,
}

Oil_Slick_Entity :: struct {
	using entity: Entity,
	on_fire: bool,
	fire_particles: [dynamic]Particle,
	ramp_up_duration: f32,
	desired_fire_particles: int,
}

Bumper_Entity :: struct {
	using entity: Entity,
	animating: bool,
	animation_duration: f32,
}

Boost_Jet_Entity :: struct {
	using entity: Entity,
	particles: [dynamic]Particle,
}

update_entity_transform :: proc(using entity: ^Entity) {
	transform = linalg.matrix4_from_trs(position, orientation, size);
}

init_rigid_body_entity :: proc(entity: ^Rigid_Body_Entity, mass: f32, dimensions: linalg.Vector3f32) {
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
	
	entity.mass = mass;
	entity.inv_local_inertia_tensor = inv_local_inertia_tensor;
	entity.tentative_inv_global_inertia_tensor = linalg.MATRIX3F32_IDENTITY;
	entity.island_index = -1;
}

CAR_MASS: f32 : 500;
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

init_car_entity :: proc(entity: ^Car_Entity) {
	entity.tentative_inv_global_inertia_tensor = linalg.MATRIX3F32_IDENTITY;
	entity.tentative_transform = linalg.MATRIX4F32_IDENTITY;
	entity.handbrake_duration = 10; // If this were to be initialized at 0, the car would be sliding.
}