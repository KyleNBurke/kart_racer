package main;

import "core:container/small_array";
import "core:math";
import "core:math/linalg";
import "core:slice";
import "math2";

Contact :: struct {
	position_a: linalg.Vector3f32,
	position_b: linalg.Vector3f32,
}

Contact_Manifold :: struct {
	normal: linalg.Vector3f32,
	contacts: small_array.Small_Array(4, Contact),
}

Simplex :: struct {
	vertices: [4]linalg.Vector3f32,
	overwrite_index: u32,
}

Polytope :: struct {
	vertices: [dynamic]linalg.Vector3f32,
	markers: [dynamic]bool, // Only used in ground collisions
	faces: [dynamic]Face,
}

Face :: struct {a, b, c: int, normal: linalg.Vector3f32 }

furthest_point_hull :: proc(hull: ^Collision_Hull, direction: linalg.Vector3f32) -> linalg.Vector3f32 {
	d := math2.matrix3_transform_direction(hull.inv_global_transform, direction);
	point: linalg.Vector3f32;

	switch hull.kind {
		case .Box:
			point = linalg.Vector3f32 {math.sign_f32(d.x), math.sign_f32(d.y), math.sign_f32(d.z)};
		case .Cylinder:
			xz := linalg.normalize(linalg.Vector2f32 {d.x, d.z});
			point = linalg.Vector3f32 {xz.x, math.sign_f32(d.y), xz.y};
		case .Mesh:
			unimplemented();
	}

	return math2.matrix4_transform_point(hull.global_transform, point);
}

evaluate_and_evolve_simplex :: proc(using simplex: ^Simplex, direction: ^linalg.Vector3f32) -> bool {
	switch overwrite_index {
		case 1:
			a := vertices[0];
			b := vertices[1];
			ab := b - a;
			a0 := -a;

			direction^ = linalg.cross(linalg.cross(ab, a0), ab);

			overwrite_index += 1;
			return false;

		case 2:
			a := simplex.vertices[0];
			b := simplex.vertices[1];
			c := simplex.vertices[2];
			ab := b - a;
			ac := c - a;

			direction^ = linalg.cross(ab, ac);

			a0 := -a;
			if linalg.dot(a0, direction^) < 0.0 {
				direction^ = -direction^;

				// Swap so that the winding order of abc is such that the face normals will point outwards in the next iteration
				vertices[0], vertices[1] = vertices[1], vertices[0];
			}

			overwrite_index += 1;
			return false;

		case 3:
			a := simplex.vertices[0];
			b := simplex.vertices[1];
			c := simplex.vertices[2];
			d := simplex.vertices[3];

			da := a - d;
			db := b - d;
			dc := c - d;
			d0 := -d;

			dab_norm := linalg.cross(da, db);
			if linalg.dot(dab_norm, d0) > 0.0 {
				direction^ = dab_norm;

				// Remove c
				simplex.vertices[2] = simplex.vertices[3];

				return false;
			}

			dbc_norm := linalg.cross(db, dc);
			if linalg.dot(dbc_norm, d0) > 0.0 {
				direction^ = dbc_norm;

				// Remove a
				simplex.vertices[0] = simplex.vertices[1];
				simplex.vertices[1] = simplex.vertices[2];
				simplex.vertices[2] = simplex.vertices[3];

				return false;
			}

			dca_norm := linalg.cross(dc, da);
			if linalg.dot(dca_norm, d0) > 0.0 {
				direction^ = dca_norm;

				// Remove b and swap so that the winding order of abc is such that the face normals will point outwards in the next iteration
				simplex.vertices[1] = simplex.vertices[0];
				simplex.vertices[0] = simplex.vertices[2];
				simplex.vertices[2] = simplex.vertices[3];

				return false;
			}

			return true;
		case:
			unreachable();
	}
}

