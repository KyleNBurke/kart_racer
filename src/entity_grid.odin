package main;

import "core:math";
import "core:slice";
import "core:math/linalg";
import "math2";

@(private="file")
CELL_SIZE: f32 : 20;

Entity_Grid :: struct {
	half_cell_count: int,
	cells: [dynamic][dynamic][dynamic]Entity_Lookup,
}

entity_grid_reset :: proc(using grid: ^Entity_Grid, half_size: f32) {
	half_cell_count = cast(int) max(math.ceil(half_size / CELL_SIZE), 5.0);

	// Once we resize the grid, it can kill in internal memory so we must destroy it explicitly to not cause a memory leak.
	for &col in cells {
		for &cell in col {
			delete(cell);
		}

		delete(col);
	}

	cell_count := half_cell_count * 2;

	resize(&cells, cell_count);

	for &col in cells {
		col = make([dynamic][dynamic]Entity_Lookup, cell_count);
	}
}

entity_grid_insert :: proc(grid: ^Entity_Grid, entity_lookup: Entity_Lookup, entity: ^Entity) {
	grid_min_x, grid_min_y, grid_max_x, grid_max_y, ok := bounds_to_grid_cells(grid.half_cell_count, CELL_SIZE, entity.bounds);
	assert(ok);

	for x in grid_min_x..<grid_max_x {
		for y in grid_min_y..<grid_max_y {
			append(&grid.cells[x][y], entity_lookup);
		}
	}
}

entity_grid_remove :: proc(grid: ^Entity_Grid, entity_lookup: Entity_Lookup, entity: ^Entity) {
	grid_min_x, grid_min_y, grid_max_x, grid_max_y, ok := bounds_to_grid_cells(grid.half_cell_count, CELL_SIZE, entity.bounds);
	if !ok do return;

	for x in grid_min_x..<grid_max_x {
		for y in grid_min_y..<grid_max_y {
			i, ok := slice.linear_search(grid.cells[x][y][:], entity_lookup);
			assert(ok);
			unordered_remove(&grid.cells[x][y], i);
		}
	}
}

entity_grid_move_tentatively :: proc(grid: ^Entity_Grid, entity_lookup: Entity_Lookup, entity: ^Entity, tentative_orientation: linalg.Quaternionf32, tentative_transform: linalg.Matrix4f32) {
	// Remove the lookup from the old cells which this entity spans
	grid_min_x, grid_min_y, grid_max_x, grid_max_y, ok := bounds_to_grid_cells(grid.half_cell_count, CELL_SIZE, entity.bounds);
	if !ok do return;

	for x in grid_min_x..<grid_max_x {
		for y in grid_min_y..<grid_max_y {
			cell := &grid.cells[x][y];

			i, ok := slice.linear_search(cell[:], entity_lookup);
			assert(ok);
			unordered_remove(cell, i);
		}
	}

	// Update the global transform matrix and the global bounds
	update_entity_hull_transforms_and_bounds(entity, tentative_orientation, tentative_transform);

	// Add the lookup to the new cells which this hull spans
	grid_min_x, grid_min_y, grid_max_x, grid_max_y, ok = bounds_to_grid_cells(grid.half_cell_count, CELL_SIZE, entity.bounds);
	if !ok do return;

	for x in grid_min_x..<grid_max_x {
		for y in grid_min_y..<grid_max_y {
			append(&grid.cells[x][y], entity_lookup);
		}
	}
}

entity_grid_find_nearby_entities :: proc(grid: ^Entity_Grid, bounds: math2.Box3f32) -> [dynamic]Entity_Lookup {
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

entity_grid_cleanup :: proc(grid: ^Entity_Grid) {
	for &col in grid.cells {
		for &row in col {
			delete(row);
		}

		delete(col);
	}

	delete(grid.cells);
}