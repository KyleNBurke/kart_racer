package main;

import "core:math";
import "core:math/linalg";
import "core:slice";
import "math2";

@(private="file")
CELL_SIZE: f32 : 20.0;

Ground_Grid :: struct {
	half_cell_count: int,
	positions: [dynamic]f32,
	triangles: [dynamic]Ground_Grid_Triangle,
	query_flags: [dynamic]u32,
	grid: [dynamic][dynamic][dynamic]int,
}

Ground_Grid_Triangle :: struct {
	indices: [6]int,
	bounds: math2.Box3f32,
}

Ground_Grid_Evaluated_Triangle :: struct {
	a, b, c, g1, g2, g3: linalg.Vector3f32,
	bounds: math2.Box3f32,
	normal: linalg.Vector3f32,
}

ground_grid_init :: proc(using ground_grid: ^Ground_Grid) {
	// Since an index of 0 represents no ghost vertex, we fill the first position slot with something.
	append(&positions, 0, 0, 0);
}

ground_grid_reset :: proc(using ground_grid: ^Ground_Grid, half_size: f32) {
	half_cell_count = cast(int) max(math.ceil(half_size / CELL_SIZE), 5.0);
	resize(&positions, 3); // Resize to the initial 3 values
	clear(&triangles);
	clear(&query_flags);

	// Once we resize the grid, it can kill the internal memory so we must destroy it explicitly to not cause a memory leak.
	for &col in grid {
		for &cell in col {
			delete(cell);
		}

		delete(col);
	}

	delete(grid);

	cell_count := half_cell_count * 2;

	grid = make([dynamic][dynamic][dynamic]int, cell_count);

	for &col in grid {
		col = make([dynamic][dynamic]int, cell_count);
	}
}

insert_into_ground_grid :: proc(using ground_grid: ^Ground_Grid, new_indices: []u16, new_positions: []f32) {
	current_indices_count := len(positions) / 3;
	append(&positions, ..new_positions);

	// Create a mapping from each triangle's edge to it's opposite vertex
	edge_to_vertex_map := make(map[[2]int]int, allocator = context.temp_allocator);

	for triangle_index in 0..< len(new_indices) / 3 {
		a_index := cast(int) new_indices[triangle_index * 3];
		b_index := cast(int) new_indices[triangle_index * 3 + 1];
		c_index := cast(int) new_indices[triangle_index * 3 + 2];

		// Reverse the edge to maintain the winding order of the triangle with this ghost vertex
		edge_to_vertex_map[[?]int {b_index, a_index}] = c_index;
		edge_to_vertex_map[[?]int {c_index, b_index}] = a_index;
		edge_to_vertex_map[[?]int {a_index, c_index}] = b_index;
	}

	// Create triangles and insert them
	for triangle_index in 0..< len(new_indices) / 3 {
		a_index := cast(int) new_indices[triangle_index * 3] + current_indices_count;
		b_index := cast(int) new_indices[triangle_index * 3 + 1] + current_indices_count;
		c_index := cast(int) new_indices[triangle_index * 3 + 2] + current_indices_count;

		// Find ghost vertices
		g1_index, _ := edge_to_vertex_map[[?]int {a_index, b_index}];
		g2_index, _ := edge_to_vertex_map[[?]int {b_index, c_index}];
		g3_index, _ := edge_to_vertex_map[[?]int {c_index, a_index}];

		// Calculate triangle bounds
		a_pos_index := a_index * 3;
		b_pos_index := b_index * 3;
		c_pos_index := c_index * 3;

		a := linalg.Vector3f32 {positions[a_pos_index], positions[a_pos_index + 1], positions[a_pos_index + 2]};
		b := linalg.Vector3f32 {positions[b_pos_index], positions[b_pos_index + 1], positions[b_pos_index + 2]};
		c := linalg.Vector3f32 {positions[c_pos_index], positions[c_pos_index + 1], positions[c_pos_index + 2]};

		bounds_min := linalg.min(a, b, c);
		bounds_max := linalg.max(a, b, c);
		bounds := math2.Box3f32 {bounds_min, bounds_max};

		// Create triangle
		triangle := Ground_Grid_Triangle {
			[?]int {a_index, b_index, c_index, g1_index, g2_index, g3_index},
			bounds,
		};

		append(&triangles, triangle);
		append(&query_flags, 0);

		// Add the triangle index to the cells it spans
		final_triangle_index := len(triangles) - 1;
		grid_min_x, grid_min_y, grid_max_x, grid_max_y, ok := bounds_to_grid_cells(half_cell_count, CELL_SIZE, bounds);
		assert(ok);

		for x in grid_min_x..<grid_max_x {
			for y in grid_min_y..<grid_max_y {
				append(&grid[x][y], final_triangle_index);
			}
		}
	}
}

ground_grid_find_nearby_triangles :: proc(ground_grid: ^Ground_Grid, bounds: math2.Box3f32) -> [dynamic]int {
	@(static) query_run: u32 = 0;

	if query_run == max(u32) {
		slice.fill(ground_grid.query_flags[:], 0);
		query_run = 0;
	}

	query_run += 1;
	triangle_indices := make([dynamic]int, context.temp_allocator);

	grid_min_x, grid_min_y, grid_max_x, grid_max_y, ok := bounds_to_grid_cells(ground_grid.half_cell_count, CELL_SIZE, bounds);
	if !ok do return triangle_indices;

	for x in grid_min_x..<grid_max_x {
		for y in grid_min_y..<grid_max_y {
			for index in &ground_grid.grid[x][y] {
				if ground_grid.query_flags[index] == query_run {
					continue;
				}

				append(&triangle_indices, index);
				ground_grid.query_flags[index] = query_run;
			}
		}
	}

	return triangle_indices;
}

ground_grid_form_triangle :: proc(ground_grid: ^Ground_Grid, triangle_index: int) -> Ground_Grid_Evaluated_Triangle {
	positions := &ground_grid.positions;

	triangle := &ground_grid.triangles[triangle_index];
	indices := &triangle.indices;

	a_index  := indices[0] * 3;
	b_index  := indices[1] * 3;
	c_index  := indices[2] * 3;
	g1_index := indices[3] * 3;
	g2_index := indices[4] * 3;
	g3_index := indices[5] * 3;

	a  := linalg.Vector3f32 {positions[a_index],  positions[a_index + 1],  positions[a_index + 2]};
	b  := linalg.Vector3f32 {positions[b_index],  positions[b_index + 1],  positions[b_index + 2]};
	c  := linalg.Vector3f32 {positions[c_index],  positions[c_index + 1],  positions[c_index + 2]};
	g1 := linalg.Vector3f32 {positions[g1_index], positions[g1_index + 1], positions[g1_index + 2]};
	g2 := linalg.Vector3f32 {positions[g2_index], positions[g2_index + 1], positions[g2_index + 2]};
	g3 := linalg.Vector3f32 {positions[g3_index], positions[g3_index + 1], positions[g3_index + 2]};

	ab := b - a;
	ac := c - a;
	normal := linalg.normalize(linalg.cross(ab, ac));

	evaluated_triangle := Ground_Grid_Evaluated_Triangle {
		a, b, c, g1, g2, g3,
		triangle.bounds,
		normal,
	};

	return evaluated_triangle;
}

ground_grid_cleanup :: proc(using ground_grid: ^Ground_Grid) {
	delete(positions);
	delete(triangles);
	delete(query_flags);

	for &col in grid {
		for &row in col {
			delete(row);
		}

		delete(col);
	}

	delete(grid);
}