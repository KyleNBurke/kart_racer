package main;

import "core:slice";
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

	for hull in &entity.collision_hulls {
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

	cylinder_helper_geo, cylinder_helper_geo_lookup := create_geometry("cylinder hull visualizer", .Keep);
	geometry_make_cylinder_helper(cylinder_helper_geo);

	sphere_helper_geo, sphere_helper_geo_lookup := create_geometry("sphere hull visualizer", .Keep);
	geometry_make_sphere_helper(sphere_helper_geo, VEC3_ZERO, 1);

	hull_helpers.box_helper_geo_lookup = box_helper_geo_lookup;
	hull_helpers.cylinder_helper_geo_lookup = cylinder_helper_geo_lookup;
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

	for &entity, entity_index in entities_geos.entities {
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

			entity, entity_lookup := create_entity("hull helper", geometry_lookup, Inanimate_Entity);
			entity.transform = hull.global_transform;
			append(&hull_helpers.hull_helpers, entity_lookup);
		}
	}
}