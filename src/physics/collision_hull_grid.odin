package physics;

import "core:math";

@(private="file")
CELL_SIZE: f32 : 20.0;

CollisionHullGrid :: struct {
	half_cell_count: u32,
	hull_records: [dynamic]HullRecord,
	query_flags: [dynamic]u32,
	grid: [dynamic][dynamic][dynamic]int,
}

HullRecord :: struct {
	entity_index: int, // some kind of entity identifier
	hull: CollisionHull,
}

reset_collision_hull_grid :: proc(using collision_hull_grid: ^CollisionHullGrid, half_size: f32) {
	delete(hull_records);
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
}

insert_into_collision_hull_grid :: proc(using collision_hull_grid: ^CollisionHullGrid, entity_index: int, hull: CollisionHull) -> int {
	append(&hull_records, HullRecord {entity_index, hull});
	index := len(hull_records) - 1;

	grid_min_x, grid_min_y, grid_max_x, grid_max_y, ok := bounds_to_grid_cells(half_cell_count, CELL_SIZE, hull.global_bounds);
	assert(ok);

	for x in grid_min_x..<grid_max_x {
		for y in grid_min_y..<grid_max_y {
			append(&grid[x][y], index);
		}
	}

	return index;
}