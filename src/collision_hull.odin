package main;

import "core:slice";
import "core:math";
import "core:math/linalg";
import "math2";

Collision_Hull :: struct {
	local_orientation:      linalg.Quaternionf32,
	local_transform:        linalg.Matrix4f32,
	global_transform:       linalg.Matrix4f32,
	inv_global_orientation: linalg.Quaternionf32,
	inv_global_transform:   linalg.Matrix4f32,
	kind: Hull_Kind,
	local_bounds,
	global_bounds: math2.Box3f32,
	indices: [dynamic]u16,
	positions: [dynamic]f32,
}

Hull_Kind :: enum { Box, Cylinder, Sphere, Mesh }

init_collision_hull :: proc(
	local_position:    linalg.Vector3f32,
	local_orientation: linalg.Quaternionf32,
	local_size:        linalg.Vector3f32,
	kind:              Hull_Kind,
	maybe_indices:     Maybe([dynamic]u16) = nil,
	maybe_positions:   Maybe([dynamic]f32) = nil,
) -> Collision_Hull {
	hull: Collision_Hull;
	hull.local_orientation = local_orientation;
	hull.local_transform = linalg.matrix4_from_trs(local_position, local_orientation, local_size);
	hull.kind = kind;

	local_bounds: math2.Box3f32;

	switch kind {
	case .Box, .Cylinder, .Sphere:
		hull.local_bounds = math2.BOX3F32_STANDARD; // #todo This doesn't seem right to me if there is a local scale.
	case .Mesh:
		indices, indices_ok := maybe_indices.?;
		positions, positions_ok := maybe_positions.?;
		assert(indices_ok);
		assert(positions_ok);

		local_bounds_min := VEC3_INF;
		local_bounds_max := VEC3_NEG_INF;

		for triangle_index in 0..<len(indices) / 3 {
			a, b, c := math2.triangle_index_to_points(triangle_index, indices[:], positions[:]);

			local_bounds_min = linalg.min(local_bounds_min, linalg.min(a, b, c));
			local_bounds_max = linalg.max(local_bounds_max, linalg.max(a, b, c));
		}

		hull.local_bounds = math2.Box3f32 { local_bounds_min, local_bounds_max };
		hull.indices = indices;
		hull.positions = positions;
	}

	return hull;
}

// Be careful about calling this. The collision hull grid relies on the hull bounds to be exactly where it was during the last grid update. If this is called haphazardly, the collision hull grid may
// not be able to find the correct grid cells to remove the hulls. This can, of course be changed, it's just currently implemented this way.
update_entity_hull_transforms_and_bounds :: proc(entity: ^Entity, orientation: linalg.Quaternionf32, transform: linalg.Matrix4f32) {
	assert(len(entity.collision_hulls) > 0);
	entity_min: linalg.Vector3f32 = VEC3_INF;
	entity_max: linalg.Vector3f32 = VEC3_NEG_INF;

	for &hull in entity.collision_hulls {
		global_orientation := orientation * hull.local_orientation;
		hull.inv_global_orientation = linalg.quaternion_inverse(global_orientation);

		hull.global_transform = transform * hull.local_transform;
		hull.inv_global_transform = linalg.matrix4_inverse(hull.global_transform);

		// We can ignore the translation components and use a matrix 3 because we're transforming the extent with this which is a direction vector
		t := &hull.global_transform
		global_transform_abs := linalg.Matrix3f32 {
			abs(t[0][0]), abs(t[1][0]), abs(t[2][0]),
			abs(t[0][1]), abs(t[1][1]), abs(t[2][1]),
			abs(t[0][2]), abs(t[1][2]), abs(t[2][2]),
		};

		center := math2.matrix4_transform_point(hull.global_transform, math2.box_center(hull.local_bounds));
		extent := math2.matrix3_transform_direction(global_transform_abs, math2.box_extent(hull.local_bounds));

		hull.global_bounds.min = center - extent;
		hull.global_bounds.max = center + extent;

		entity_min = linalg.min(entity_min, hull.global_bounds.min);
		entity_max = linalg.max(entity_max, hull.global_bounds.max);
	}

	entity.bounds.min = entity_min;
	entity.bounds.max = entity_max;
}

