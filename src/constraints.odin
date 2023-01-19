package main;

import "core:math";
import "core:math/linalg";
import "core:container/small_array";
import "math2";

SLOP: f32 : 0.001;

SPRING_ZETA: f32 : 1.0;
SPRING_FREQUENCY: f32 : 5.0;
SPRING_OMEGA: f32 : 2.0 * math.PI * SPRING_FREQUENCY;

SPRING_EQUILIBRIUM_LENGTH: f32 : 0.4;

Spring_Constraint_Set :: struct {
	n: linalg.Vector3f32,
	constraints: small_array.Small_Array(4, Spring_Constraint),
}

Spring_Constraint :: struct {
	r,
	rxn: linalg.Vector3f32,
	effective_mass_inv,
	softness,
	bias,
	total_impulse: f32,
}

Fixed_Constraint_Set :: struct {
	entity_lookup: Entity_Lookup,
	n, t1, t2: linalg.Vector3f32,
	constraints: small_array.Small_Array(4, Fixed_Constraint),
}

Fixed_Constraint :: struct {
	r,
	rxn,
	rxt1,
	rxt2: linalg.Vector3f32,
	effective_mass_inv_n,
	effective_mass_inv_t1,
	effective_mass_inv_t2,
	bias,
	total_impulse_n,
	total_impulse_t1,
	total_impulse_t2: f32,
}

Movable_Constraint_Set :: struct {
	entity_a_lookup,
	entity_b_lookup: Entity_Lookup,
	n, t1, t2: linalg.Vector3f32,
	constraints: small_array.Small_Array(4, Movable_Constraint),
}

Movable_Constraint :: struct {
	ra,
	raxn,
	raxt1,
	raxt2,
	rb,
	rbxn,
	rbxt1,
	rbxt2: linalg.Vector3f32,
	effective_mass_inv_n,
	effective_mass_inv_t1,
	effective_mass_inv_t2,
	bias,
	total_impulse_n,
	total_impulse_t1,
	total_impulse_t2: f32,
}

Constraints :: struct {
	spring_constraint_set: Maybe(Spring_Constraint_Set),
	fixed_constraint_sets: [dynamic]Fixed_Constraint_Set,
	movable_constraint_sets: [dynamic]Movable_Constraint_Set,
}

clear_constraints :: proc(using constraints: ^Constraints) {
	spring_constraint_set = nil;
	clear(&fixed_constraint_sets);
	clear(&movable_constraint_sets);
}

set_spring_constraint_set :: proc(constraints: ^Constraints, car: ^Car_Entity, manifold: ^Spring_Contact_Manifold, dt: f32) {
	n := manifold.normal;
	
	spring_constraint_set := Spring_Constraint_Set {
		n = n,
	};

	inverse_mass := 1.0 / CAR_MASS;

	for contact in small_array.slice(&manifold.contacts) {
		r := contact.body_point - car.new_position;
		rxn := linalg.cross(r, n);

		effective_mass_inv := inverse_mass + linalg.dot((rxn * car.inv_global_inertia_tensor), rxn);
		effective_mass := 1.0 / effective_mass_inv;

		spring_k := effective_mass * SPRING_OMEGA * SPRING_OMEGA;
		spring_c := 2.0 * effective_mass * SPRING_ZETA * SPRING_OMEGA;

		gamma := 1.0 / (spring_c + dt * spring_k);
		softness := gamma / dt;

		beta := (dt * spring_k) / (spring_c + dt * spring_k);
		position_error := SPRING_EQUILIBRIUM_LENGTH - contact.length;
		bias := beta / dt * -position_error;

		small_array.append(&spring_constraint_set.constraints, Spring_Constraint {
			r = r,
			rxn = rxn,
			effective_mass_inv = effective_mass_inv,
			softness = softness,
			bias = bias,
		});
	}

	constraints.spring_constraint_set = spring_constraint_set;
}

