package main;

import "core:math";
import "core:math/linalg";
import "core:container/small_array";
import "core:fmt";
import "math2";

Triangle :: struct { a, b, c, normal: linalg.Vector3f32 }

GroundHull :: small_array.Small_Array(6, linalg.Vector3f32);

evaluate_ground_collision :: proc(triangle_positions: []f32, ground_grid_triangle: ^Ground_Grid_Evaluated_Triangle, entity_hull: ^Collision_Hull) -> Maybe(Contact_Manifold) {
	if !math2.box_intersects(entity_hull.global_bounds, ground_grid_triangle.bounds) {
		return nil;
	}

	triangle := form_triangle(ground_grid_triangle);

	simplex, ok_colliding := colliding(&triangle, entity_hull).?;
	if !ok_colliding {
		return nil;
	}

	ground_hull := form_convex_ground_hull(triangle.normal, ground_grid_triangle);
	normal, ok_normal := find_collision_normal(&simplex, &ground_hull, entity_hull).?;
	if !ok_normal {
		return nil;
	}

	triangle_normal := triangle.normal;
	triangle_polygon := make([dynamic]linalg.Vector3f32, context.temp_allocator);
	append(&triangle_polygon, triangle.a, triangle.b, triangle.c);

	hull_normal, hull_polygon := find_plane_normal_and_polygon(entity_hull, -normal);

	a_is_ref := abs(linalg.dot(normal, hull_normal)) > abs(linalg.dot(normal, triangle_normal));
	contacts: small_array.Small_Array(4, Contact);

	if len(hull_polygon) == 2 {
		if a_is_ref {
			contacts = line_clip_line_is_ref(hull_normal, hull_polygon[0], hull_polygon[1], triangle_polygon);
		} else {
			contacts = line_clip_poly_is_ref(triangle_normal, triangle_polygon, hull_polygon[0], hull_polygon[1]);
		}
	} else {
		full_contacts: [dynamic]Contact;

		if a_is_ref {
			full_contacts = clip(hull_normal, hull_polygon, triangle_polygon, true);
		} else {
			full_contacts = clip(triangle_normal, triangle_polygon, hull_polygon, false);
		}

		contacts = reduce(full_contacts);
	}

	if small_array.len(contacts) == 0 {
		return nil;
	}

	return Contact_Manifold { normal, contacts };
}

form_triangle :: proc(using ground_grid_triangle: ^Ground_Grid_Evaluated_Triangle) -> Triangle {
	ab := b - a;
	ac := c - a;
	normal := linalg.normalize(linalg.cross(ab, ac));

	return Triangle { a, b, c, normal };
}