find_closest_face :: proc(polytope: ^Polytope) -> (int, f32) {
	closest_index := 0;
	closest_distance: f32 = math.F32_MAX;

	for face, i in &polytope.faces {
		a := polytope.vertices[face.a];
		distance := linalg.dot(face.normal, a);

		if distance < closest_distance {
			closest_index = i;
			closest_distance = distance;
		}
	}

	return closest_index, closest_distance;
}

// The marker is only used for ground collisions
expand_polytope :: proc(polytope: ^Polytope, v: linalg.Vector3f32, marker: Maybe(bool)) {
	edges := make([dynamic][2]int, context.temp_allocator);

	for i := len(polytope.faces) - 1; i >= 0; i -= 1 {
		face := &polytope.faces[i];
		a := polytope.vertices[face.a];
		av := v - a;

		if linalg.dot(face.normal, av) > 0.0 {
			develop_unique_edges(&edges, face.a, face.b);
			develop_unique_edges(&edges, face.b, face.c);
			develop_unique_edges(&edges, face.c, face.a);
			
			unordered_remove(&polytope.faces, i);
		}
	}

	append(&polytope.vertices, v);
	
	if marker, ok := marker.?; ok {
		append(&polytope.markers, marker);
	}

	v_index := len(polytope.vertices) - 1;

	for edge in &edges {
		a_index := edge[0];
		b_index := edge[1];

		a := polytope.vertices[a_index];
		b := polytope.vertices[b_index];
		
		ab := b - a;
		av := v - a;
		normal := linalg.normalize(linalg.cross(ab, av));

		append(&polytope.faces, Face {a_index, b_index, v_index, normal});
	}
}

develop_unique_edges :: proc(edges: ^[dynamic][2]int, a_index, b_index: int) {
	for edge, edge_index in edges {
		saved_a_index, saved_b_index := edge[0], edge[1];

		// We compare the opposite indices because the winding order of the faces is such that a shared edge will be in reverse order
		if saved_a_index == b_index && saved_b_index == a_index {
			unordered_remove(edges, edge_index);
			return;
		}
	}

	append(edges, [?]int {a_index, b_index});
}

find_plane_normal_and_polygon :: proc(hull: ^Collision_Hull, collision_normal: linalg.Vector3f32) -> (plane_normal: linalg.Vector3f32, polygon: [dynamic]linalg.Vector3f32) {
	d := math2.matrix3_transform_direction(hull.inv_global_transform, collision_normal);
	polygon = make([dynamic]linalg.Vector3f32, context.temp_allocator);
	
	switch hull.kind {
		case .Box:
			if abs(d.x) >= abs(d.y) && abs(d.x) >= abs(d.z) {
				if d.x > 0.0 {
					plane_normal = linalg.Vector3f32 {1.0, 0.0, 0.0};
					append(&polygon,
						linalg.Vector3f32 {1.0, 1.0, 1.0},
						linalg.Vector3f32 {1.0, -1.0, 1.0},
						linalg.Vector3f32 {1.0, -1.0, -1.0},
						linalg.Vector3f32 {1.0, 1.0, -1.0},
					);
				} else {
					plane_normal = linalg.Vector3f32 {-1.0, 0.0, 0.0};
					append(&polygon,
						linalg.Vector3f32 {-1.0, 1.0, 1.0},
						linalg.Vector3f32 {-1.0, 1.0, -1.0},
						linalg.Vector3f32 {-1.0, -1.0, -1.0},
						linalg.Vector3f32 {-1.0, -1.0, 1.0},
					);
				}

			} else if abs(d.z) > abs(d.x) && abs(d.z) > abs(d.y) {
				if d.z > 0.0 {
					plane_normal = linalg.Vector3f32 {0.0, 0.0, 1.0};
					append(&polygon,
						linalg.Vector3f32 {1.0, 1.0, 1.0},
						linalg.Vector3f32 {-1.0, 1.0, 1.0},
						linalg.Vector3f32 {-1.0, -1.0, 1.0},
						linalg.Vector3f32 {1.0, -1.0, 1.0},
					);
				} else {
					plane_normal = linalg.Vector3f32 {0.0, 0.0, -1.0};
					append(&polygon,
						linalg.Vector3f32 {1.0, 1.0, -1.0},
						linalg.Vector3f32 {1.0, -1.0, -1.0},
						linalg.Vector3f32 {-1.0, -1.0, -1.0},
						linalg.Vector3f32 {-1.0, 1.0, -1.0},
					);
				}
			} else {
				if d.y > 0.0 {
					plane_normal = linalg.Vector3f32 {0.0, 1.0, 0.0};
					append(&polygon,
						linalg.Vector3f32 {1.0, 1.0, 1.0},
						linalg.Vector3f32 {1.0, 1.0, -1.0},
						linalg.Vector3f32 {-1.0, 1.0, -1.0},
						linalg.Vector3f32 {-1.0, 1.0, 1.0},
					);
				} else {
					plane_normal = linalg.Vector3f32 {0.0, -1.0, 0.0};
					append(&polygon,
						linalg.Vector3f32 {1.0, -1.0, 1.0},
						linalg.Vector3f32 {-1.0, -1.0, 1.0},
						linalg.Vector3f32 {-1.0, -1.0, -1.0},
						linalg.Vector3f32 {1.0, -1.0, -1.0},
					);
				}
			}

		case .Cylinder:
			unimplemented();
		
		case .Mesh:
			unimplemented();
	}

	plane_normal = linalg.normalize(math2.matrix4_transform_direction(hull.global_transform, plane_normal));

	for point in &polygon {
		point = math2.matrix4_transform_point(hull.global_transform, point);
	}

	return;
}