add_fixed_constraint_set :: proc(constraints: ^Constraints, entity_lookup: Entity_Lookup, rigid_body: ^Rigid_Body_Entity, manifold: ^Contact_Manifold, dt: f32) {
	n := manifold.normal;
	t1, t2 := math2.vector3_tangents(n);

	constraint_set := Fixed_Constraint_Set {
		entity_lookup = entity_lookup,
		n = n,
		t1 = t1,
		t2 = t2,
	};

	inverse_mass := 1.0 / rigid_body.mass;

	for contact in small_array.slice(&manifold.contacts) {
		r := contact.position_a - rigid_body.new_position;
		rxn  := linalg.cross(r, n);
		rxt1 := linalg.cross(r, t1);
		rxt2 := linalg.cross(r, t2);
		
		effective_mass_inv_n  := inverse_mass + linalg.dot((rxn  * rigid_body.inv_global_inertia_tensor), rxn);
		effective_mass_inv_t1 := inverse_mass + linalg.dot((rxt1 * rigid_body.inv_global_inertia_tensor), rxt1);
		effective_mass_inv_t2 := inverse_mass + linalg.dot((rxt2 * rigid_body.inv_global_inertia_tensor), rxt2);

		position_error := linalg.dot((contact.position_b - contact.position_a), n);
		bias := -0.2 / dt * max((position_error - SLOP), 0);

		constraint := Fixed_Constraint {
			r = r,
			rxn = rxn,
			rxt1 = rxt1,
			rxt2 = rxt2,
			effective_mass_inv_n = effective_mass_inv_n,
			effective_mass_inv_t1 = effective_mass_inv_t1,
			effective_mass_inv_t2 = effective_mass_inv_t2,
			bias = bias,
		};

		small_array.append(&constraint_set.constraints, constraint);
	}

	append(&constraints.fixed_constraint_sets, constraint_set);
}

add_movable_constraint_set :: proc(constraints: ^Constraints, entity_a_lookup, entity_b_lookup: Entity_Lookup, rigid_body_a, rigid_body_b: ^Rigid_Body_Entity, manifold: ^Contact_Manifold, dt: f32) {
	n := manifold.normal;
	t1, t2 := math2.vector3_tangents(n);

	constraint_set := Movable_Constraint_Set {
		entity_a_lookup = entity_a_lookup,
		entity_b_lookup = entity_b_lookup,
		n = n,
		t1 = t1,
		t2 = t2,
	};

	inverse_mass_a := 1.0 / rigid_body_a.mass;
	inverse_mass_b := 1.0 / rigid_body_b.mass;

	for contact in small_array.slice(&manifold.contacts) {
		ra := contact.position_a - rigid_body_a.new_position;
		raxn := linalg.cross(ra, n);
		raxt1 := linalg.cross(ra, t1);
		raxt2 := linalg.cross(ra, t2);

		rb := contact.position_b - rigid_body_b.new_position;
		rbxn := linalg.cross(rb, n);
		rbxt1 := linalg.cross(rb, t1);
		rbxt2 := linalg.cross(rb, t2);

		effective_mass_inv_n  := inverse_mass_a + linalg.dot((raxn  * rigid_body_a.inv_global_inertia_tensor), raxn)  + inverse_mass_b + linalg.dot((rbxn  * rigid_body_b.inv_global_inertia_tensor), rbxn);
		effective_mass_inv_t1 := inverse_mass_a + linalg.dot((raxt1 * rigid_body_a.inv_global_inertia_tensor), raxt1) + inverse_mass_b + linalg.dot((rbxt1 * rigid_body_b.inv_global_inertia_tensor), rbxt1);
		effective_mass_inv_t2 := inverse_mass_a + linalg.dot((raxt2 * rigid_body_a.inv_global_inertia_tensor), raxt2) + inverse_mass_b + linalg.dot((rbxt2 * rigid_body_b.inv_global_inertia_tensor), rbxt2);
		
		position_error := linalg.dot((contact.position_b - contact.position_a), n);
		bias := -0.2 / dt * max((position_error - SLOP), 0);

		constraint := Movable_Constraint {
			ra = ra,
			raxn = raxn,
			raxt1 = raxt1,
			raxt2 = raxt2,
			rb = rb,
			rbxn = rbxn,
			rbxt1 = rbxt1,
			rbxt2 = rbxt2,
			effective_mass_inv_n = effective_mass_inv_n,
			effective_mass_inv_t1 = effective_mass_inv_t1,
			effective_mass_inv_t2 = effective_mass_inv_t2,
			bias = bias,
		};

		small_array.append(&constraint_set.constraints, constraint);
	}

	append(&constraints.movable_constraint_sets, constraint_set);
}

