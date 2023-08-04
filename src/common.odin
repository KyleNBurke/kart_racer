package main;

import "core:math";
import "math2";

bounds_to_grid_cells :: proc(half_cell_count: int, cell_size: f32, bounds: math2.Box3f32) -> (min_x, min_y, max_x, max_y: int, ok: bool) {
	half_cell_count_f32 := f32(half_cell_count);
	cell_count := half_cell_count * 2;
	cell_count_f32 := f32(cell_count);

	min_x = cast(int) max(math.floor(bounds.min.x / cell_size + half_cell_count_f32), 0);
	min_y = cast(int) max(math.floor(bounds.min.z / cell_size + half_cell_count_f32), 0);
	max_x = cast(int) min(math.ceil(bounds.max.x / cell_size + half_cell_count_f32), cell_count_f32);
	max_y = cast(int) min(math.ceil(bounds.max.z / cell_size + half_cell_count_f32), cell_count_f32);

	// We use min and max to account for things partially off the grid. If something is fully off the grid,
	// on the negative side, it's max value will be 0. If it's on the grid, it will be ceil'd to 1. It
	// works similarly on the other side.
	if max_x < 0 || max_y < 0 || min_x >= cell_count || min_y >= cell_count {
		ok = false;
		return;
	}
	
	// These checks account for the situation where you have a completely vertical wall lined up perfectly
	// with a grid boundary. If that happens you will get the same min and max value which is a problem for
	// iteration. We must either increase the max or decrease the min.
	if min_x == max_x {
		if max_x == cell_count - 1 {
			min_x -= 1;
		} else {
			max_x += 1;
		}
	}

	if min_y == max_y {
		if max_y == cell_count - 1 {
			min_y -= 1;
		} else {
			max_y += 1;
		}
	}

	ok = true;
	return;
}