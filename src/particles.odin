package main;

import "core:math";
import "core:math/linalg";
import "core:math/rand";
import "math2";

SHOCK_PARTICLE_MAX_OFFSET :: 1.4;

Game_Particle :: struct {
	using particle: Particle,
	velocity: linalg.Vector3f32,
	life_time: f32,
	time_alive: f32,
}

init_shock_particles :: proc(shock_entities: []Entity_Lookup) {
	for lookup in shock_entities {
		rigid_body := get_entity(lookup).variant.(^Rigid_Body_Entity);

		for _ in 0..<150 {
			particle: Game_Particle;
			particle.size = SHOCK_PARTICLE_SIZE;
			
			append(&rigid_body.shock_particles, particle);
		}
	}
}

init_fire_particles :: proc(fire_entities: []Entity_Lookup) {
	for lookup in fire_entities {
		rigid_body := get_entity(lookup).variant.(^Rigid_Body_Entity);

		for _ in 0..<200 {
			particle: Game_Particle;
			append(&rigid_body.fire_particles, particle);
		}
	}
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

update_shock_particle :: proc(body_velocity: linalg.Vector3f32, particle: ^Game_Particle, dt: f32) {
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
reset_shock_particle :: proc(rigid_body: ^Rigid_Body_Entity, particle: ^Game_Particle) {
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

			update_rigid_body_fire_particle(&particle, dt);
		}
	}
}

update_rigid_body_fire_particle :: proc(particle: ^Game_Particle, dt: f32) {
	DRAG :: 20;
	particle.velocity.x -= math.clamp(particle.velocity.x, -DRAG * dt, DRAG * dt);
	particle.velocity.z -= math.clamp(particle.velocity.z, -DRAG * dt, DRAG * dt);
	particle.position += particle.velocity * dt;

	set_fire_particle_color(particle);

	particle.time_alive += dt;
}