solve_constraints :: proc(using constraints: ^Constraints, entities_geos: ^Entities_Geos, car: ^Car_Entity) {
	for _ in 0..<10 {
		if constraint_set, ok := spring_constraint_set.?; ok {
			for _, constraint_index in small_array.slice(&constraint_set.constraints) {
				constraint := small_array.get_ptr(&constraint_set.constraints, constraint_index);

				velocity := car.velocity + linalg.cross(car.angular_velocity, constraint.r);
				velocity_error := linalg.dot(velocity, constraint_set.n);
				lambda := -(velocity_error + constraint.bias + constraint.softness * constraint.total_impulse) / (constraint.effective_mass_inv + constraint.softness);

				prev_total_impulse := constraint.total_impulse;
				constraint.total_impulse = max((prev_total_impulse + lambda), 0.0); // It's weird that using using the prev_total_impulse here but not in the other two constraints
				total_impulse_delta := constraint.total_impulse - prev_total_impulse;

				car.velocity += constraint_set.n * total_impulse_delta / CAR_MASS;
				car.angular_velocity += car.inv_global_inertia_tensor * constraint.rxn * total_impulse_delta;
			}
		}

		for constraint_set in &fixed_constraint_sets {
			rigid_body := get_entity(entities_geos, constraint_set.entity_lookup).variant.(^Rigid_Body_Entity);

			for _, constraint_index in small_array.slice(&constraint_set.constraints) {
				constraint := small_array.get_ptr(&constraint_set.constraints, constraint_index);
				contact_velocity := rigid_body.velocity + linalg.cross(rigid_body.angular_velocity, constraint.r);

				// Normal
				velocity_error_n := linalg.dot(contact_velocity, constraint_set.n);
				lambda_n := -(velocity_error_n + constraint.bias) / constraint.effective_mass_inv_n;
				
				prev_total_impulse_n := constraint.total_impulse_n;
				constraint.total_impulse_n = max((constraint.total_impulse_n + lambda_n), 0.0);
				total_impulse_delta_n := constraint.total_impulse_n - prev_total_impulse_n;

				rigid_body.velocity += constraint_set.n * total_impulse_delta_n / rigid_body.mass;
				rigid_body.angular_velocity += rigid_body.inv_global_inertia_tensor * constraint.rxn * total_impulse_delta_n;

				max_friction_impulse := constraint.total_impulse_n * 0.8;

				// Tangent 1
				velocity_error_t1 := linalg.dot(contact_velocity, constraint_set.t1);
				lambda_t1 := -velocity_error_t1 / constraint.effective_mass_inv_t1;

				prev_total_impulse_t1 := constraint.total_impulse_t1;
				constraint.total_impulse_t1 = clamp((constraint.total_impulse_t1 + lambda_t1), -max_friction_impulse, max_friction_impulse);
				total_impulse_delta_t1 := constraint.total_impulse_t1 - prev_total_impulse_t1;

				rigid_body.velocity += constraint_set.t1 * total_impulse_delta_t1 / rigid_body.mass;
				rigid_body.angular_velocity += rigid_body.inv_global_inertia_tensor * constraint.rxt1 * total_impulse_delta_t1;

				// Tangent 2
				velocity_error_t2 := linalg.dot(contact_velocity, constraint_set.t2);
				lambda_t2 := -velocity_error_t2 / constraint.effective_mass_inv_t2;
				
				prev_total_impulse_t2 := constraint.total_impulse_t2;
				constraint.total_impulse_t2 = clamp((constraint.total_impulse_t2 + lambda_t2), -max_friction_impulse, max_friction_impulse);
				total_impulse_delta_t2 := constraint.total_impulse_t2 - prev_total_impulse_t2;

				rigid_body.velocity += constraint_set.t2 * total_impulse_delta_t2 / rigid_body.mass;
				rigid_body.angular_velocity += rigid_body.inv_global_inertia_tensor * constraint.rxt2 * total_impulse_delta_t2;
			}
		}

		for constraint_set in &movable_constraint_sets {
			rigid_body_a := get_entity(entities_geos, constraint_set.entity_a_lookup).variant.(^Rigid_Body_Entity);
			rigid_body_b := get_entity(entities_geos, constraint_set.entity_b_lookup).variant.(^Rigid_Body_Entity);

			for _, constraint_index in small_array.slice(&constraint_set.constraints) {
				constraint := small_array.get_ptr(&constraint_set.constraints, constraint_index);

				contact_velocity_a := rigid_body_a.velocity + linalg.cross(rigid_body_a.angular_velocity, constraint.ra);
				contact_velocity_b := rigid_body_b.velocity + linalg.cross(rigid_body_b.angular_velocity, constraint.rb);

				// Normal
				velocity_error_n := linalg.dot((contact_velocity_a - contact_velocity_b), constraint_set.n);
				lambda_n := -(velocity_error_n + constraint.bias) / constraint.effective_mass_inv_n;
	
				prev_total_impulse_n := constraint.total_impulse_n;
				constraint.total_impulse_n = max((constraint.total_impulse_n + lambda_n), 0.0);
				total_impulse_delta_n := constraint.total_impulse_n - prev_total_impulse_n;
	
				rigid_body_a.velocity += constraint_set.n * total_impulse_delta_n / rigid_body_a.mass;
				rigid_body_a.angular_velocity += rigid_body_a.inv_global_inertia_tensor * constraint.raxn * total_impulse_delta_n;
	
				rigid_body_b.velocity -= constraint_set.n * total_impulse_delta_n / rigid_body_b.mass;
				rigid_body_b.angular_velocity -= rigid_body_b.inv_global_inertia_tensor * constraint.rbxn * total_impulse_delta_n;
	
				max_friction_impulse := constraint.total_impulse_n * 0.8;
	
				// Tangent 1
				velocity_error_t1 := linalg.dot((contact_velocity_a - contact_velocity_b), constraint_set.t1);
				lambda_t1 := -velocity_error_t1 / constraint.effective_mass_inv_t1;
	
				prev_total_impulse_t1 := constraint.total_impulse_t1;
				constraint.total_impulse_t1 = clamp((constraint.total_impulse_t1 + lambda_t1), -max_friction_impulse, max_friction_impulse);
				total_impulse_delta_t1 := constraint.total_impulse_t1 - prev_total_impulse_t1;
	
				rigid_body_a.velocity += constraint_set.t1 * total_impulse_delta_t1 / rigid_body_a.mass;
				rigid_body_a.angular_velocity += rigid_body_a.inv_global_inertia_tensor * constraint.raxt1 * total_impulse_delta_t1;
	
				rigid_body_b.velocity -= constraint_set.t1 * total_impulse_delta_t1 / rigid_body_b.mass;
				rigid_body_b.angular_velocity -= rigid_body_b.inv_global_inertia_tensor * constraint.rbxt1 * total_impulse_delta_t1;
	
				// Tangent 2
				velocity_error_t2 := linalg.dot((contact_velocity_a - contact_velocity_b), constraint_set.t2);
				lambda_t2 := -velocity_error_t2 / constraint.effective_mass_inv_t2;
	
				prev_total_impulse_t2 := constraint.total_impulse_t2;
				constraint.total_impulse_t2 = clamp((constraint.total_impulse_t2 + lambda_t2), -max_friction_impulse, max_friction_impulse);
				total_impulse_delta_t2 := constraint.total_impulse_t2 - prev_total_impulse_t2;
	
				rigid_body_a.velocity += constraint_set.t2 * total_impulse_delta_t2 / rigid_body_a.mass;
				rigid_body_a.angular_velocity += rigid_body_a.inv_global_inertia_tensor * constraint.raxt2 * total_impulse_delta_t2;
	
				rigid_body_b.velocity -= constraint_set.t2 * total_impulse_delta_t2 / rigid_body_b.mass;
				rigid_body_b.angular_velocity -= rigid_body_b.inv_global_inertia_tensor * constraint.rbxt2 * total_impulse_delta_t2;
			}
		}
	}
}

cleanup_constraints :: proc(using constraints: ^Constraints) {
	delete(fixed_constraint_sets);
	delete(movable_constraint_sets);
}