@(private="file")
colliding :: proc(triangle: ^Triangle, entity_hull: ^Collision_Hull) -> Maybe(Simplex) {
	direction := linalg.Vector3f32 {0.0, 0.0, 1.0};
	v := support_gjk(triangle, entity_hull, direction);
	zero := linalg.Vector3f32 {0.0, 0.0, 0.0};
	
	simplex := Simplex {
		[4]linalg.Vector3f32 {v, zero, zero, zero},
		1,
	};
	
	direction = -direction;
	iteration := 0;

	for {
		if iteration > 50 {
			fmt.println("Reached max GJK iterations for ground collision");
			return nil;
		}

		v := support_gjk(triangle, entity_hull, direction);
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
support_gjk :: proc(triangle: ^Triangle, hull: ^Collision_Hull, direction: linalg.Vector3f32) -> linalg.Vector3f32 {
	v1 := furthest_point_triangle(triangle, direction);
	v2 := furthest_point_hull(hull, -direction);

	return v1 - v2;
}

furthest_point_triangle :: proc(triangle: ^Triangle, direction: linalg.Vector3f32) -> linalg.Vector3f32 {
	furthest_dot := linalg.dot(direction, triangle.a);
	furthest_vertex := triangle.a;

	dot := linalg.dot(direction, triangle.b);
	if dot > furthest_dot {
		furthest_dot = dot;
		furthest_vertex = triangle.b;
	}

	dot = linalg.dot(direction, triangle.c);
	if dot > furthest_dot {
		furthest_vertex = triangle.c;
	}

	return furthest_vertex;
}

form_convex_ground_hull :: proc(triangle_normal: linalg.Vector3f32, using g_triangle: ^Ground_Grid_Evaluated_Triangle) -> GroundHull {
	hull: GroundHull;
	small_array.append(&hull, a, b, c);

	if g1 != VEC3_ZERO {
		ag1 := g1 - a;
		ab := b - a;
		adjacent_normal := linalg.normalize(linalg.cross(ag1, ab));

		ab_normal := linalg.normalize(linalg.cross(ab, triangle_normal));

		if linalg.dot(adjacent_normal, ab_normal) > 0.0001 {
			small_array.append(&hull, g1);
		} else {
			ca := linalg.normalize(a - c);
			ca_len := 3.0 / linalg.dot(ca, ab_normal);
			hull.data[0] += ca * ca_len;

			cb := linalg.normalize(b - c);
			cb_len := 3.0 / linalg.dot(cb, ab_normal);
			hull.data[1] += cb * cb_len;
		}
	}

	if g2 != VEC3_ZERO {
		bg2 := g2 - b;
		bc := c - b;
		adjacent_normal := linalg.normalize(linalg.cross(bg2, bc));

		bc_normal := linalg.normalize(linalg.cross(bc, triangle_normal));

		if linalg.dot(adjacent_normal, bc_normal) > 0.0001 {
			small_array.append(&hull, g2);
		} else {
			ab := linalg.normalize(b - a);
			ab_len := 3.0 / linalg.dot(ab, bc_normal);
			hull.data[1] += ab * ab_len;

			ac := linalg.normalize(c - a);
			ac_len := 3.0 / linalg.dot(ac, bc_normal);
			hull.data[2] += ac * ac_len;
		}
	}

	if g3 != VEC3_ZERO {
		cg3 := g3 - c;
		ca := a - c;
		adjacent_normal := linalg.normalize(linalg.cross(cg3, ca));

		ca_normal := linalg.normalize(linalg.cross(ca, triangle_normal));

		if linalg.dot(adjacent_normal, ca_normal) > 0.0001 {
			small_array.append(&hull, g3);
		} else {
			bc := linalg.normalize(c - b);
			bc_len := 3.0 / linalg.dot(bc, ca_normal);
			hull.data[2] += bc * bc_len;

			ba := linalg.normalize(a - b);
			ba_len := 3.0 / linalg.dot(ba, ca_normal);
			hull.data[0] += ba * ba_len;
		}
	}

	return hull;
}

@(private="file")
find_collision_normal :: proc(simplex: ^Simplex, ground_hull: ^GroundHull, entity_hull: ^Collision_Hull) -> Maybe(linalg.Vector3f32) {
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
		markers = make([dynamic]bool, context.temp_allocator),
		faces = make([dynamic]Face, context.temp_allocator),
	};

	append(&polytope.vertices, a, b, c, d);
	append(&polytope.markers, true, true, true, true);
	append(&polytope.faces,
		Face {0, 2, 1, acb_norm},
		Face {3, 0, 1, dab_norm},
		Face {3, 1, 2, dbc_norm},
		Face {3, 2, 0, dca_norm},
	);

	iteration := 0;

	for {
		if iteration > 50 {
			fmt.println("Reached max EPA iterations for ground collision");
			return nil;
		}

		face_index, distance := find_closest_face(&polytope);
		face := &polytope.faces[face_index];
		point, marker := support_epa(ground_hull, entity_hull, face.normal);

		if linalg.dot(face.normal, point) - distance < 0.0005 {
			if distance <= 0.0005 {
				return nil;
			}

			markers := &polytope.markers;

			if !markers[face.a] || !markers[face.b] || !markers[face.c] {
				return nil;
			}

			return face.normal;
		}
		
		expand_polytope(&polytope, point, marker);
		iteration += 1;
	}
}

@(private="file")
support_epa :: proc(ground_hull: ^GroundHull, entity_hull: ^Collision_Hull, direction: linalg.Vector3f32) -> (linalg.Vector3f32, bool) {
	v1, marker := furthest_point_ground_hull(ground_hull, direction);
	v2 := furthest_point_hull(entity_hull, -direction);

	return v1 - v2, marker;
}

@(private="file")
furthest_point_ground_hull :: proc(ground_hull: ^GroundHull, direction: linalg.Vector3f32) -> (linalg.Vector3f32, bool) {
	furthest_dot: f32 = math.F32_MIN;
	furthest_index := 0;

	for point, i in &ground_hull.data {
		dot := linalg.dot(direction, point);

		if dot > furthest_dot {
			furthest_dot = dot;
			furthest_index = i;
		}
	}

	point := ground_hull.data[furthest_index];
	marker := furthest_index < 3; // If the index is < 3 then we know it came from the reference triangle

	return point, marker;
}