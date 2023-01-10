package main;

import "core:math/linalg";
import "core:container/small_array";
import "math2";

import "core:fmt";

SLOP: f32 : 0.001;

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

Constraints :: struct {
	fixed_constraint_sets: [dynamic]Fixed_Constraint_Set,
}

clear_constraints :: proc(using constraints: ^Constraints) {
	clear(&fixed_constraint_sets);
}

add_fixed_constraint_set :: proc(constraints: ^Constraints, entity_lookup: Entity_Lookup, rigid_body: ^Rigid_Body_Entity, manifold: ^ContactManifold, dt: f32) {
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

solve_constraints :: proc(using constraints: ^Constraints, entities: ^Entities) {
	for _ in 0..<10 {
		for constraint_set in &fixed_constraint_sets {
			rigid_body := get_entity(entities, constraint_set.entity_lookup).variant.(^Rigid_Body_Entity);

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
	}
}

cleanup_constraints :: proc(using constraints: ^Constraints) {
	delete(fixed_constraint_sets);
}