Hull_Helpers :: struct {
	box_helper_geo_lookup: Geometry_Lookup,
	cylinder_helper_geo_lookup: Geometry_Lookup,
	sphere_helper_geo_lookup: Geometry_Lookup,
	hull_helpers: [dynamic]Entity_Lookup,
}

init_hull_helpers :: proc(hull_helpers: ^Hull_Helpers) {
	box_helper_geo, box_helper_geo_lookup := create_geometry("box hull visualizer", .Keep);
	geometry_make_box_helper(box_helper_geo, VEC3_NEG_ONE, VEC3_ONE)
	hull_helpers.box_helper_geo_lookup = box_helper_geo_lookup;

	cylinder_helper_geo, cylinder_helper_geo_lookup := create_geometry("cylinder hull visualizer", .Keep);
	geometry_make_cylinder_helper(cylinder_helper_geo);
	hull_helpers.cylinder_helper_geo_lookup = cylinder_helper_geo_lookup;

	sphere_helper_geo, sphere_helper_geo_lookup := create_geometry("sphere hull visualizer", .Keep);
	geometry_make_sphere_helper(sphere_helper_geo, VEC3_ZERO, 1);
	hull_helpers.sphere_helper_geo_lookup = sphere_helper_geo_lookup;
}

cleanup_hull_helpers :: proc(hull_helpers: ^Hull_Helpers) {
	delete(hull_helpers.hull_helpers);
}

update_entity_hull_helpers :: proc(hull_helpers: ^Hull_Helpers) {
	for lookup in hull_helpers.hull_helpers {
		remove_entity(lookup);
	}

	clear(&hull_helpers.hull_helpers);

	entities_count := len(entities_geos.entities);

	for i in 0..<entities_count {
		entity := entities_geos.entities[i];
		if entity.free do continue;

		for &hull in entity.collision_hulls {
			geometry_lookup: Geometry_Lookup;

			switch hull.kind {
			case .Box:
				geometry_lookup = hull_helpers.box_helper_geo_lookup;
			case .Cylinder:
				geometry_lookup = hull_helpers.cylinder_helper_geo_lookup;
			case .Sphere:
				geometry_lookup = hull_helpers.sphere_helper_geo_lookup;
			case .Mesh:
				// We would want to create a wireframe triangle geometry here using the indices and positions. This would be a good thing to do on laptop.
				// We actually wouldn't want to use a [dynamic]linalg.Vector3f32 for the positions in this case.
				continue;
			}

			helper_entity, helper_entity_lookup := create_entity("hull helper", geometry_lookup, Inanimate_Entity);
			helper_entity.transform = hull.global_transform;
			append(&hull_helpers.hull_helpers, helper_entity_lookup);
		}
	}
}

Ray_Hull_Contact :: struct {
	length: f32,
	normal: linalg.Vector3f32,
}

