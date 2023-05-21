package main;

import "core:container/small_array";
import "core:math";
import "core:math/linalg";
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
	// Note, the direction is not normalized so neither would the local_direction be.
	local_direction := math2.quaternion_transform_direction(hull.inv_global_orientation, direction);
	point: linalg.Vector3f32;

	switch hull.kind {
		case .Box:
			point = linalg.Vector3f32 {
				math.sign_f32(local_direction.x),
				math.sign_f32(local_direction.y),
				math.sign_f32(local_direction.z),
			};

		case .Cylinder:
			xz: linalg.Vector2f32;
			if local_direction.x == 0 && local_direction.z == 0 {
				xz = linalg.Vector2f32 {0, 1};
			} else {
				xz = linalg.normalize(linalg.Vector2f32 {local_direction.x, local_direction.z});
			}

			point = linalg.Vector3f32 {
				xz.x,
				math.sign_f32(local_direction.y),
				xz.y
			};

		case .Sphere:
			point = linalg.normalize(local_direction);

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
	d := math2.quaternion_transform_direction(hull.inv_global_orientation, collision_normal);
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
			d_norm := linalg.normalize(d);
			dot := linalg.dot(d_norm, linalg.VECTOR3F32_Y_AXIS);

			if math.acos(abs(dot)) < math.PI / 4 {
				// The direction is pointing up or down
				y, angle_dir: f32;

				if dot > 0 {
					y = 1;
					angle_dir = -1;
				} else {
					y = -1;
					angle_dir = 1;
				}

				plane_normal = linalg.Vector3f32 {0, y, 0};
				
				POINT_COUNT :: 4;
				ANGLE_INCREMENT := math.TAU / f32(POINT_COUNT);

				for i in 0..<POINT_COUNT {
					angle := angle_dir * f32(i) * ANGLE_INCREMENT;
					x := math.cos(angle);
					z := math.sin(angle);
					
					append(&polygon, linalg.Vector3f32 {x, y, z});
				}
			} else {
				// The direction is pointing sideways
				xz := linalg.normalize(linalg.Vector2f32 {d_norm.x, d_norm.z});
				plane_normal = linalg.Vector3f32 {xz.x, 0, xz.y};
				
				append(&polygon,
					linalg.Vector3f32 {xz.x,  1, xz.y},
					linalg.Vector3f32 {xz.x, -1, xz.y});
			}
		
		case .Sphere:
			unreachable();
		
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

			if d0 * d1 < -0.0001 {
				t := d0 / (d0 - d1);
				p := (inc_b - inc_a) * t + inc_a;

				append(&new_points, p);
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

clip_line :: proc(normal: linalg.Vector3f32, offset: f32, a: linalg.Vector3f32, b: ^linalg.Vector3f32) {
	depth_a := linalg.dot(normal, a) - offset;
	depth_b := linalg.dot(normal, b^) - offset;

	if depth_b > 0 {
		t := depth_a / (depth_a - depth_b);
		b^ = (b^ - a) * t + a;
	}
}

// This is defined to return up to 4 contacts. However, only 0, 1 or 2 will be returned. We use 4 to avoid the type conversion Small_Array(2, Contact) -> Small_Array(4, Contact)
line_clip_poly_is_ref :: proc(ref_plane_normal: linalg.Vector3f32, ref_polygon: [dynamic]linalg.Vector3f32, line_a, line_b: linalg.Vector3f32) -> small_array.Small_Array(4, Contact) {
	// Clip the incident line between all the edges of the reference polygon. That should always keep 2 points. Then run those 2 points through the final clip.

	inc_a := line_a;
	inc_b := line_b;
	
	for ref_a, ref_index_a in ref_polygon {
		ref_index_b := (ref_index_a + 1) % len(ref_polygon);
		ref_b := ref_polygon[ref_index_b];
		ref_edge := ref_b - ref_a;

		normal := linalg.normalize(linalg.cross(ref_edge, ref_plane_normal));
		offset := linalg.dot(normal, ref_a);

		clip_line(normal, offset, inc_a, &inc_b);
		clip_line(normal, offset, inc_b, &inc_a);
	}

	contacts: small_array.Small_Array(4, Contact);
	ref_a := ref_polygon[0];
	offset := linalg.dot(ref_plane_normal, ref_a);

	depth_a := linalg.dot(ref_plane_normal, inc_a) - offset;
	depth_b := linalg.dot(ref_plane_normal, inc_b) - offset;

	if depth_a < 0 {
		projection := inc_a + ref_plane_normal * -depth_a;
		small_array.append(&contacts, Contact { inc_a, projection });
	}

	if depth_b < 0 {
		projection := inc_b + ref_plane_normal * -depth_b;
		small_array.append(&contacts, Contact { inc_b, projection });
	}

	return contacts;
}

// This is defined to return up to 4 contacts. However, only 0, 1 or 2 will be returned. We use 4 to avoid the type conversion Small_Array(2, Contact) -> Small_Array(4, Contact)
line_clip_line_is_ref :: proc(ref_normal, line_a, line_b: linalg.Vector3f32, inc_polygon: [dynamic]linalg.Vector3f32) -> small_array.Small_Array(4, Contact) {
	// If the line is reference, we know it must run through the coplanar polygon and give 1 or 2 intersection points. It may be possible to return 0
	// due to floating point weirdness? If we have 2 points, we clip them against the end planes of the reference line. Then run those 2 points through
	// the final clip.

	points: [2]linalg.Vector3f32;
	points_index := 0;

	ref_edge := line_b - line_a;
	normal := linalg.normalize(linalg.cross(ref_edge, ref_normal));
	offset := linalg.dot(normal, line_a);

	for inc_a, inc_index_a in inc_polygon {
		inc_index_b := (inc_index_a + 1) % len(inc_polygon);
		inc_b := inc_polygon[inc_index_b];

		depth_a := linalg.dot(normal, inc_a) - offset;
		depth_b := linalg.dot(normal, inc_b) - offset;

		if depth_a * depth_b < 0 {
			t := depth_a / (depth_a - depth_b);
			points[points_index] = (inc_b - inc_a) * t + inc_a;

			points_index += 1;
			if points_index == 2 do break;
		}
	}

	if points_index < 2 {
		return {};
	}

	{
		norm_to_b := linalg.normalize(line_b - line_a);
		offset := linalg.dot(norm_to_b, line_b);

		clip_line(norm_to_b, offset, points[0], &points[1]);
		clip_line(norm_to_b, offset, points[1], &points[0]);
	}

	{
		norm_to_a := linalg.normalize(line_a - line_b);
		offset := linalg.dot(norm_to_a, line_a);

		clip_line(norm_to_a, offset, points[0], &points[1]);
		clip_line(norm_to_a, offset, points[1], &points[0]);
	}

	contacts: small_array.Small_Array(4, Contact);

	{
		offset := linalg.dot(ref_normal, line_a);
		inc_a := points[0];
		inc_b := points[1];
		depth_a := linalg.dot(ref_normal, inc_a) - offset;
		depth_b := linalg.dot(ref_normal, inc_b) - offset;

		if depth_a < 0 {
			projection := inc_a + ref_normal * -depth_a;
			small_array.append(&contacts, Contact { inc_a, projection });
		}
	
		if depth_b < 0 {
			projection := inc_b + ref_normal * -depth_b;
			small_array.append(&contacts, Contact { inc_b, projection });
		}
	}

	return contacts;
}
// This is defined to return up to 4 contacts. However, only 0, 1 or 2 will be returned. We use 4 to avoid the type conversion Small_Array(2, Contact) -> Small_Array(4, Contact)
line_clip_lines :: proc(ref_normal, ref_a, ref_b, inc_a, inc_b: linalg.Vector3f32, a_is_ref: bool) -> small_array.Small_Array(4, Contact) {
	// In the case of 2 lines we first determine whether they intersect. If they intersect, the final clip only operates on the intersection point.
	// If they don't intersect, we clip the end points between the reference line and run the final clip on those two points.

	points: [2]linalg.Vector3f32;
	points_count := 0;

	ref_edge := ref_b - ref_a;
	normal := linalg.normalize(linalg.cross(ref_edge, ref_normal));
	offset := linalg.dot(normal, ref_a);

	inc_depth_a := linalg.dot(normal, inc_a) - offset;
	inc_depth_b := linalg.dot(normal, inc_b) - offset;

	if inc_depth_a * inc_depth_b < 0 {
		t := inc_depth_a / (inc_depth_a - inc_depth_b);
		points[0] = (inc_b - inc_a) * t + inc_a;
		points_count = 1;
	} else {
		inc_a, inc_b := inc_a, inc_b;

		norm_to_b := linalg.normalize(ref_b - ref_a);
		offset = linalg.dot(norm_to_b, ref_b);
		clip_line(norm_to_b, offset, inc_a, &inc_b);
		clip_line(norm_to_b, offset, inc_b, &inc_a);

		norm_to_a := linalg.normalize(ref_a - ref_b);
		offset = linalg.dot(norm_to_a, ref_a);
		clip_line(norm_to_a, offset, inc_a, &inc_b);
		clip_line(norm_to_a, offset, inc_b, &inc_a);

		points[0], points[1] = inc_a, inc_b;
		points_count = 2;
	}

	contacts: small_array.Small_Array(4, Contact);
	offset = linalg.dot(ref_normal, ref_a);

	for i in 0..<points_count {
		point := points[i];
		depth := linalg.dot(ref_normal, point) - offset;

		if depth < 0 {
			projection := point + ref_normal * -depth;
			contact: Contact;

			if a_is_ref {
				contact.position_a = projection;
				contact.position_b = point;
			} else {
				contact.position_a = point;
				contact.position_b = projection;
			}

			small_array.append(&contacts, contact);
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