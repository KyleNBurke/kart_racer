package math2;

import "core:math/linalg";
import "core:testing";

vector3_tangents :: proc(v: linalg.Vector3f32) -> (t1, t2: linalg.Vector3f32) {
	if abs(v.x) >= 0.57735027 {
		t1 = linalg.normalize(linalg.Vector3f32 {v.y, -v.x, 0});
	} else {
		t1 = linalg.normalize(linalg.Vector3f32 {0, v.z, -v.y});
	}
	
	t2 = linalg.cross(v, t1);

	return;
}

quaternion_mul_f32 :: proc(q: linalg.Quaternionf32, f: f32) -> linalg.Quaternionf32 {
	return quaternion(q.w * f, q.x * f, q.y * f, q.z * f);
}

matrix3_transform_direction :: proc(m: linalg.Matrix3f32, p: linalg.Vector3f32) -> linalg.Vector3f32 {
	return linalg.Vector3f32 {
		m[0][0] * p.x + m[1][0] * p.y + m[2][0] * p.z,
		m[0][1] * p.x + m[1][1] * p.y + m[2][1] * p.z,
		m[0][2] * p.x + m[1][2] * p.y + m[2][2] * p.z,
	};
}

matrix4_transform_point :: proc(m: linalg.Matrix4f32, p: linalg.Vector3f32) -> linalg.Vector3f32 {
	return linalg.Vector3f32 {
		m[0][0] * p.x + m[1][0] * p.y + m[2][0] * p.z + m[3][0],
		m[0][1] * p.x + m[1][1] * p.y + m[2][1] * p.z + m[3][1],
		m[0][2] * p.x + m[1][2] * p.y + m[2][2] * p.z + m[3][2],
	};
}

matrix4_transform_direction :: proc(m: linalg.Matrix4f32, d: linalg.Vector3f32) -> linalg.Vector3f32 {
	return linalg.Vector3f32 {
		m[0][0] * d.x + m[1][0] * d.y + m[2][0] * d.z,
		m[0][1] * d.x + m[1][1] * d.y + m[2][1] * d.z,
		m[0][2] * d.x + m[1][2] * d.y + m[2][2] * d.z,
	};
}

integrate_angular_velocity :: proc(vel: linalg.Vector3f32, ori: linalg.Quaternionf32, dt: f32) -> linalg.Quaternionf32 {
	w := cast(linalg.Quaternionf32) quaternion(0, vel.x, vel.y, vel.z)
	return linalg.normalize(ori + quaternion_mul_f32(w * ori, 0.5 * dt));
}

calculate_inv_global_inertia_tensor :: proc(orientation: linalg.Quaternionf32, inv_local_inertia_tensor: linalg.Matrix3f32) -> linalg.Matrix3f32 {
	m := linalg.matrix3_from_quaternion(orientation);
	return m * inv_local_inertia_tensor * linalg.transpose(m);
}

matrix4_down :: proc(m: linalg.Matrix4f32) -> linalg.Vector3f32 {
	return linalg.Vector3f32 {-m[0][1], -m[1][1], -m[2][1]};
}

@(test, private)
test_matrix3_transform_direction :: proc(t: ^testing.T) {
	m := linalg.Matrix3f32 {
		4.0, 2.0, 8.0,
		7.0, 1.0, 9.0,
		0.0, 2.0, 6.0,
	};
	
	d := linalg.Vector3f32 {1.0, 1.0, 1.0};
	testing.expect_value(t, matrix3_transform_direction(m, d), linalg.Vector3f32 {14.0, 17.0, 8.0});
}

@(test, private)
test_matrix4_transform_point :: proc(t: ^testing.T) {
	m := linalg.Matrix4f32 {
		4.0, 2.0, 8.0, 5.0,
		7.0, 1.0, 9.0, 4.0,
		0.0, 2.0, 6.0, 3.0,
		7.0, 8.0, 5.0, 3.0,
	};
	
	p := linalg.Vector3f32 {1.0, 1.0, 1.0};
	testing.expect_value(t, matrix4_transform_point(m, p), linalg.Vector3f32 {19.0, 21.0, 11.0});
}

@(test, private)
test_matrix4_transform_direction :: proc(t: ^testing.T) {
	m := linalg.Matrix4f32 {
		4.0, 2.0, 8.0, 5.0,
		7.0, 1.0, 9.0, 4.0,
		0.0, 2.0, 6.0, 3.0,
		7.0, 8.0, 5.0, 3.0,
	};
	
	p := linalg.Vector3f32 {1.0, 1.0, 1.0};
	testing.expect_value(t, matrix4_transform_direction(m, p), linalg.Vector3f32 {14.0, 17.0, 8.0});
}