ray_intersects_hull :: proc(hull: ^Collision_Hull, origin, direction: linalg.Vector3f32, length: f32) -> Maybe(Ray_Hull_Contact) {
	local_origin := math2.matrix4_transform_point(hull.inv_global_transform, origin);

	// If the hull has a scale this will not be normalized. I think normalizing it changes the "scale" or "reference view" of the t value
	// in the cylinder case so they are smaller than what they should be. That can probably be corrected somehow but this doesn't seem to
	// need to be normalized so we can simply leave it unnormalized.
	local_direction := math2.matrix4_transform_direction(hull.inv_global_transform, direction);

	local_contact_normal: linalg.Vector3f32;
	contact_length: f32 = max(f32);

	switch hull.kind {
	case .Box:
		// We should look into using this method or something more efficient: https://tavianator.com/2011/ray_box.html

		// We could probably take another look at this and try to improve it. It would be nice if we could generate the faces to check.
		// Just remember, you cannot use the direction of the ray to derive the exact face the ray will pass through. You can use it
		// to find the faces which have normals poiting in the same direction.
		// Why are we doing best length here? The unbounded ray would pass through 2 faces but the backside is already being ignored.

		best_normal: linalg.Vector3f32;
		best_length := max(f32);

		face_normals :: [6]linalg.Vector3f32 {
			{  1,  0,  0 },
			{ -1,  0,  0 },
			{  0,  1,  0 },
			{  0, -1,  0 },
			{  0,  0,  1 },
			{  0,  0, -1 },
		};

		for face_normal in face_normals {
			dot := linalg.dot(local_direction, face_normal);

			// If the dot product is greator than zero, the ray would pass through the backside.
			if dot >= 0 do continue;

			face_point := face_normal;
			t := linalg.dot((face_point - local_origin), face_normal) / dot;
			if abs(t) > length do continue;
			p := local_origin + local_direction * t;
			intersecting := false;

			switch face_normal {
			case { 1, 0, 0 }, { -1, 0, 0 }:
				if p.z < 1 && p.z > -1 && p.y < 1 && p.y > -1 {
					intersecting = true;
				}

			case { 0, 1, 0 }, { 0, -1, 0 }:
				if p.x < 1 && p.x > -1 && p.z < 1 && p.z > -1 {
					intersecting = true;
				}

			case { 0, 0, 1 }, { 0, 0, -1 }:
				if p.x < 1 && p.x > -1 && p.y < 1 && p.y > -1 {
					intersecting = true;
				}

			case:
				unreachable();
			}

			if intersecting && t < best_length {
				best_normal = face_normal;
				best_length = t;
			}
		}

		if best_length != max(f32) {
			local_contact_normal = best_normal;
			contact_length = best_length;
		}

	case .Cylinder:
		s := local_origin;
		e := local_origin + local_direction * length;

		top_bot: {
			// If the y value of the ray is 0 then it's horizontal.
			if local_direction.y == 0 do break top_bot;

			y := math.sign(local_direction.y);
			depth_s := abs(s.y) - 1; // The - 1 is the distance to the horizontal plane
			depth_e := abs(e.y) - 1;

			if depth_s * depth_e < 0 {
				t := depth_s / (depth_s - depth_e);
				p := s + local_direction * t;

				if p.x * p.x + p.z * p.z >= 1 do break top_bot;

				local_contact_normal = { 0, -y, 0 };
				contact_length = t;
				break;
			}
		}

		sides: {
			// If the y value of the ray is 1 or -1 then it's vertical.
			if abs(local_direction.y) == 1 do break sides;

			v := local_direction;
			a := v.x * v.x + v.z * v.z;
			b := 2 * s.x * v.x + 2 * s.z * v.z;
			c := s.x * s.x + s.z * s.z - 1;

			j := b * b - 4 * a * c;
			if j < 0 do break sides;
			k := math.sqrt(b * b - 4 * a * c);
			q := 2 * a;

			t1 := (-b + k) / q;
			t2 := (-b - k) / q;
			t := min(t1, t2);

			if t <= 0 || t >= length {
				break sides;
			}

			p := s + t * v;
			if abs(p.y) >= 1 do break sides;

			local_contact_normal = { p.x, 0, p.z };
			contact_length = t;
		}

	case .Sphere:
		unreachable();

	case .Mesh:
		unimplemented();
	}

	if contact_length == max(f32) {
		return nil;
	} else {
		global_normal := linalg.normalize(math2.matrix4_transform_direction(hull.global_transform, local_contact_normal));
		return Ray_Hull_Contact { contact_length, global_normal };
	}
}