package physics;

import "core:math/linalg";
import "../math2";

CollisionHull :: struct {
	local_transform: linalg.Matrix4f32,
	global_transform: linalg.Matrix4f32,
	inv_global_transform: linalg.Matrix3f32,
	kind: HullKind,
	local_bounds: math2.Box3f32,
	global_bounds: math2.Box3f32,
}

HullKind :: enum {Box, Cylinder, Mesh}

init_collision_hull :: proc(local_transform, global_entity_transform: linalg.Matrix4f32, kind: HullKind) -> CollisionHull {
	local_bounds: math2.Box3f32;

	switch kind {
		case .Box:
			local_bounds = math2.BOX3F32_STANDARD;
		case .Cylinder:
			local_bounds = math2.BOX3F32_STANDARD;
		case .Mesh:
			unimplemented();
	}

	hull := CollisionHull {
		local_transform,
		linalg.MATRIX4F32_IDENTITY,
		linalg.MATRIX3F32_IDENTITY,
		kind,
		local_bounds,
		math2.BOX3F32_ZERO,
	};

	update_collision_hull_global_transform_and_bounds(&hull, global_entity_transform);

	return hull;
}

// Be careful about calling this. The collision hull grid relies on the hull bounds to be exactly where it was during the last grid update. If this is called haphazardly, the collision hull grid may
// not be able to find the correct grid cells to remove the hulls from during update_hull_global_transform_mat_and_bounds(). This can, of course be changed, it's just currently implemented this way.
update_collision_hull_global_transform_and_bounds :: proc(using hull: ^CollisionHull, global_entity_transform: linalg.Matrix4f32) {
	global_transform = global_entity_transform * local_transform;
	inv_global_transform = linalg.matrix3_inverse(linalg.matrix3_from_matrix4(global_transform));

	// We can ignore the translation components and use a matrix 3 because we're transforming the extent with this which is a direction vector
	global_transform_abs := linalg.Matrix3f32 {
		abs(global_transform[0][0]), abs(global_transform[0][1]), abs(global_transform[0][2]),
		abs(global_transform[1][0]), abs(global_transform[1][1]), abs(global_transform[1][2]),
		abs(global_transform[2][0]), abs(global_transform[2][1]), abs(global_transform[2][2]),
	};

	center := math2.matrix4_transform_point(global_transform, math2.box_center(local_bounds));
	extent := math2.matrix3_transform_direction(global_transform_abs, math2.box_extent(local_bounds));

	global_bounds.min = center - extent;
	global_bounds.max = center + extent;
}