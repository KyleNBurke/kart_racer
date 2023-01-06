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