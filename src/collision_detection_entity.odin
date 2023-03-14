package main;

import "core:fmt";
import "core:math/linalg";
import "core:container/small_array";
import "math2";

evaluate_entity_collision :: proc(hull_a, hull_b: ^Collision_Hull) -> Maybe(Contact_Manifold) {
	if !math2.box_intersects(hull_a.global_bounds, hull_b.global_bounds) {
		return nil;
	}

	if simplex, ok := colliding(hull_a, hull_b).?; ok {
		if normal, ok := find_collision_normal(&simplex, hull_a, hull_b).?; ok {
			// Since the collision normal points from b to a, we must negate the normal for a
			plane_normal_a, polygon_a := find_plane_normal_and_polygon(hull_a, -normal);
			plane_normal_b, polygon_b := find_plane_normal_and_polygon(hull_b, normal);
			a_is_ref := abs(linalg.dot(normal, plane_normal_a)) > abs(linalg.dot(normal, plane_normal_b));
			contacts: small_array.Small_Array(4, Contact);

			if len(polygon_a) == 2 && len(polygon_b) == 2 {
				if a_is_ref {
					contacts = line_clip_lines(plane_normal_a, polygon_a[0], polygon_a[1], polygon_b[0], polygon_b[1], true);
				} else {
					contacts = line_clip_lines(plane_normal_b, polygon_b[0], polygon_b[1], polygon_a[0], polygon_a[1], false);
				}
			} else if len(polygon_a) == 2 {
				if a_is_ref {
					contacts = line_clip_line_is_ref(plane_normal_a, polygon_a[0], polygon_a[1], polygon_b);
				} else {
					contacts = line_clip_poly_is_ref(plane_normal_b, polygon_b, polygon_a[0], polygon_a[1]);
				}
			} else if len(polygon_b) == 2 {
				if a_is_ref {
					contacts = line_clip_poly_is_ref(plane_normal_a, polygon_a, polygon_b[0], polygon_b[1]);
				} else {
					contacts = line_clip_line_is_ref(plane_normal_b, polygon_b[0], polygon_b[1], polygon_a);
				}
			} else {
				full_contacts: [dynamic]Contact;

				if a_is_ref {
					full_contacts = clip(plane_normal_a, polygon_a, polygon_b, true);
				} else {
					full_contacts = clip(plane_normal_b, polygon_b, polygon_a, false);
				}

				contacts = reduce(full_contacts);
			}

			if small_array.len(contacts) == 0 {
				return nil;
			}
			
			return Contact_Manifold { normal, contacts };
		}
	}
	
	return nil;
}

@(private="file")
colliding :: proc(hull_a, hull_b: ^Collision_Hull) -> Maybe(Simplex) {
	direction := linalg.Vector3f32 {0.0, 0.0, 1.0};
	v := support(hull_a, hull_b, direction);
	zero := linalg.Vector3f32 {0.0, 0.0, 0.0};
	
	simplex := Simplex {
		[4]linalg.Vector3f32 {v, zero, zero, zero},
		1,
	};
	
	direction = -direction;
	iteration := 0;

	for {
		if iteration > 50 {
			fmt.println("Reached max GJK iterations for entity collision");
			return nil;
		}

		v = support(hull_a, hull_b, direction);
		simplex.vertices[simplex.overwrite_index] = v;

		if linalg.dot(direction, v) <= 0.0 {
			return nil;
		}

		if evaluate_and_evolve_simplex(&simplex, &direction) {
			return simplex;
		}

		iteration += 1;
	}
}

@(private="file")
support :: proc(hull_a, hull_b: ^Collision_Hull, direction: linalg.Vector3f32) -> linalg.Vector3f32 {
	// We do b first then a because we want the collision normal to point from b to a
	v1 := furthest_point_hull(hull_b, direction);
	v2 := furthest_point_hull(hull_a, -direction);

	return v1 - v2;
}

@(private="file")
find_collision_normal :: proc(simplex: ^Simplex, hull_a, hull_b: ^Collision_Hull) -> Maybe(linalg.Vector3f32) {
	a := simplex.vertices[0];
	b := simplex.vertices[1];
	c := simplex.vertices[2];
	d := simplex.vertices[3];

	ac := c - a;
	ab := b - a;
	da := a - d;
	db := b - d;
	dc := c - d;

	acb_norm := linalg.normalize(linalg.cross(ac, ab));
	dab_norm := linalg.normalize(linalg.cross(da, db));
	dbc_norm := linalg.normalize(linalg.cross(db, dc));
	dca_norm := linalg.normalize(linalg.cross(dc, da));

	polytope := Polytope {
		vertices = make([dynamic]linalg.Vector3f32, context.temp_allocator),
		faces = make([dynamic]Face, context.temp_allocator),
	};

	append(&polytope.vertices, a, b, c, d);
	append(&polytope.faces,
		Face {0, 2, 1, acb_norm},
		Face {3, 0, 1, dab_norm},
		Face {3, 1, 2, dbc_norm},
		Face {3, 2, 0, dca_norm},
	);

	iteration := 0;

	for {
		if iteration > 50 {
			fmt.println("Reached max EPA iterations for entity collision");
			return nil;
		}

		face_index, distance := find_closest_face(&polytope);
		face := &polytope.faces[face_index];
		point := support(hull_a, hull_b, face.normal);

		if linalg.dot(face.normal, point) - distance < 0.0005 {
			if distance <= 0.0005 {
				return nil;
			}

			return face.normal;
		}
		
		expand_polytope(&polytope, point, nil);
		iteration += 1;
	}
}