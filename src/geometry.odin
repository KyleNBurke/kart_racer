package main;

import "core:slice";
import "core:math";
import "core:math/linalg";

NEG_ONE :: linalg.Vector3f32 {-1, -1, -1};
POS_ONE :: linalg.Vector3f32 {1, 1, 1};

GREEN :: [3]f32 {0, 1, 0};
BLUE  :: [3]f32 {0, 0, 1};
GREY :: [3]f32 {0.3, 0.3, 0.3};
YELLOW :: [3]f32 {1, 1, 0};

Geometry :: struct {
	name: string,
	indices: [dynamic]u16,
	attributes: [dynamic]f32,
	pipeline: Pipeline,
}

Pipeline :: enum { Line, Basic, Lambert }

init_triangle_geometry :: proc(name: string, indices: [dynamic]u16, attributes: [dynamic]f32) -> Geometry {
	when ODIN_DEBUG {
		assert(len(indices) % 3 == 0);
		assert(len(attributes) % 9 == 0);
	}

	return Geometry { name, indices, attributes, .Lambert };
}

init_box :: proc(name: string, color: [3]f32 = GREY) -> Geometry {
	indices := [dynamic]u16 {
		0,  3,  2,  // top
		0,  2,  1,
		4,  6,  7,  // bottom
		4,  5,  6,
		8,  9,  10, // right
		8,  10, 11,
		12, 15, 13, // left
		13, 15, 14,
		16, 17, 18, // front
		16, 18, 19,
		20, 23, 22, // back
		20, 22, 21,
	};

	r, g, b := color[0], color[1], color[2];

	attributes := [dynamic]f32 {
		1.0,  1.0,  1.0,  0.0,  1.0,  0.0, r, g, b, // top
	   -1.0,  1.0,  1.0,  0.0,  1.0,  0.0, r, g, b,
	   -1.0,  1.0, -1.0,  0.0,  1.0,  0.0, r, g, b,
		1.0,  1.0, -1.0,  0.0,  1.0,  0.0, r, g, b,
		1.0, -1.0,  1.0,  0.0, -1.0,  0.0, r, g, b, // bottom
	   -1.0, -1.0,  1.0,  0.0, -1.0,  0.0, r, g, b,
	   -1.0, -1.0, -1.0,  0.0, -1.0,  0.0, r, g, b,
		1.0, -1.0, -1.0,  0.0, -1.0,  0.0, r, g, b,
	   -1.0,  1.0,  1.0, -1.0,  0.0,  0.0, r, g, b, // right
	   -1.0,  1.0, -1.0, -1.0,  0.0,  0.0, r, g, b,
	   -1.0, -1.0, -1.0, -1.0,  0.0,  0.0, r, g, b,
	   -1.0, -1.0,  1.0, -1.0,  0.0,  0.0, r, g, b,
		1.0,  1.0,  1.0,  1.0,  0.0,  0.0, r, g, b, // left
		1.0,  1.0, -1.0,  1.0,  0.0,  0.0, r, g, b,
		1.0, -1.0, -1.0,  1.0,  0.0,  0.0, r, g, b,
		1.0, -1.0,  1.0,  1.0,  0.0,  0.0, r, g, b,
		1.0,  1.0,  1.0,  0.0,  0.0,  1.0, r, g, b, // front
	   -1.0,  1.0,  1.0,  0.0,  0.0,  1.0, r, g, b,
	   -1.0, -1.0,  1.0,  0.0,  0.0,  1.0, r, g, b,
		1.0, -1.0,  1.0,  0.0,  0.0,  1.0, r, g, b,
		1.0,  1.0, -1.0,  0.0,  0.0, -1.0, r, g, b, // back
	   -1.0,  1.0, -1.0,  0.0,  0.0, -1.0, r, g, b,
	   -1.0, -1.0, -1.0,  0.0,  0.0, -1.0, r, g, b,
		1.0, -1.0, -1.0,  0.0,  0.0, -1.0, r, g, b,
   };

	return Geometry { name, indices, attributes, .Lambert };
}

init_line_helper :: proc(name: string, origin, vector: linalg.Vector3f32, color: [3]f32 = YELLOW) -> Geometry {
	geo := Geometry { name = name };
	set_line_helper(&geo, origin, vector, color);
	return geo;
}

set_line_helper :: proc(using geometry: ^Geometry, origin, vector: linalg.Vector3f32, color: [3]f32 = YELLOW) {
	clear(&indices);
	clear(&attributes);

	append(&indices, 0, 1);

	s := origin;
	e := origin + vector;

	s_x, s_y, s_z := s[0], s[1], s[2];
	e_x, e_y, e_z := e[0], e[1], e[2];
	r, g, b := color[0], color[1], color[2];

	append(&attributes,
		s_x, s_y, s_z, r, g, b,
		e_x, e_y, e_z, r, g, b,
	);

	pipeline = .Line;
}

init_box_helper :: proc(name: string, min: linalg.Vector3f32 = NEG_ONE, max: linalg.Vector3f32 = POS_ONE, color: [3]f32 = YELLOW) -> Geometry {
	indices := [dynamic]u16 {
		0, 1, 0, 2, 3, 1, 3, 2,
		5, 4, 5, 7, 6, 4, 6, 7,
		0, 4, 5, 1, 3, 7, 6, 2,
	};

	min_x, min_y, min_z := min[0], min[1], min[2];
	max_x, max_y, max_z := max[0], max[1], max[2];
	r, g, b := color[0], color[1], color[2];

	attributes := [dynamic]f32 {
		max_x, max_y, max_z, r, g, b,
		max_x, min_y, max_z, r, g, b,
		min_x, max_y, max_z, r, g, b,
		min_x, min_y, max_z, r, g, b,
		max_x, max_y, min_z, r, g, b,
		max_x, min_y, min_z, r, g, b,
		min_x, max_y, min_z, r, g, b,
		min_x, min_y, min_z, r, g, b,
	};

	return Geometry { name, indices, attributes, .Line };
}

init_cylinder_helper :: proc(name: string, color: [3]f32 = YELLOW) -> Geometry {
	geo := Geometry { name = name, pipeline = .Line };
	r, g, b := color[0], color[1], color[2];

	POINT_COUNT :: 8
	ANGLE_INCREMENT :: math.TAU / f32(POINT_COUNT);

	for i in 0..<POINT_COUNT {
		angle := f32(i) * ANGLE_INCREMENT;
		x := math.cos(angle);
		z := math.sin(angle);

		append(&geo.attributes, x,  1, z, r, g, b);
		append(&geo.attributes, x, -1, z, r, g, b);

		k := u16(i) * 2;
		append(&geo.indices,
			k, k + 1,
			k, (k + 2) % (POINT_COUNT * 2),
			k + 1, (k + 3) % (POINT_COUNT * 2),
		);
	}

	return geo;
}