@(private="file")
reset_fire_particle :: proc(rigid_body: ^Rigid_Body_Entity, particle: ^Game_Particle) {
	RANGE :: 1.1;

	offset_x := rand.float32_range(-RANGE, RANGE);
	offset_y : f32 = -1;
	offset_z := rand.float32_range(-RANGE, RANGE);
	particle.position = rigid_body.position + linalg.Vector3f32 {offset_x, offset_y, offset_z};

	particle.velocity = rigid_body.velocity;
	particle.velocity.y = 8;

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

update_status_effect_cloud_particles :: proc(clouds: []Entity_Lookup, dt: f32) {
	SHOCK_RAMP_UP_TIME :: 1;
	SHOCK_DESIRED_PARTICLES :: 300;
	SHOCK_RAMP_UP_PARTICLES_PER_SECOND :: SHOCK_DESIRED_PARTICLES / SHOCK_RAMP_UP_TIME;

	FIRE_RAMP_UP_TIME :: 1;
	FIRE_DESIRED_PARTICLES :: 300;
	FIRE_RAMP_UP_PARTICLES_PER_SECOND :: FIRE_DESIRED_PARTICLES / FIRE_RAMP_UP_TIME;

	reset_shock_particle :: proc(transform: linalg.Matrix4f32, particle: ^Game_Particle) {
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
			if len(cloud.particles) < SHOCK_DESIRED_PARTICLES {
				desired_particles_so_far := min(cast(int) math.ceil(cloud.ramp_up_duration * SHOCK_RAMP_UP_PARTICLES_PER_SECOND), SHOCK_DESIRED_PARTICLES);
				particles_to_add := desired_particles_so_far - len(cloud.particles);
				
				cloud.ramp_up_duration += dt;

				for _ in 0..<particles_to_add {
					particle: Game_Particle;
					particle.size = SHOCK_PARTICLE_SIZE;
					reset_shock_particle(hull.global_transform, &particle);
					append(&cloud.particles, particle);
				}
			}

			for particle in &cloud.particles {
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

		for particle in &cloud.particles {
			draw_particle(vulkan, &particle);
		}
	}
}

set_fire_particle_color :: proc(particle: ^Game_Particle) {
	life_time_multiplier := min(particle.time_alive / particle.life_time, 1);
	particle.size = max((1 - life_time_multiplier) * 0.2, 0.08);

	h := math.lerp(f32(65), f32(10), life_time_multiplier);
	s := math.lerp(f32(0.8), f32(1.0), life_time_multiplier);
	v : f32 : 1;

	r, g, b := math2.hsv_to_rgb(h, s, v);
	particle.color = [3]f32 {r, g, b};
}

update_on_fire_oil_slicks :: proc(oil_slick_lookups: []Entity_Lookup, dt: f32) {
	RAMP_UP_TIME :: 2.5;

	reset_particle :: proc(entity: ^Entity, particle: ^Game_Particle) {
		phi := rand.float32() * math.TAU;
		rho := rand.float32() * 1.2;
		x := math.sqrt(rho) * math.cos(phi);
		z := math.sqrt(rho) * math.sin(phi);
		
		extent := math2.box_extent(entity.collision_hulls[0].local_bounds);
		local_position := linalg.Vector3f32 { x * extent.x, 0, z * extent.z };
		particle.position = math2.matrix4_transform_point(entity.transform, local_position);

		particle.velocity.y = 5;

		particle.life_time = rand.float32() * 0.3 + 0.1;
		particle.time_alive = 0;
	}

	update_particle :: proc(particle: ^Game_Particle, dt: f32) {
		particle.position.y += 5 * dt;
		set_fire_particle_color(particle);
		particle.time_alive += dt;
	}

	for oil_slick_lookup in oil_slick_lookups {
		oil_slick := get_entity(oil_slick_lookup).variant.(^Oil_Slick_Entity);

		if len(oil_slick.fire_particles) < oil_slick.desired_fire_particles {
			ramp_up_particles_per_second := f32(oil_slick.desired_fire_particles) / RAMP_UP_TIME;
			desired_particles_so_far := min(cast(int) math.ceil(oil_slick.ramp_up_duration * ramp_up_particles_per_second), oil_slick.desired_fire_particles);
			particles_to_add := desired_particles_so_far - len(oil_slick.fire_particles);

			oil_slick.ramp_up_duration += dt;

			for _ in 0..<particles_to_add {
				particle: Game_Particle;
				reset_particle(oil_slick, &particle);
				append(&oil_slick.fire_particles, particle);
			}
		}

		for particle in &oil_slick.fire_particles {
			if particle.time_alive > particle.life_time {
				reset_particle(oil_slick, &particle);
			}

			update_particle(&particle, dt);
		}
	}
}

draw_on_fire_oil_slicks :: proc(vulkan: ^Vulkan, oil_slick_lookups: []Entity_Lookup) {
	for lookup in oil_slick_lookups {
		oil_slick := get_entity(lookup).variant.(^Oil_Slick_Entity);

		for particle in &oil_slick.fire_particles {
			draw_particle(vulkan, &particle);
		}
	}
}

reset_boost_jet_particle :: proc(particle: ^Game_Particle, hull_transform: linalg.Matrix4f32) {
	x := rand.float32_range(-1, 1);
	y := rand.float32_range(-1, 1);
	z: f32 = -1;
	local_pos := linalg.Vector3f32 { x, y, z };
	particle.position = math2.matrix4_transform_point(hull_transform, local_pos);

	particle.life_time = 0.5 + rand.float32_range(-0.1, 0.1);
	particle.time_alive = rand.float32() * particle.life_time;
}

init_boost_jet_particles :: proc(boost_jet_lookups: []Entity_Lookup) {
	for lookup in boost_jet_lookups {
		boost_jet := get_entity(lookup).variant.(^Boost_Jet_Entity);
		hull_transform := boost_jet.collision_hulls[0].global_transform;
		
		for _ in 0..<150 {
			particle: Game_Particle;
			particle.size = 0.1;
			particle.color = [3]f32 { 0.9, 0.9, 0.9 };

			reset_boost_jet_particle(&particle, hull_transform);
			append(&boost_jet.particles, particle);
		}
	}
}

update_boost_jet_particles :: proc(boost_jet_lookups: []Entity_Lookup, dt: f32) {
	SPEED :: 20;
	
	for lookup in boost_jet_lookups {
		boost_jet := get_entity(lookup).variant.(^Boost_Jet_Entity);
		hull_transform := boost_jet.collision_hulls[0].global_transform;
		forward := linalg.normalize(math2.matrix4_forward(boost_jet.transform));

		for particle in &boost_jet.particles {
			if particle.time_alive > particle.life_time {
				reset_boost_jet_particle(&particle, hull_transform);
			}

			particle.position += forward * SPEED * dt;
			particle.time_alive += dt;
		}
	}
}

draw_boost_jet_particles :: proc(vulkan: ^Vulkan, boost_jet_lookups: []Entity_Lookup) {
	for lookup in boost_jet_lookups {
		boost_jet := get_entity(lookup).variant.(^Boost_Jet_Entity);

		for particle in &boost_jet.particles {
			draw_particle(vulkan, &particle);
		}
	}
}