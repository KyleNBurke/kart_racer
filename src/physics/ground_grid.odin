package physics;

import "core:math";
import "core:math/linalg";
import "core:fmt";

CELL_SIZE: f32 : 20.0;

GroundGrid :: struct {
	half_cell_count: u32,
	positions: [dynamic]f32,
	triangles: [dynamic]Triangle,
	query_flags: [dynamic]u32,
	grid: [dynamic][dynamic][dynamic]int,
}

Triangle :: struct {
	indices: [6]int,
	bounds_min: linalg.Vector3f32,
	bounds_max: linalg.Vector3f32,
}

reset_ground_grid :: proc(using ground_grid: ^GroundGrid, half_size: f32) {
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

	triangles = make([dynamic]Triangle, 0);
}

insert_into_ground_grid :: proc(using ground_grid: ^GroundGrid, new_indices: ^[dynamic]u16, new_positions: ^[dynamic]f32) {
	current_indices_count := len(positions) / 3;
	// append(&positions, ..new_positions^);
	for new_position in new_positions {
		append(&positions, new_position);
	}

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

		// Create triangle
		triangle := Triangle {
			indices = [?]int {a_index, b_index, c_index, g1_index, g2_index, g3_index},
			bounds_min = bounds_min,
			bounds_max = bounds_max,
		};

		append(&triangles, triangle);
		append(&query_flags, 0);

		// Add the triangle index to the cells it spans
		final_triangle_index := len(triangles) - 1;
		grid_min_x, grid_min_y, grid_max_x, grid_max_y, ok := bounds_to_grid_cells(half_cell_count, bounds_min, bounds_max);
		assert(ok);

		for x in grid_min_x..<grid_max_x {
			for y in grid_min_y..<grid_max_y {
				append(&grid[x][y], final_triangle_index);
			}
		}
	}
}

@(private)
bounds_to_grid_cells :: proc(half_cell_count: u32, min, max: linalg.Vector3f32) -> (min_x, min_y, max_x, max_y: u32, ok: bool) {
	half_cell_count_f32 := f32(half_cell_count);
	cell_count := half_cell_count * 2;
	cell_count_f32 := f32(cell_count);

	min_x = cast(u32) math.max(math.floor(min.x / CELL_SIZE + half_cell_count_f32), 0.0);
	min_y = cast(u32) math.max(math.floor(min.z / CELL_SIZE + half_cell_count_f32), 0.0);
	max_x = cast(u32) math.min(math.ceil(max.x / CELL_SIZE + half_cell_count_f32), cell_count_f32);
	max_y = cast(u32) math.min(math.ceil(max.z / CELL_SIZE + half_cell_count_f32), cell_count_f32);

	if max_x == 0 || max_y == 0 || min_x == cell_count || min_y == cell_count {
		ok = false;
	} else {
		ok = true;
	}

	return;
}