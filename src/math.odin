package main;

import "core:math/linalg";

// https://gamedev.stackexchange.com/a/50545/122527
quaternion_transform_direction :: proc(q: linalg.Quaternionf32, d: linalg.Vector3f32) -> linalg.Vector3f32 {
	u := linalg.Vector3f32 {q.x, q.y, q.z};
	s := q.w;

	return u * linalg.dot(u, d) * 2.0 + d * (s * s - linalg.dot(u, u)) + linalg.cross(u, d) * s * 2.0;
}