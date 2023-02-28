package main;

import "core:math";
import "core:math/linalg";
import "core:math/rand";
import "math2";

initialize_fire_particles :: proc(entities_geos: ^Entities_Geos, fire_cubes: []Entity_Lookup) {
	for lookup in fire_cubes {
		rigid_body := get_entity(entities_geos, lookup).variant.(^Rigid_Body_Entity);

		for _ in 0..<200 {
			particle: Fire_Particle;
			append(&rigid_body.fire_particles, particle);
		}
	}
}

cleanup_fire_particles :: proc(entities_geos: ^Entities_Geos, fire_cubes: []Entity_Lookup) {
	for lookup in fire_cubes {
		rigid_body := get_entity(entities_geos, lookup).variant.(^Rigid_Body_Entity);
		delete(rigid_body.fire_particles);
	}
}

update_fire_cube_particles :: proc(entities_geos: ^Entities_Geos, fire_cubes: []Entity_Lookup, dt: f32) {
	for lookup in fire_cubes {
		rigid_body := get_entity(entities_geos, lookup).variant.(^Rigid_Body_Entity);

		for particle in &rigid_body.fire_particles {
			update_fire_particle(&particle, dt);

			if particle.time_alive >= particle.life_time {
				reset_fire_particle(rigid_body, &particle);
			}
			
			particle.time_alive += dt;
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
	v: f32 : 1;

	r, g, b := math2.hsv_to_rgb(h, s, v);
	particle.color = [3]f32 {r, g, b};
}

@(private="file")
reset_fire_particle :: proc(rigid_body: ^Rigid_Body_Entity, particle: ^Fire_Particle) {
	RANGE :: 1.2;
	
	left := math2.matrix4_left(rigid_body.transform);
	forward := math2.matrix4_forward(rigid_body.transform);

	offset_left := left * rand.float32_range(-RANGE, RANGE);
	offset_forward := forward * rand.float32_range(-RANGE, RANGE);
	offset_up := linalg.Vector3f32 {0, -1, 0};
	particle.position = rigid_body.position + offset_left + offset_forward + offset_up;

	particle.velocity = rigid_body.velocity;
	particle.velocity.y += 8;

	off_center_life_time_offset := (1 - linalg.length(offset_left + offset_forward) / 1.2) * 0.2;
	rand_life_time_offset := rand.float32_range(0, 0.1);
	particle.life_time = 0.25 + off_center_life_time_offset + rand_life_time_offset;

	particle.time_alive = 0;
}

draw_fire_cube_particles :: proc(vulkan: ^Vulkan, entities_geos: ^Entities_Geos, fire_cubes: []Entity_Lookup) {
	for lookup in fire_cubes {
		rigid_body := get_entity(entities_geos, lookup).variant.(^Rigid_Body_Entity);

		for particle in &rigid_body.fire_particles {
			draw_particle(vulkan, &particle);
		}
	}
}