package main;

import "core:math";
import "core:math/linalg";
import "math2";

bounds_to_grid_cells :: proc(half_cell_count: u32, cell_size: f32, bounds: math2.Box3f32) -> (min_x, min_y, max_x, max_y: u32, ok: bool) {
	half_cell_count_f32 := f32(half_cell_count);
	cell_count := half_cell_count * 2;
	cell_count_f32 := f32(cell_count);

	min_x = cast(u32) math.max(math.floor(bounds.min.x / cell_size + half_cell_count_f32), 0.0);
	min_y = cast(u32) math.max(math.floor(bounds.min.z / cell_size + half_cell_count_f32), 0.0);
	max_x = cast(u32) math.min(math.ceil(bounds.max.x / cell_size + half_cell_count_f32), cell_count_f32);
	max_y = cast(u32) math.min(math.ceil(bounds.max.z / cell_size + half_cell_count_f32), cell_count_f32);

	if max_x == 0 || max_y == 0 || min_x == cell_count || min_y == cell_count {
		ok = false;
	} else {
		ok = true;
	}

	return;
}