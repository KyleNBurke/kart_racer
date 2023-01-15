package main;

import "core:slice";

NEG_ONE :: [?]f32 {-1, -1, -1};
POS_ONE :: [?]f32 {1, 1, 1};

GREY :: [?]f32 {0.3, 0.3, 0.3};
YELLOW :: [?]f32 {1, 1, 0};

Geometry :: struct {
	indices: [dynamic]u16,
	attributes: [dynamic]f32,
	pipeline: Pipeline,
}

Pipeline :: enum { Line, Basic, Lambert }

init_triangle_geometry :: proc(indices: [dynamic]u16, attributes: [dynamic]f32) -> Geometry {
	when ODIN_DEBUG {
		assert(len(indices) % 3 == 0);
		assert(len(attributes) % 9 == 0);
	}

	return Geometry { indices, attributes, .Lambert };
}

init_box :: proc(color: [3]f32 = GREY) -> Geometry {
	indices := [?]u16 {
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

	attributes := [?]f32 {
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

	indices_dyn := slice.clone_to_dynamic(indices[:]);
	attributes_dyn := slice.clone_to_dynamic(attributes[:]);

	return Geometry { indices_dyn, attributes_dyn, .Lambert };
}

init_box_helper :: proc(min: [3]f32 = NEG_ONE, max: [3]f32 = POS_ONE, color: [3]f32 = YELLOW) -> Geometry {
	indices := [?]u16 {
		0, 1, 0, 2, 3, 1, 3, 2,
		5, 4, 5, 7, 6, 4, 6, 7,
		0, 4, 5, 1, 3, 7, 6, 2,
	};

	min_x, min_y, min_z := min[0], min[1], min[2];
	max_x, max_y, max_z := max[0], max[1], max[2];
	r, g, b := color[0], color[1], color[2];

	attributes := [?]f32 {
		max_x, max_y, max_z, r, g, b,
		max_x, min_y, max_z, r, g, b,
		min_x, max_y, max_z, r, g, b,
		min_x, min_y, max_z, r, g, b,
		max_x, max_y, min_z, r, g, b,
		max_x, min_y, min_z, r, g, b,
		min_x, max_y, min_z, r, g, b,
		min_x, min_y, min_z, r, g, b,
	};

	indices_dyn := slice.clone_to_dynamic(indices[:]);
	attributes_dyn := slice.clone_to_dynamic(attributes[:]);

	return Geometry { indices_dyn, attributes_dyn, .Line };
}

init_line_helper :: proc(origin: [3]f32, vector: [3]f32, color: [3]f32 = YELLOW) -> Geometry {
	indices := [?]u16 {0, 1};

	s := origin;
	e := origin + vector;

	s_x, s_y, s_z := s[0], s[1], s[2];
	e_x, e_y, e_z := e[0], e[1], e[2];
	r, g, b := color[0], color[1], color[2];

	attributes := [?]f32 {
		s_x, s_y, s_z, r, g, b,
		e_x, e_y, e_z, r, g, b,
	};

	indices_dyn := slice.clone_to_dynamic(indices[:]);
	attributes_dyn := slice.clone_to_dynamic(attributes[:]);

	return Geometry { indices_dyn, attributes_dyn, .Line };
}