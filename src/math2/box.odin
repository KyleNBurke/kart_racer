package math2;

import "core:math/linalg";
import "core:testing";

BOX3F32_STANDARD :: Box3f32 {
	linalg.Vector3f32 {-1.0, -1.0, -1.0},
	linalg.Vector3f32 {1.0, 1.0, 1.0},
};

BOX3F32_ZERO :: Box3f32 {
	linalg.Vector3f32 {0.0, 0.0, 0.0},
	linalg.Vector3f32 {0.0, 0.0, 0.0},
};

Box3f32 :: struct {
	min: linalg.Vector3f32,
	max: linalg.Vector3f32,
}

box_center :: proc(using b: Box3f32) -> linalg.Vector3f32 {
	return (min + max) / 2.0;
}

box_extent :: proc(using b: Box3f32) -> linalg.Vector3f32 {
	return (max - min) / 2.0;
}

box_contains :: proc(a, b: Box3f32) -> bool {
	return b.min.x >= a.min.x && b.max.x <= a.max.x &&
		b.min.y >= a.min.y && b.max.y <= a.max.y &&
		b.min.z >= a.min.z && b.max.z <= a.max.z;
}

box_intersects :: proc(a, b: Box3f32) -> bool {
	return a.min.x < b.max.x && a.max.x > b.min.x &&
		a.min.y < b.max.y && a.max.y > b.min.y &&
		a.min.z < b.max.z && a.max.z > b.min.z;
}

box_union :: proc(b1, b2, b3, b4: Box3f32) -> Box3f32 {
	min_x := min(b1.min.x, b2.min.x, b3.min.x, b4.min.x);
	min_y := min(b1.min.y, b2.min.y, b3.min.y, b4.min.y);
	min_z := min(b1.min.z, b2.min.z, b3.min.z, b4.min.z);
	min := linalg.Vector3f32 {min_x, min_y, min_z};

	max_x := max(b1.max.x, b2.max.x, b3.max.x, b4.max.x);
	max_y := max(b1.max.y, b2.max.y, b3.max.y, b4.max.y);
	max_z := max(b1.max.z, b2.max.z, b3.max.z, b4.max.z);
	max := linalg.Vector3f32 {max_x, max_y, max_z};

	return Box3f32 {min, max};
}

@(test, private)
test_box_contains :: proc(t: ^testing.T) {
	a := Box3f32 {linalg.Vector3f32 {-3.0, 2.0, 0.0}, linalg.Vector3f32 {1.0, 5.0, 3.0}};
	b := Box3f32 {linalg.Vector3f32 {-2.0, 3.0, 1.0}, linalg.Vector3f32 {0.0, 4.0, 3.0}};
	testing.expect(t, box_contains(a, b));

	a = Box3f32 {linalg.Vector3f32 {-3.0, 2.0, 3.0}, linalg.Vector3f32 {1.0, 5.0, 4.0}};
	b = Box3f32 {linalg.Vector3f32 {-2.0, 2.0, 3.0}, linalg.Vector3f32 {1.0, 4.0, 4.0}};
	testing.expect(t, box_contains(a, b));

	a = Box3f32 {linalg.Vector3f32 {-3.0, 2.0, 0.0}, linalg.Vector3f32 {1.0, 5.0, 1.0}};
	b = Box3f32 {linalg.Vector3f32 {-5.0, -4.0, 3.0}, linalg.Vector3f32 {1.0, 4.0, 4.0}};
	testing.expect(t, !box_contains(a, b))
}