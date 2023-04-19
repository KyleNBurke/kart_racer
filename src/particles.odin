package main;

import "core:slice";
import "core:math";
import "core:math/linalg";
import "core:math/rand";
import "math2";

import "core:fmt";

SHOCK_PARTICLE_MAX_OFFSET :: 1.4;

Shock_Particle :: struct {
	using particle: Particle,
	local_position: linalg.Vector3f32,
	velocity: linalg.Vector3f32,
	life_time: f32,
	time_alive: f32,
}

Fire_Particle :: struct {
	using particle: Particle,
	velocity: linalg.Vector3f32,
	life_time: f32,
	time_alive: f32,
}

init_shock_particles :: proc(shock_entities: []Entity_Lookup) {
	for lookup in shock_entities {
		rigid_body := get_entity(lookup).variant.(^Rigid_Body_Entity);

		for _ in 0..<150 {
			particle: Shock_Particle;
			particle.size = SHOCK_PARTICLE_SIZE;
			
			append(&rigid_body.shock_particles, particle);
		}
	}
}

init_fire_particles :: proc(fire_entities: []Entity_Lookup) {
	for lookup in fire_entities {
		rigid_body := get_entity(lookup).variant.(^Rigid_Body_Entity);

		for _ in 0..<200 {
			particle: Fire_Particle;
			append(&rigid_body.fire_particles, particle);
		}
	}
}

cleanup_shock_entity_particles :: proc(shock_entities: []Entity_Lookup) {
	for lookup in shock_entities {
		rigid_body := get_entity(lookup).variant.(^Rigid_Body_Entity);
		delete(rigid_body.shock_particles);
	}
}

cleanup_fire_entity_particles :: proc(fire_entities: []Entity_Lookup) {
	for lookup in fire_entities {
		rigid_body := get_entity(lookup).variant.(^Rigid_Body_Entity);
		delete(rigid_body.fire_particles);
	}
}

remove_from_shock_entites :: proc(shock_entities: ^[dynamic]Entity_Lookup, lookup: Entity_Lookup) {
	i, ok := slice.linear_search(shock_entities[:], lookup);
	assert(ok);
	unordered_remove(shock_entities, i);
}

update_shock_entity_particles :: proc(shock_entities: []Entity_Lookup, dt: f32) {
	for lookup in shock_entities {
		rigid_body := get_entity(lookup).variant.(^Rigid_Body_Entity);

		for particle in &rigid_body.shock_particles {
			dist := linalg.abs(particle.position - rigid_body.position);

			if dist.x > SHOCK_PARTICLE_MAX_OFFSET || dist.y > SHOCK_PARTICLE_MAX_OFFSET || dist.z > SHOCK_PARTICLE_MAX_OFFSET {
				reset_shock_particle(rigid_body, &particle);
			}

			update_shock_particle(rigid_body.velocity, &particle, dt);
		}
	}
}

update_shock_particle :: proc(body_velocity: linalg.Vector3f32, particle: ^Shock_Particle, dt: f32) {
	MAX_VEL_CHANGE :: 1;
	MAX_VEL :: 2;

	particle.velocity.x += rand.float32_range(-MAX_VEL_CHANGE, MAX_VEL_CHANGE);
	particle.velocity.y += rand.float32_range(-MAX_VEL_CHANGE, MAX_VEL_CHANGE);
	particle.velocity.z += rand.float32_range(-MAX_VEL_CHANGE, MAX_VEL_CHANGE);

	particle.velocity.x = clamp(particle.velocity.x, -MAX_VEL, MAX_VEL);
	particle.velocity.y = clamp(particle.velocity.y, -MAX_VEL, MAX_VEL);
	particle.velocity.z = clamp(particle.velocity.z, -MAX_VEL, MAX_VEL);

	particle.position += (body_velocity + particle.velocity) * dt;

	life_time_multiplier := math.mod_f32(particle.time_alive, SHOCK_PARTICLE_COLOR_FADE_TIME) / SHOCK_PARTICLE_COLOR_FADE_TIME;

	h: f32;
	s: f32;
	if particle.time_alive < SHOCK_PARTICLE_COLOR_FADE_TIME / 4 {
		h = 62;
		s = math.lerp(f32(1), f32(0), life_time_multiplier);
	} else {
		h = 235;
		s = math.lerp(f32(0), f32(1), life_time_multiplier);
	}

	v : f32 : 1.0;

	r, g, b := math2.hsv_to_rgb(h, s, v);
	particle.color = [3]f32 {r, g, b};

	particle.time_alive += dt;
}

@(private="file")
reset_shock_particle :: proc(rigid_body: ^Rigid_Body_Entity, particle: ^Shock_Particle) {
	offset_x := rand.float32_range(-SHOCK_PARTICLE_MAX_OFFSET, SHOCK_PARTICLE_MAX_OFFSET);
	offset_y := rand.float32_range(-SHOCK_PARTICLE_MAX_OFFSET, SHOCK_PARTICLE_MAX_OFFSET);
	offset_z := rand.float32_range(-SHOCK_PARTICLE_MAX_OFFSET, SHOCK_PARTICLE_MAX_OFFSET);
	particle.position = rigid_body.position + linalg.Vector3f32 {offset_x, offset_y, offset_z};

	particle.time_alive = 0;
}

update_fire_entity_particles :: proc(fire_entities: []Entity_Lookup, dt: f32) {
	MAX_OFFSET :: 1.1;
	DRAG :: 20;

	for lookup in fire_entities {
		rigid_body := get_entity(lookup).variant.(^Rigid_Body_Entity);

		for particle in &rigid_body.fire_particles {
			if particle.time_alive >= particle.life_time {
				reset_fire_particle(rigid_body, &particle);
			}

			update_fire_particle(&particle, dt);
		}
	}
}

