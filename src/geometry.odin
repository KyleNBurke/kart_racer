package main;

import "core:math";
import "core:math/linalg";
import "core:strings";

RED    :: [3]f32 {1, 0, 0};
GREEN  :: [3]f32 {0, 1, 0};
BLUE   :: [3]f32 {0, 0, 1};
YELLOW :: [3]f32 {1, 1, 0};
CYAN   :: [3]f32 {0, 1, 1};
GREY   :: [3]f32 {0.3, 0.3, 0.3};

Geometry :: struct {
	name: string,
	free: bool,
	generation: u32,
	entity_lookups: [dynamic]Entity_Lookup,
	on_no_entities: On_No_Entities,
	indices: [dynamic]u16,
	attributes: [dynamic]f32,
	pipeline: Pipeline,
}

On_No_Entities :: enum {
	Keep,       // Will not free the geometry
	KeepRender, // Will not free the geometry and will render it with an identity matrix
	Free,       // Free the geometry
}

Pipeline :: enum { Line, Basic, Lambert, LambertTwoSided }

geometry_make_triangle_mesh :: proc(geo: ^Geometry, indices: []u16, attributes: []f32, pipeline: Pipeline) {
	assert(len(indices) % 3 == 0);
	assert(len(attributes) % 9 == 0);
	assert(pipeline != .Line);

	clear(&geo.indices);
	clear(&geo.attributes);

	append(&geo.indices, ..indices);
	append(&geo.attributes, ..attributes);
	
	geo.pipeline = pipeline;
}

geometry_make_box :: proc(geo: ^Geometry, color: [3]f32 = GREY, pipeline: Pipeline) {
	assert(pipeline != .Line);

	clear(&geo.indices);
	clear(&geo.attributes);
	geo.pipeline = pipeline;

	append(&geo.indices,
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
	);

	r, g, b := color[0], color[1], color[2];

	append(&geo.attributes,
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
	);
}

geometry_make_line_helper_origin_vector :: proc(geo: ^Geometry, origin, vector: linalg.Vector3f32, color: [3]f32 = YELLOW) {
	s := origin;
	e := origin + vector;

	geometry_make_line_helper_start_end(geo, s, e, color);
}

geometry_make_line_helper_start_end :: proc(geo: ^Geometry, start, end: linalg.Vector3f32, color: [3]f32 = YELLOW) {
	clear(&geo.indices);
	clear(&geo.attributes);
	geo.pipeline = .Line;

	append(&geo.indices, 0, 1);

	s_x, s_y, s_z := start[0], start[1], start[2];
	e_x, e_y, e_z := end[0], end[1], end[2];
	r, g, b := color[0], color[1], color[2];

	append(&geo.attributes,
		s_x, s_y, s_z, r, g, b,
		e_x, e_y, e_z, r, g, b,
	);
}

geometry_make_line_helper_points_strip :: proc(geo: ^Geometry, points: []f32, color := YELLOW) {
	clear(&geo.indices);
	clear(&geo.attributes);
	geo.pipeline = .Line;

	r, g, b := color[0], color[1], color[2];

	for i in 0..<(len(points) / 3) {
		s := u16(i);
		e := u16(i) + 1;

		if i != len(points) / 3 - 1 {
			append(&geo.indices, s, e);
		}

		x := points[i * 3];
		y := points[i * 3 + 1];
		z := points[i * 3 + 2];

		append(&geo.attributes, x, y, z, r, g, b);
	}
}