clip :: proc(ref_plane_normal: linalg.Vector3f32, ref_polygon, inc_polygon: [dynamic]linalg.Vector3f32, a_is_ref: bool) -> [dynamic]Contact {
	points := inc_polygon;

	for ref_a, ref_index_a in ref_polygon {
		ref_index_b := (ref_index_a + 1) % len(ref_polygon);
		ref_b := ref_polygon[ref_index_b];
		ref_edge := ref_b - ref_a;

		normal := linalg.normalize(linalg.cross(ref_edge, ref_plane_normal));
		offset := linalg.dot(normal, ref_a);

		new_points := make([dynamic]linalg.Vector3f32, context.temp_allocator);

		for inc_a, inc_index_a in points {
			inc_index_b := (inc_index_a + 1) % len(points);
			inc_b := points[inc_index_b];

			d0 := linalg.dot(normal, inc_a) - offset;
			d1 := linalg.dot(normal, inc_b) - offset;
			
			if d0 <= 0.0 {
				append(&new_points, inc_a);
			}

			if d0 * d1 < 0.0 {
				u := d0 / (d0 - d1);

				e := inc_b - inc_a;
				e *= u;
				e += inc_a;

				append(&new_points, e);
			}
		}

		points = new_points;
	}

	ref_a := ref_polygon[0];
	offset := linalg.dot(ref_plane_normal, ref_a);

	contacts := make([dynamic]Contact, context.temp_allocator);

	for point in points {
		depth := linalg.dot(ref_plane_normal, point) - offset;

		if depth < 0.0 {
			projection := point + ref_plane_normal * -depth;
			contact: Contact;

			if a_is_ref {
				contact.position_a = projection;
				contact.position_b = point;
			} else {
				contact.position_a = point;
				contact.position_b = projection;
			}

			append(&contacts, contact);
		}
	}

	return contacts;
}

// As is stands like this, we could eliminate this proc and only return at most 4 contacts from clip.
// In the future, if we want a more complicated manifold reduction proct, this would be the place to do it.
// So for now, we'll keep it.
reduce :: proc(contacts: [dynamic]Contact) -> small_array.Small_Array(4, Contact) {
	reduced_contacts: small_array.Small_Array(4, Contact);
	count := min(len(contacts), 4);

	for i in 0..<count {
		small_array.append(&reduced_contacts, contacts[i]);
	}

	return reduced_contacts;
}