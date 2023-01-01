package physics;

import "core:math/linalg";
import "core:container/small_array";
import "../entity";
// import "collision";

Fixed_Constraint_Set :: struct {
	entity_lookup: int,
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

// add_fixed_constraint_set :: proc(constraints: ^Constraints, entity_lookup: int, rigid_body: ^entity.RigidBodyEntity, manifold: ^collision.ContactManifold, dt: f32) {
// 	n := manifold.normal;
// }