geometry_make_box_helper :: proc(geo: ^Geometry, min, max: linalg.Vector3f32, color: [3]f32 = YELLOW) {
	clear(&geo.indices);
	clear(&geo.attributes);
	geo.pipeline = .Line;

	append(&geo.indices,
		0, 1, 0, 2, 3, 1, 3, 2,
		5, 4, 5, 7, 6, 4, 6, 7,
		0, 4, 5, 1, 3, 7, 6, 2,
	);

	min_x, min_y, min_z := min[0], min[1], min[2];
	max_x, max_y, max_z := max[0], max[1], max[2];
	r, g, b := color[0], color[1], color[2];

	append(&geo.attributes,
		max_x, max_y, max_z, r, g, b,
		max_x, min_y, max_z, r, g, b,
		min_x, max_y, max_z, r, g, b,
		min_x, min_y, max_z, r, g, b,
		max_x, max_y, min_z, r, g, b,
		max_x, min_y, min_z, r, g, b,
		min_x, max_y, min_z, r, g, b,
		min_x, min_y, min_z, r, g, b,
	);
}

geometry_make_cylinder_helper :: proc(geo: ^Geometry, color: [3]f32 = YELLOW) {
	clear(&geo.indices);
	clear(&geo.attributes);
	geo.pipeline = .Line;

	r, g, b := color[0], color[1], color[2];

	POINT_COUNT :: 8
	ANGLE_INCREMENT :: math.TAU / f32(POINT_COUNT);

	for i in 0..<POINT_COUNT {
		angle := f32(i) * ANGLE_INCREMENT;
		x := math.cos(angle);
		z := math.sin(angle);

		append(&geo.attributes,
			x,  1, z, r, g, b,
			x, -1, z, r, g, b);

		k := u16(i) * 2;
		append(&geo.indices,
			k, k + 1,
			k, (k + 2) % (POINT_COUNT * 2),
			k + 1, (k + 3) % (POINT_COUNT * 2),
		);
	}
}

geometry_make_sphere_helper :: proc(geo: ^Geometry, center: linalg.Vector3f32, radius: f32, color: [3]f32 = YELLOW) {
	clear(&geo.indices);
	clear(&geo.attributes);
	geo.pipeline = .Line;

	r, g, b := color[0], color[1], color[2];

	POINT_COUNT :: 8;
	POINT_COUNT_THETA :: POINT_COUNT / 2;
	ANGLE_INCREMENT_THETA :: math.TAU / f32(POINT_COUNT);
	ANGLE_INCREMENT_PHI :: math.PI / f32(POINT_COUNT / 2);

	bottom_x := center.x;
	bottom_y := center.y - radius;
	bottom_z := center.z;
	append(&geo.attributes, bottom_x, bottom_y, bottom_z, r, g, b); // Bottom point

	for x in 0..<POINT_COUNT {
		for y in 0..<POINT_COUNT_THETA {
			theta := f32(x) * ANGLE_INCREMENT_THETA;
			phi   := f32(y + 1) * ANGLE_INCREMENT_PHI - math.PI;

			pos_x := center.x + radius * math.sin(phi) * math.cos(theta);
			pos_y := center.y + radius * math.cos(phi);
			pos_z := center.z + radius * math.sin(phi) * math.sin(theta);

			append(&geo.attributes, pos_x, pos_y, pos_z, r, g, b);

			s: u16;
			e: u16 = 1 + u16(x) * POINT_COUNT_THETA + u16(y);

			if y == 0 {
				s = 0;
			} else {
				s = e - 1;
			}

			append(&geo.indices, s, e);

			if y != 0 {
				e = 1 + u16(x + 1) % POINT_COUNT * POINT_COUNT_THETA + u16(y - 1);
				append(&geo.indices, s, e);
			}
		}
	}

	top_x := center.x;
	top_y := center.y + radius;
	top_z := center.z;
	append(&geo.attributes, top_x, top_y, top_z, r, g, b); // Top point
}

geometry_set_color :: proc(geo: ^Geometry, color: [3]f32) {
	if geo.pipeline == .Line {
		unimplemented();
	}

	for vert_index in 0..<(len(geo.attributes) / 9) {
		geo.attributes[vert_index * 9 + 6] = color[0];
		geo.attributes[vert_index * 9 + 7] = color[1];
		geo.attributes[vert_index * 9 + 8] = color[2];
	}
}