update_fire_particle :: proc(particle: ^Fire_Particle, dt: f32) {
	DRAG :: 20;
	particle.velocity.x -= math.clamp(particle.velocity.x, -DRAG * dt, DRAG * dt);
	particle.velocity.z -= math.clamp(particle.velocity.z, -DRAG * dt, DRAG * dt);
	particle.position += particle.velocity * dt;

	life_time_multiplier := min(particle.time_alive / particle.life_time, 1);

	particle.size = max((1 - life_time_multiplier) * 0.2, 0.08);

	h := math.lerp(f32(65), f32(10), life_time_multiplier);
	s := math.lerp(f32(0.8), f32(1.0), life_time_multiplier);
	v : f32 : 1;

	r, g, b := math2.hsv_to_rgb(h, s, v);
	particle.color = [3]f32 {r, g, b};

	particle.time_alive += dt;
}

@(private="file")
reset_fire_particle :: proc(rigid_body: ^Rigid_Body_Entity, particle: ^Fire_Particle) {
	RANGE :: 1.1;

	offset_x := rand.float32_range(-RANGE, RANGE);
	offset_y : f32 = -1;
	offset_z := rand.float32_range(-RANGE, RANGE);
	particle.position = rigid_body.position + linalg.Vector3f32 {offset_x, offset_y, offset_z};

	particle.velocity = rigid_body.velocity;
	particle.velocity.y += 8;

	off_center_life_time_offset := (1 - (offset_x * offset_x + offset_z * offset_z) / (RANGE * RANGE * 2)) * 0.3;
	rand_life_time_offset := rand.float32_range(0, 0.1);
	particle.life_time = 0.15 + off_center_life_time_offset + rand_life_time_offset;

	particle.time_alive = 0;
}

draw_shock_entity_particles ::  proc(vulkan: ^Vulkan, shock_entities: []Entity_Lookup) {
	for lookup in shock_entities {
		rigid_body := get_entity(lookup).variant.(^Rigid_Body_Entity);

		for particle in &rigid_body.shock_particles {
			draw_particle(vulkan, &particle);
		}
	}
}

draw_fire_entity_particles :: proc(vulkan: ^Vulkan, fire_entities: []Entity_Lookup) {
	for lookup in fire_entities {
		rigid_body := get_entity(lookup).variant.(^Rigid_Body_Entity);

		for particle in &rigid_body.fire_particles {
			draw_particle(vulkan, &particle);
		}
	}
}

SHOCK_CLOUD_RAMP_UP_TIME :: 1;
SHOCK_CLOUD_DESIRED_PARTICLES :: 300;
SHOCK_CLOUD_RAMP_UP_PARTICLES_PER_SECOND :: SHOCK_CLOUD_DESIRED_PARTICLES / SHOCK_CLOUD_RAMP_UP_TIME

update_status_effect_cloud_particles :: proc(clouds: []Entity_Lookup, dt: f32) {
	reset_shock_particle :: proc(transform: linalg.Matrix4f32, particle: ^Shock_Particle) {
		// https://math.stackexchange.com/a/1113326/825984
		// Uniformly pick a random point the surface of a sphere
		u1 := rand.float32();
		u2 := rand.float32();

		y := 2 * u1 - 1;
		x := math.sqrt(1 - y * y) * math.cos(math.TAU * u2);
		z := math.sqrt(1 - y * y) * math.sin(math.TAU * u2);

		particle.position = math2.matrix4_transform_point(transform, linalg.Vector3f32 {x, y, z});
		particle.time_alive = 0;
	}

	for lookup in clouds {
		cloud := get_entity(lookup).variant.(^Cloud_Entity);
		hull := &cloud.collision_hulls[0];

		switch cloud.status_effect {
		case .Shock:
			if len(cloud.shock_particles) < SHOCK_CLOUD_DESIRED_PARTICLES {
				desired_particles_so_far := min(cast(int) math.ceil(cloud.ramp_up_duration * SHOCK_CLOUD_RAMP_UP_PARTICLES_PER_SECOND), SHOCK_CLOUD_DESIRED_PARTICLES);
				particles_to_add := desired_particles_so_far - len(cloud.shock_particles);
				
				cloud.ramp_up_duration += dt;

				for _ in 0..<particles_to_add {
					particle: Shock_Particle;
					particle.size = SHOCK_PARTICLE_SIZE;
					reset_shock_particle(hull.global_transform, &particle);
					append(&cloud.shock_particles, particle);
				}
			}

			for particle in &cloud.shock_particles {
				local_dist := math2.matrix4_transform_point(hull.inv_global_transform, particle.position);

				if linalg.length2(local_dist) > 1.2 * 1.2 {
					reset_shock_particle(hull.global_transform, &particle);
				}
				
				update_shock_particle(linalg.Vector3f32 {0, 0, 0}, &particle, dt);
			}
		}
	}
}

draw_status_effect_clouds :: proc(vulkan: ^Vulkan, clouds: []Entity_Lookup) {
	for lookup in clouds {
		cloud := get_entity(lookup).variant.(^Cloud_Entity);

		for particle in &cloud.shock_particles {
			draw_particle(vulkan, &particle);
		}
	}
}

cleanup_status_effect_clouds :: proc(clouds: []Entity_Lookup) {
	for lookup in clouds {
		cloud := get_entity(lookup).variant.(^Cloud_Entity);

		delete(cloud.shock_particles);
	}
}