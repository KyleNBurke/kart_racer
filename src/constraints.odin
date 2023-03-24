package main;

import "core:math";
import "core:math/linalg";
import "core:container/small_array";
import "math2";

SLOP: f32 : 0.01;

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

Car_Fixed_Constraint_Set :: struct {
	n, t1, t2: linalg.Vector3f32,
	constraints: small_array.Small_Array(4, Fixed_Constraint),
}

Fixed_Constraint_Set :: struct {
	rigid_body: ^Rigid_Body_Entity,
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

Car_Movable_Constraint_Set :: struct {
	rigid_body_b: ^Rigid_Body_Entity,
	n: linalg.Vector3f32,
	constraints: small_array.Small_Array(4, Car_Movable_Constraint),
}

Car_Movable_Constraint :: struct {
	ra,
	rb,
	rbxn: linalg.Vector3f32,
	effective_mass_inv_n,
	bias,
	total_impulse_n: f32,
}

Movable_Constraint_Set :: struct {
	rigid_body_a,
	rigid_body_b: ^Rigid_Body_Entity,
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

Cylinder_Rolling :: struct {
	rigid_body: ^Rigid_Body_Entity,
	rolling_axis,
	rolling_dir: linalg.Vector3f32,
}

Constraints :: struct {
	spring_constraint_set: Maybe(Spring_Constraint_Set),
	car_fixed_constraint_sets: [dynamic]Car_Fixed_Constraint_Set,
	car_movable_constraint_sets: [dynamic]Car_Movable_Constraint_Set,
	fixed_constraint_sets: [dynamic]Fixed_Constraint_Set,
	movable_constraint_sets: [dynamic]Movable_Constraint_Set,
	cylinders_rolling: [dynamic]Cylinder_Rolling,
}

clear_constraints :: proc(using constraints: ^Constraints) {
	spring_constraint_set = nil;
	clear(&car_fixed_constraint_sets);
	clear(&car_movable_constraint_sets);
	clear(&fixed_constraint_sets);
	clear(&movable_constraint_sets);
	clear(&cylinders_rolling);
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

		effective_mass_inv := inverse_mass + linalg.dot(rxn * car.inv_global_inertia_tensor, rxn);
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

add_car_fixed_constraint_set :: proc(constraints: ^Constraints, car: ^Car_Entity, manifold: ^Contact_Manifold, dt: f32) {
	n := manifold.normal;
	t1, t2 := math2.vector3_tangents(n);

	constraint_set := Car_Fixed_Constraint_Set {
		n = n,
		t1 = t1,
		t2 = t2,
		constraints = calculate_fixed_constraints(n, t1, t2, CAR_MASS, car.new_position, car.inv_global_inertia_tensor, &manifold.contacts, dt),
	};

	append(&constraints.car_fixed_constraint_sets, constraint_set);
}

add_car_movable_constraint_set :: proc(constraints: ^Constraints, car: ^Car_Entity, rigid_body_b: ^Rigid_Body_Entity, manifold: ^Contact_Manifold, dt: f32) {
	n := manifold.normal;
	t1, t2 := math2.vector3_tangents(n);

	constraint_set := Car_Movable_Constraint_Set {
		rigid_body_b = rigid_body_b,
		n = n,
	};

	inverse_mass_a := 1.0 / CAR_MASS;
	inverse_mass_b := 1.0 / rigid_body_b.mass;

	for contact in small_array.slice(&manifold.contacts) {
		ra := contact.position_a - car.new_position;
		raxn := linalg.cross(ra, n);

		rb := contact.position_b - rigid_body_b.new_position;
		rbxn := linalg.cross(rb, n);

		effective_mass_inv_n := inverse_mass_a + linalg.dot(raxn * car.inv_global_inertia_tensor, raxn) + inverse_mass_b + linalg.dot(rbxn * rigid_body_b.inv_global_inertia_tensor, rbxn);

		position_error := linalg.dot(contact.position_b - contact.position_a, n);
		bias := -0.2 / dt * max(position_error - SLOP, 0);

		constraint := Car_Movable_Constraint {
			ra = ra,
			rb = rb,
			rbxn = rbxn,
			effective_mass_inv_n = effective_mass_inv_n,
			bias = bias,
		};

		small_array.append(&constraint_set.constraints, constraint);
	}

	append(&constraints.car_movable_constraint_sets, constraint_set);
}

add_fixed_constraint_set :: proc(constraints: ^Constraints, rigid_body: ^Rigid_Body_Entity, hull_kind: Hull_Kind, manifold: ^Contact_Manifold, dt: f32) {
	n := manifold.normal;
	t1, t2 := math2.vector3_tangents(n);

	if hull_kind == .Cylinder {
		axis := linalg.normalize(math2.matrix4_up(rigid_body.tentative_transform));
		angle := math.acos(abs(linalg.dot(n, axis)));
		
		if angle > math.PI / 4 {
			rolling_dir := linalg.cross(axis, n);

			cylinder_rolling := Cylinder_Rolling {
				rigid_body,
				axis,
				rolling_dir,
			};

			append(&constraints.cylinders_rolling, cylinder_rolling);
		}
	}

	constraint_set := Fixed_Constraint_Set {
		rigid_body = rigid_body,
		n = n,
		t1 = t1,
		t2 = t2,
		constraints = calculate_fixed_constraints(n, t1, t2, rigid_body.mass, rigid_body.new_position, rigid_body.inv_global_inertia_tensor, &manifold.contacts, dt),
	};

	append(&constraints.fixed_constraint_sets, constraint_set);
}

@(private="file")
calculate_fixed_constraints :: proc(n, t1, t2: linalg.Vector3f32, mass: f32, new_position: linalg.Vector3f32, inv_global_inertia_tensor: linalg.Matrix3f32, contacts: ^small_array.Small_Array(4, Contact), dt: f32) -> small_array.Small_Array(4, Fixed_Constraint) {
	constraints: small_array.Small_Array(4, Fixed_Constraint);
	inverse_mass := 1.0 / mass;

	for contact in small_array.slice(contacts) {
		r := contact.position_a - new_position;
		rxn  := linalg.cross(r, n);
		rxt1 := linalg.cross(r, t1);
		rxt2 := linalg.cross(r, t2);
		
		effective_mass_inv_n  := inverse_mass + linalg.dot(rxn  * inv_global_inertia_tensor, rxn);
		effective_mass_inv_t1 := inverse_mass + linalg.dot(rxt1 * inv_global_inertia_tensor, rxt1);
		effective_mass_inv_t2 := inverse_mass + linalg.dot(rxt2 * inv_global_inertia_tensor, rxt2);

		position_error := linalg.dot((contact.position_b - contact.position_a), n);
		bias := -0.2 / dt * max(position_error - SLOP, 0);

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

		small_array.append(&constraints, constraint);
	}

	return constraints;
}

add_movable_constraint_set :: proc(constraints: ^Constraints, rigid_body_a, rigid_body_b: ^Rigid_Body_Entity, manifold: ^Contact_Manifold, dt: f32) {
	n := manifold.normal;
	t1, t2 := math2.vector3_tangents(n);

	constraint_set := Movable_Constraint_Set {
		rigid_body_a = rigid_body_a,
		rigid_body_b = rigid_body_b,
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

		effective_mass_inv_n  := inverse_mass_a + linalg.dot(raxn  * rigid_body_a.inv_global_inertia_tensor, raxn)  + inverse_mass_b + linalg.dot(rbxn  * rigid_body_b.inv_global_inertia_tensor, rbxn);
		effective_mass_inv_t1 := inverse_mass_a + linalg.dot(raxt1 * rigid_body_a.inv_global_inertia_tensor, raxt1) + inverse_mass_b + linalg.dot(rbxt1 * rigid_body_b.inv_global_inertia_tensor, rbxt1);
		effective_mass_inv_t2 := inverse_mass_a + linalg.dot(raxt2 * rigid_body_a.inv_global_inertia_tensor, raxt2) + inverse_mass_b + linalg.dot(rbxt2 * rigid_body_b.inv_global_inertia_tensor, rbxt2);
		
		position_error := linalg.dot(contact.position_b - contact.position_a, n);
		bias := -0.2 / dt * max(position_error - SLOP, 0);

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

solve_constraints :: proc(using constraints: ^Constraints, car: ^Car_Entity, dt: f32) {
	for _ in 0..<10 {
		if constraint_set, ok := spring_constraint_set.?; ok {
			for _, constraint_index in small_array.slice(&constraint_set.constraints) {
				constraint := small_array.get_ptr(&constraint_set.constraints, constraint_index);

				velocity := car.velocity + linalg.cross(car.angular_velocity, constraint.r);
				velocity_error := linalg.dot(velocity, constraint_set.n);
				lambda := -(velocity_error + constraint.bias + constraint.softness * constraint.total_impulse) / (constraint.effective_mass_inv + constraint.softness);

				prev_total_impulse := constraint.total_impulse;
				constraint.total_impulse = max(constraint.total_impulse + lambda, 0.0);
				total_impulse_delta := constraint.total_impulse - prev_total_impulse;

				car.velocity += constraint_set.n * total_impulse_delta / CAR_MASS;
				car.angular_velocity += car.inv_global_inertia_tensor * constraint.rxn * total_impulse_delta;
			}
		}

		for constraint_set in &car_fixed_constraint_sets {
			solve_fixed_constraints(&constraint_set.constraints, constraint_set.n, constraint_set.t1, constraint_set.t2, CAR_MASS, car.inv_global_inertia_tensor, &car.velocity, &car.angular_velocity);
		}

		for constraint_set in &car_movable_constraint_sets {
			rigid_body_b := constraint_set.rigid_body_b;

			for _, constraint_index in small_array.slice(&constraint_set.constraints) {
				constraint := small_array.get_ptr(&constraint_set.constraints, constraint_index);

				contact_velocity_a := car.velocity + linalg.cross(car.angular_velocity, constraint.ra);
				contact_velocity_b := rigid_body_b.velocity + linalg.cross(rigid_body_b.angular_velocity, constraint.rb);

				velocity_error_n := linalg.dot(contact_velocity_a - contact_velocity_b, constraint_set.n);
				lambda_n := -(velocity_error_n + constraint.bias) / constraint.effective_mass_inv_n;

				prev_total_impulse_n := constraint.total_impulse_n;
				constraint.total_impulse_n = max(constraint.total_impulse_n + lambda_n, 0.0);
				total_impulse_delta_n := constraint.total_impulse_n - prev_total_impulse_n;

				car.velocity += constraint_set.n * total_impulse_delta_n / CAR_MASS;

				rigid_body_b.velocity -= constraint_set.n * total_impulse_delta_n / rigid_body_b.mass;
				rigid_body_b.angular_velocity -= rigid_body_b.inv_global_inertia_tensor * constraint.rbxn * total_impulse_delta_n;
			}
		}

		for constraint_set in &fixed_constraint_sets {
			rigid_body := constraint_set.rigid_body;

			for _, constraint_index in small_array.slice(&constraint_set.constraints) {
				constraint := small_array.get_ptr(&constraint_set.constraints, constraint_index);
				contact_velocity := rigid_body.velocity + linalg.cross(rigid_body.angular_velocity, constraint.r);

				// Normal
				velocity_error_n := linalg.dot(contact_velocity, constraint_set.n);
				lambda_n := -(velocity_error_n + constraint.bias) / constraint.effective_mass_inv_n;
				
				prev_total_impulse_n := constraint.total_impulse_n;
				constraint.total_impulse_n = max(constraint.total_impulse_n + lambda_n, 0.0);
				total_impulse_delta_n := constraint.total_impulse_n - prev_total_impulse_n;

				rigid_body.velocity += constraint_set.n * total_impulse_delta_n / rigid_body.mass;
				rigid_body.angular_velocity += rigid_body.inv_global_inertia_tensor * constraint.rxn * total_impulse_delta_n;

				max_friction_impulse := constraint.total_impulse_n * 0.8;

				// Tangent 1
				velocity_error_t1 := linalg.dot(contact_velocity, constraint_set.t1);
				lambda_t1 := -velocity_error_t1 / constraint.effective_mass_inv_t1;

				prev_total_impulse_t1 := constraint.total_impulse_t1;
				constraint.total_impulse_t1 = clamp(constraint.total_impulse_t1 + lambda_t1, -max_friction_impulse, max_friction_impulse);
				total_impulse_delta_t1 := constraint.total_impulse_t1 - prev_total_impulse_t1;

				rigid_body.velocity += constraint_set.t1 * total_impulse_delta_t1 / rigid_body.mass;
				rigid_body.angular_velocity += rigid_body.inv_global_inertia_tensor * constraint.rxt1 * total_impulse_delta_t1;

				// Tangent 2
				velocity_error_t2 := linalg.dot(contact_velocity, constraint_set.t2);
				lambda_t2 := -velocity_error_t2 / constraint.effective_mass_inv_t2;
				
				prev_total_impulse_t2 := constraint.total_impulse_t2;
				constraint.total_impulse_t2 = clamp(constraint.total_impulse_t2 + lambda_t2, -max_friction_impulse, max_friction_impulse);
				total_impulse_delta_t2 := constraint.total_impulse_t2 - prev_total_impulse_t2;

				rigid_body.velocity += constraint_set.t2 * total_impulse_delta_t2 / rigid_body.mass;
				rigid_body.angular_velocity += rigid_body.inv_global_inertia_tensor * constraint.rxt2 * total_impulse_delta_t2;
			}
		}

		for constraint_set in &movable_constraint_sets {
			rigid_body_a := constraint_set.rigid_body_a;
			rigid_body_b := constraint_set.rigid_body_b;

			for _, constraint_index in small_array.slice(&constraint_set.constraints) {
				constraint := small_array.get_ptr(&constraint_set.constraints, constraint_index);

				contact_velocity_a := rigid_body_a.velocity + linalg.cross(rigid_body_a.angular_velocity, constraint.ra);
				contact_velocity_b := rigid_body_b.velocity + linalg.cross(rigid_body_b.angular_velocity, constraint.rb);

				// Normal
				velocity_error_n := linalg.dot(contact_velocity_a - contact_velocity_b, constraint_set.n);
				lambda_n := -(velocity_error_n + constraint.bias) / constraint.effective_mass_inv_n;
	
				prev_total_impulse_n := constraint.total_impulse_n;
				constraint.total_impulse_n = max(constraint.total_impulse_n + lambda_n, 0.0);
				total_impulse_delta_n := constraint.total_impulse_n - prev_total_impulse_n;
	
				rigid_body_a.velocity += constraint_set.n * total_impulse_delta_n / rigid_body_a.mass;
				rigid_body_a.angular_velocity += rigid_body_a.inv_global_inertia_tensor * constraint.raxn * total_impulse_delta_n;
	
				rigid_body_b.velocity -= constraint_set.n * total_impulse_delta_n / rigid_body_b.mass;
				rigid_body_b.angular_velocity -= rigid_body_b.inv_global_inertia_tensor * constraint.rbxn * total_impulse_delta_n;
	
				max_friction_impulse := constraint.total_impulse_n * 0.8;
	
				// Tangent 1
				velocity_error_t1 := linalg.dot(contact_velocity_a - contact_velocity_b, constraint_set.t1);
				lambda_t1 := -velocity_error_t1 / constraint.effective_mass_inv_t1;
	
				prev_total_impulse_t1 := constraint.total_impulse_t1;
				constraint.total_impulse_t1 = clamp(constraint.total_impulse_t1 + lambda_t1, -max_friction_impulse, max_friction_impulse);
				total_impulse_delta_t1 := constraint.total_impulse_t1 - prev_total_impulse_t1;
	
				rigid_body_a.velocity += constraint_set.t1 * total_impulse_delta_t1 / rigid_body_a.mass;
				rigid_body_a.angular_velocity += rigid_body_a.inv_global_inertia_tensor * constraint.raxt1 * total_impulse_delta_t1;
	
				rigid_body_b.velocity -= constraint_set.t1 * total_impulse_delta_t1 / rigid_body_b.mass;
				rigid_body_b.angular_velocity -= rigid_body_b.inv_global_inertia_tensor * constraint.rbxt1 * total_impulse_delta_t1;
	
				// Tangent 2
				velocity_error_t2 := linalg.dot(contact_velocity_a - contact_velocity_b, constraint_set.t2);
				lambda_t2 := -velocity_error_t2 / constraint.effective_mass_inv_t2;
	
				prev_total_impulse_t2 := constraint.total_impulse_t2;
				constraint.total_impulse_t2 = clamp(constraint.total_impulse_t2 + lambda_t2, -max_friction_impulse, max_friction_impulse);
				total_impulse_delta_t2 := constraint.total_impulse_t2 - prev_total_impulse_t2;
	
				rigid_body_a.velocity += constraint_set.t2 * total_impulse_delta_t2 / rigid_body_a.mass;
				rigid_body_a.angular_velocity += rigid_body_a.inv_global_inertia_tensor * constraint.raxt2 * total_impulse_delta_t2;
	
				rigid_body_b.velocity -= constraint_set.t2 * total_impulse_delta_t2 / rigid_body_b.mass;
				rigid_body_b.angular_velocity -= rigid_body_b.inv_global_inertia_tensor * constraint.rbxt2 * total_impulse_delta_t2;
			}
		}
	}

	// Angular velocity damping because the friction constraints don't work with rolling resistance
	for cylinder in &cylinders_rolling {
		rigid_body := cylinder.rigid_body;

		ang_vel := linalg.dot(cylinder.rolling_axis, rigid_body.angular_velocity);
		ang_vel_error := clamp(ang_vel, -2 * dt, 2 * dt);

		rigid_body.angular_velocity += cylinder.rolling_axis * -ang_vel_error;
		rigid_body.velocity += cylinder.rolling_dir * -ang_vel_error * 1; // The 1 here is the radius of the cylinder so scaled cylinder's are not implemented
	}
}

@(private="file")
solve_fixed_constraints :: proc(constraints: ^small_array.Small_Array(4, Fixed_Constraint), n, t1, t2: linalg.Vector3f32, mass: f32, inv_global_inertia_tensor: linalg.Matrix3f32, velocity, angular_velocity: ^linalg.Vector3f32) {
	for _, constraint_index in small_array.slice(constraints) {
		constraint := small_array.get_ptr(constraints, constraint_index);
		contact_velocity := velocity^ + linalg.cross(angular_velocity^, constraint.r);

		// Normal
		velocity_error_n := linalg.dot(contact_velocity, n);
		lambda_n := -(velocity_error_n + constraint.bias) / constraint.effective_mass_inv_n;
		
		prev_total_impulse_n := constraint.total_impulse_n;
		constraint.total_impulse_n = max(constraint.total_impulse_n + lambda_n, 0.0);
		total_impulse_delta_n := constraint.total_impulse_n - prev_total_impulse_n;

		velocity^ += n * total_impulse_delta_n / mass;
		angular_velocity^ += inv_global_inertia_tensor * constraint.rxn * total_impulse_delta_n;

		max_friction_impulse := constraint.total_impulse_n * 0.8;

		// Tangent 1
		velocity_error_t1 := linalg.dot(contact_velocity, t1);
		lambda_t1 := -velocity_error_t1 / constraint.effective_mass_inv_t1;

		prev_total_impulse_t1 := constraint.total_impulse_t1;
		constraint.total_impulse_t1 = clamp(constraint.total_impulse_t1 + lambda_t1, -max_friction_impulse, max_friction_impulse);
		total_impulse_delta_t1 := constraint.total_impulse_t1 - prev_total_impulse_t1;

		velocity^ += t1 * total_impulse_delta_t1 / mass;
		angular_velocity^ += inv_global_inertia_tensor * constraint.rxt1 * total_impulse_delta_t1;

		// Tangent 2
		velocity_error_t2 := linalg.dot(contact_velocity, t2);
		lambda_t2 := -velocity_error_t2 / constraint.effective_mass_inv_t2;
		
		prev_total_impulse_t2 := constraint.total_impulse_t2;
		constraint.total_impulse_t2 = clamp(constraint.total_impulse_t2 + lambda_t2, -max_friction_impulse, max_friction_impulse);
		total_impulse_delta_t2 := constraint.total_impulse_t2 - prev_total_impulse_t2;

		velocity^ += t2 * total_impulse_delta_t2 / mass;
		angular_velocity^ += inv_global_inertia_tensor * constraint.rxt2 * total_impulse_delta_t2;
	}
}

cleanup_constraints :: proc(using constraints: ^Constraints) {
	delete(car_fixed_constraint_sets);
	delete(car_movable_constraint_sets);
	delete(fixed_constraint_sets);
	delete(movable_constraint_sets);
	delete(cylinders_rolling);
}