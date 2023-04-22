package main;

import "core:math";
import "core:slice";
import "math2";

@(private="file")
CELL_SIZE: f32 : 20;

Entity_Grid :: struct {
	half_cell_count: u32,
	cells: [dynamic][dynamic][dynamic]Entity_Lookup,
	query_runs: [dynamic]u32,
}

init_entity_grid :: proc(grid: ^Entity_Grid, half_size: f32) {
	grid.half_cell_count = cast(u32) math.max(math.ceil(half_size / CELL_SIZE), 5.0);
	cell_count := grid.half_cell_count * 2;
	grid.cells = make([dynamic][dynamic][dynamic]Entity_Lookup, cell_count);

	for x in 0..<cell_count {
		grid.cells[x] = make([dynamic][dynamic]Entity_Lookup, cell_count);

		for y in 0..<cell_count {
			grid.cells[x][y] = make([dynamic]Entity_Lookup, 0);
		}
	}
}

insert_entity_into_grid :: proc(grid: ^Entity_Grid, entity: ^Entity) {
	grid_min_x, grid_min_y, grid_max_x, grid_max_y, ok := bounds_to_grid_cells(grid.half_cell_count, CELL_SIZE, entity.bounds);
	assert(ok);

	for x in grid_min_x..<grid_max_x {
		for y in grid_min_y..<grid_max_y {
			append(&grid.cells[x][y], entity.lookup);
		}
	}
}

remove_entity_from_grid :: proc(grid: ^Entity_Grid, entity: ^Entity) {
	grid_min_x, grid_min_y, grid_max_x, grid_max_y, ok := bounds_to_grid_cells(grid.half_cell_count, CELL_SIZE, entity.bounds);
	if !ok do return;

	for x in grid_min_x..<grid_max_x {
		for y in grid_min_y..<grid_max_y {
			i, ok := slice.linear_search(grid.cells[x][y][:], entity.lookup);
			assert(ok);
			unordered_remove(&grid.cells[x][y], i);
		}
	}
}

move_rigid_body_tentatively_in_grid :: proc(grid: ^Entity_Grid, rigid_body: ^Rigid_Body_Entity) {
	// Remove the lookup from the old cells which this entity spans
	grid_min_x, grid_min_y, grid_max_x, grid_max_y, ok := bounds_to_grid_cells(grid.half_cell_count, CELL_SIZE, rigid_body.bounds);
	if !ok do return;

	for x in grid_min_x..<grid_max_x {
		for y in grid_min_y..<grid_max_y {
			cell := &grid.cells[x][y];

			i, ok := slice.linear_search(cell[:], rigid_body.lookup);
			assert(ok);
			unordered_remove(cell, i);
		}
	}

	// Update the global transform matrix and the global bounds
	update_entity_hull_transforms_and_bounds(rigid_body, rigid_body.tentative_transform);

	// Add the lookup to the new cells which this hull spans
	grid_min_x, grid_min_y, grid_max_x, grid_max_y, ok = bounds_to_grid_cells(grid.half_cell_count, CELL_SIZE, rigid_body.bounds);
	if !ok do return;

	for x in grid_min_x..<grid_max_x {
		for y in grid_min_y..<grid_max_y {
			append(&grid.cells[x][y], rigid_body.lookup);
		}
	}
}

find_nearby_entities_in_grid :: proc(grid: ^Entity_Grid, bounds: math2.Box3f32) -> [dynamic]Entity_Lookup {
	@(static) query_run: u32 = 0;

	if query_run == max(u32) {
		unimplemented();
	}

	query_run += 1;
	lookups := make([dynamic]Entity_Lookup, context.temp_allocator);

	grid_min_x, grid_min_y, grid_max_x, grid_max_y, ok := bounds_to_grid_cells(grid.half_cell_count, CELL_SIZE, bounds);
	if !ok do return lookups;

	for x in grid_min_x..<grid_max_x {
		for y in grid_min_y..<grid_max_y {
			for lookup in &grid.cells[x][y] {
				entity := get_entity(lookup);

				if entity.query_run != query_run {
					append(&lookups, lookup);
					entity.query_run = query_run;
				}
			}
		}
	}

	return lookups;
}

cleanup_entity_grid :: proc(grid: ^Entity_Grid) {
	for col in &grid.cells {
		for row in &col {
			delete(row);
		}

		delete(col);
	}

	delete(grid.cells);
}