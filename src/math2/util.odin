package math2;

import "core:math";
import "core:math/linalg";
import "core:testing";

align_forward :: proc(unaligned_offset: int, alignment: int) -> int {
	under := (alignment - unaligned_offset % alignment) % alignment;
	return unaligned_offset + under;
}

align_backward :: proc(unaligned_offset: int, alignment: int) -> int {
	over := unaligned_offset % alignment;
	return unaligned_offset - over;
}

vector2_rotate :: proc(v: linalg.Vector2f32, angle: f32) -> linalg.Vector2f32 {
	return linalg.Vector2f32 {
		v.x * math.cos(angle) - v.y * math.sin(angle),
		v.x * math.sin(angle) + v.y * math.cos(angle),
	};
}

vector3_rotate :: proc(v, axis: linalg.Vector3f32, angle: f32) -> linalg.Vector3f32 {
	a_sin := math.sin(angle / 2);
	a_cos := math.cos(angle / 2);
	b := linalg.Vector3f32 {a_sin * axis.x, a_sin * axis.y, a_sin * axis.z};

	return b * 2 * linalg.dot(b, v) + v * (a_cos * a_cos - linalg.dot(b, b)) + linalg.cross(b, v) * 2 * a_cos;
}

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

// https://gamedev.stackexchange.com/a/50545/122527
quaternion_transform_direction :: proc(q: linalg.Quaternionf32, d: linalg.Vector3f32) -> linalg.Vector3f32 {
	u := linalg.Vector3f32 {q.x, q.y, q.z};
	s := q.w;

	return u * linalg.dot(u, d) * 2.0 + d * (s * s - linalg.dot(u, u)) + linalg.cross(u, d) * s * 2.0;
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

matrix4_left :: proc(m: linalg.Matrix4f32) -> linalg.Vector3f32 {
	return linalg.Vector3f32 {m[0][0], m[0][1], m[0][2]};
}

matrix4_up :: proc(m: linalg.Matrix4f32) -> linalg.Vector3f32 {
	return linalg.Vector3f32 {m[1][0], m[1][1], m[1][2]};
}

matrix4_forward :: proc(m: linalg.Matrix4f32) -> linalg.Vector3f32 {
	return linalg.Vector3f32 {m[2][0], m[2][1], m[2][2]};
}

/*
https://stackoverflow.com/a/36209005/3600203

h: [0, 360)
s: [0, 1]
v: [0, 1]

r, g, b: [0, 1]
*/
hsv_to_rgb :: proc(h, s, v: f32) -> (r, g, b: f32) {
	if ODIN_DEBUG {
		assert(h >= 0 && b < 360);
		assert(s >= 0 && s <= 1);
		assert(v >= 0 && v <= 1);
	}

	h := h / 60;
	f := h - math.floor(h);
	p := v * (1 - s);
	q := v * (1 - s * f);
	t := v * (1 - s * (1 - f));

	switch u32(h) {
	case 0:
		return v, t, p;
	case 1:
		return q, v, p;
	case 2:
		return p, v, t;
	case 3:
		return p, q, v;
	case 4:
		return t, p, v;
	case 5:
		return v, p, q;
	case:
		unreachable();
	}
}

triangle_index_to_points :: proc(triangle_index: int, indices: []u16, positions: []f32) -> (a, b, c: linalg.Vector3f32) {
	a_index := indices[triangle_index * 3 + 0] * 3;
	b_index := indices[triangle_index * 3 + 1] * 3;
	c_index := indices[triangle_index * 3 + 2] * 3;

	a = linalg.Vector3f32 {positions[a_index], positions[a_index + 1], positions[a_index + 2]};
	b = linalg.Vector3f32 {positions[b_index], positions[b_index + 1], positions[b_index + 2]};
	c = linalg.Vector3f32 {positions[c_index], positions[c_index + 1], positions[c_index + 2]};

	return a, b, c;
}

Ray_Triangle_Intersection :: struct {
	normal: linalg.Vector3f32,
	length: f32,
}

ray_intersects_triangle :: proc(origin, direction: linalg.Vector3f32, length: f32, a, b, c: linalg.Vector3f32) -> Maybe(Ray_Triangle_Intersection) {
	ab := b - a;
	ac := c - a;

	p := linalg.cross(direction, ac);
	det := linalg.dot(p, ab);

	if det < 0 {
		return nil;
	}
	
	t := origin - a;
	u := linalg.dot(p, t);

	if u < 0 || u > det {
		return nil;
	}

	q := linalg.cross(t, ab);
	v := linalg.dot(q, direction);

	if v < 0 || u + v > det {
		return nil;
	}

	dist := (1 / det) * linalg.dot(q, ac);

	if dist <= 0 || dist > length {
		return nil;
	}

	n := linalg.normalize(linalg.cross(ab, ac));
	return Ray_Triangle_Intersection { n, dist };
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

