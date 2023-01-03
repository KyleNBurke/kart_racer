package physics;

import "core:math";
import "core:math/linalg";
import "core:fmt";
import "../math2";

@(private="file")
CELL_SIZE: f32 : 20.0;

GroundGrid :: struct {
	half_cell_count: u32,
	positions: [dynamic]f32,
	triangles: [dynamic]GroundGridTriangle,
	query_flags: [dynamic]u32,
	grid: [dynamic][dynamic][dynamic]int,
}

GroundGridTriangle :: struct {
	indices: [6]int,
	bounds: math2.Box3f32,
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

	triangles = make([dynamic]GroundGridTriangle, 0);
}

insert_into_ground_grid :: proc(using ground_grid: ^GroundGrid, new_indices: ^[dynamic]u16, new_positions: ^[dynamic]f32) {
	current_indices_count := len(positions) / 3;
	// append(&positions, ..new_positions^);
	for new_position in new_positions {
		append(&positions, new_position); // Try the _elms version?
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
		bounds := math2.Box3f32 {bounds_min, bounds_max};

		// Create triangle
		triangle := GroundGridTriangle {
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