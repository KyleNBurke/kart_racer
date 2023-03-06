package main;

import "core:math";
import "core:math/linalg";
import "core:slice";
import "math2";

@(private="file")
CELL_SIZE: f32 : 20.0;

Collision_Hull_Grid :: struct {
	half_cell_count: u32,
	hull_records: [dynamic]Collision_Hull_Record,
	query_flags: [dynamic]u32,
	grid: [dynamic][dynamic][dynamic]int,
	hull_helpers: [dynamic]Entity_Lookup,
}

Collision_Hull_Record :: struct {
	entity_lookup: Entity_Lookup,
	hull: ^Collision_Hull,
	query_run: u32,
}

reset_collision_hull_grid :: proc(using collision_hull_grid: ^Collision_Hull_Grid, half_size: f32) {
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

insert_into_collision_hull_grid :: proc(using collision_hull_grid: ^Collision_Hull_Grid, entity_lookup: Entity_Lookup, hull: ^Collision_Hull) -> int {
	record := Collision_Hull_Record {
		entity_lookup,
		hull,
		0,
	};

	append(&hull_records, record);
	record_index := len(hull_records) - 1;

	grid_min_x, grid_min_y, grid_max_x, grid_max_y, ok := bounds_to_grid_cells(half_cell_count, CELL_SIZE, hull.global_bounds);
	assert(ok);

	for x in grid_min_x..<grid_max_x {
		for y in grid_min_y..<grid_max_y {
			append(&grid[x][y], record_index);
		}
	}

	return record_index;
}

// This proc gets called with a tentative transform. That might seem wrong but it's actually correct. We want to move the entities tentatively such that they are
// actually penetrating one another. The next time the proc gets called the collision hull is removed from the cells wich comprise the old tentative position and
// then the cells get the hull of the new tentative position. Hulls in this grid are always at tentative positions.
collision_hull_grid_transform_entity :: proc(using collision_hull_grid: ^Collision_Hull_Grid, hull_record_indices: []int, global_entity_transform: linalg.Matrix4f32) {
	for record_index in hull_record_indices {
		hull := hull_records[record_index].hull;

		// Remove the hull reference from the old cells which this hull spans
		grid_min_x, grid_min_y, grid_max_x, grid_max_y, ok := bounds_to_grid_cells(half_cell_count, CELL_SIZE, hull.global_bounds);
		if !ok do return;

		for x in grid_min_x..<grid_max_x {
			for y in grid_min_y..<grid_max_y {
				cell := &grid[x][y];

				removal_index, ok := slice.linear_search(cell[:], record_index);
				assert(ok);
				unordered_remove(cell, removal_index);
			}
		}

		// Update the global transform matrix and the global bounds
		update_collision_hull_global_transform_and_bounds(hull, global_entity_transform);

		// Add the hull reference to the new cells which this hull spans
		grid_min_x, grid_min_y, grid_max_x, grid_max_y, ok = bounds_to_grid_cells(half_cell_count, CELL_SIZE, hull.global_bounds);
		if !ok do return;

		for x in grid_min_x..<grid_max_x {
			for y in grid_min_y..<grid_max_y {
				append(&grid[x][y], record_index);
			}
		}
	}
}

collision_hull_grid_find_nearby_hulls :: proc(using collision_hull_grid: ^Collision_Hull_Grid, bounds: math2.Box3f32) -> [dynamic]int {
	@(static) query_run: u32 = 0;

	if query_run == max(u32) {
		for record in &hull_records {
			record.query_run = 0;
		}

		query_run = 0;
	}

	query_run += 1;
	indices := make([dynamic]int, context.temp_allocator);

	grid_min_x, grid_min_y, grid_max_x, grid_max_y, ok := bounds_to_grid_cells(half_cell_count, CELL_SIZE, bounds);
	if !ok do return indices;

	for x in grid_min_x..<grid_max_x {
		for y in grid_min_y..<grid_max_y {
			for index in &grid[x][y] {
				record := &hull_records[index];

				if record.query_run != query_run {
					append(&indices, index);
					record.query_run = query_run;
				}
			}
		}
	}

	return indices;
}

collision_hull_grid_update_hull_helpers :: proc(using collision_hull_grid: ^Collision_Hull_Grid, entities_geos: ^Entities_Geos) {
	for lookup in &hull_helpers {
		remove_entity(entities_geos, lookup);
	}

	clear(&hull_helpers);

	if len(hull_records) == 0 do return;

	geo := init_box_helper();
	geo_lookup := add_geometry(entities_geos, geo);

	for hull_record in &hull_records {
		helper := new_inanimate_entity();
		helper.transform = hull_record.hull.global_transform;
		helper_lookup := add_entity(entities_geos, geo_lookup, helper);
		append(&hull_helpers, helper_lookup);
	}
}

collision_hull_grid_cleanup :: proc(using collision_hull_grid: ^Collision_Hull_Grid) {
	delete(hull_records);
	delete(query_flags);

	for col in &grid {
		for row in &col {
			delete(row);
		}

		delete(col);
	}

	delete(grid);
	delete(hull_helpers);
}