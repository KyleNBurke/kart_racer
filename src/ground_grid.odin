package main;

import "core:math";
import "core:math/linalg";
import "core:slice";
import "math2";

@(private="file")
CELL_SIZE: f32 : 20.0;

Ground_Grid :: struct {
	half_cell_count: u32,
	positions: [dynamic]f32,
	triangles: [dynamic]Ground_Grid_Triangle,
	query_flags: [dynamic]u32,
	grid: [dynamic][dynamic][dynamic]int,
}

Ground_Grid_Triangle :: struct {
	indices: [6]int,
	bounds: math2.Box3f32,
}

reset_ground_grid :: proc(using ground_grid: ^Ground_Grid, half_size: f32) {
	delete(positions);
	delete(triangles);
	delete(query_flags);

	current_cell_count := half_cell_count * 2;
	for x in 0..<current_cell_count {
		for y in 0..<current_cell_count {
			delete(grid[x][y]);
		}

		delete(grid[x]);
	}

	delete(grid);

	half_cell_count = cast(u32) math.max(math.ceil(half_size / CELL_SIZE), 5.0);
	cell_count := half_cell_count * 2;

	grid = make([dynamic][dynamic][dynamic]int, cell_count);
	for x in 0..<cell_count {
		grid[x] = make([dynamic][dynamic]int, cell_count);

		for y in 0..<cell_count {
			grid[x][y] = make([dynamic]int, 0);
		}
	}

	positions = make([dynamic]f32, 3);

	// Since an index of 0 represents no ghost vertex, we fill the first position slot with something.
	positions[0] = 0.0;
	positions[1] = 0.0;
	positions[2] = 0.0;

	triangles = make([dynamic]Ground_Grid_Triangle, 0);
}

insert_into_ground_grid :: proc(using ground_grid: ^Ground_Grid, new_indices: []u16, new_positions: []f32) {
	current_indices_count := len(positions) / 3;
	append(&positions, ..new_positions);

	// Create a mapping from each triangle's edge to it's opposite vertex
	edge_to_vertex_map := make(map[[2]int]int);

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
		g1_index, ok1 := edge_to_vertex_map[[?]int {a_index, b_index}];
		g2_index, ok2 := edge_to_vertex_map[[?]int {b_index, c_index}];
		g3_index, ok3 := edge_to_vertex_map[[?]int {c_index, a_index}];

		// Calculate triangle bounds
		a_pos_index := a_index * 3;
		b_pos_index := b_index * 3;
		c_pos_index := c_index * 3;

		a := linalg.Vector3f32 {positions[a_pos_index], positions[a_pos_index + 1], positions[a_pos_index + 2]};
		b := linalg.Vector3f32 {positions[b_pos_index], positions[b_pos_index + 1], positions[b_pos_index + 2]};
		c := linalg.Vector3f32 {positions[c_pos_index], positions[c_pos_index + 1], positions[c_pos_index + 2]};

		bounds_min := linalg.min_triple(a, b, c);
		bounds_max := linalg.max_triple(a, b, c);
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

	delete(edge_to_vertex_map);
}

ground_grid_get_triangle :: proc(using ground_grid: ^Ground_Grid, index: int) -> ^Ground_Grid_Triangle {
	return &triangles[index];
}

ground_grid_get_triangle_points :: proc(ground_grid: ^Ground_Grid, triangle: ^Ground_Grid_Triangle) -> (a, b, c: linalg.Vector3f32) {
	indices := &triangle.indices;
	positions := &ground_grid.positions;
	
	a_index := indices[0] * 3;
	b_index := indices[1] * 3;
	c_index := indices[2] * 3;

	a = linalg.Vector3f32 {positions[a_index], positions[a_index + 1], positions[a_index + 2]};
	b = linalg.Vector3f32 {positions[b_index], positions[b_index + 1], positions[b_index + 2]};
	c = linalg.Vector3f32 {positions[c_index], positions[c_index + 1], positions[c_index + 2]};

	return;
}

ground_grid_find_nearby_triangles :: proc(using ground_grid: ^Ground_Grid, bounds: math2.Box3f32) -> [dynamic]int {
	@(static) query_run: u32 = 0;

	if query_run == max(u32) {
		slice.fill(query_flags[:], 0);
		query_run = 0;
	}

	query_run += 1;
	indices := make([dynamic]int, context.temp_allocator);

	grid_min_x, grid_min_y, grid_max_x, grid_max_y, ok := bounds_to_grid_cells(half_cell_count, CELL_SIZE, bounds);
	if !ok do return indices;

	for x in grid_min_x..<grid_max_x {
		for y in grid_min_y..<grid_max_y {
			for index in &grid[x][y] {
				if query_flags[index] != query_run {
					append(&indices, index);
					query_flags[index] = query_run;
				}
			}
		}
	}

	return indices;
}

ground_grid_cleanup :: proc(using ground_grid: ^Ground_Grid) {
	delete(positions);
	delete(triangles);
	delete(query_flags);

	for col in &grid {
		for row in &col {
			delete(row);
		}

		delete(col);
	}

	delete(grid);
}