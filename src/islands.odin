package main;

import "core:math/linalg";
import "core:slice";

Islands :: struct {
	islands: [dynamic]Island,
	free_islands: [dynamic]int,
	awake_island_indices: [dynamic]int,
	island_helpers: [dynamic]Geometry_Lookup,
}

Island :: struct {
	state: Island_State,
	lookups: [dynamic]Entity_Lookup,
	awake_island_index_index: int,
}

Island_State :: enum { Awake, Asleep, Free };

init_islands :: proc(islands: ^Islands, count: u32) {
	assert(len(islands.islands) == 0);
	assert(len(islands.awake_island_indices) == 0);

	for _ in 0..<count {
		append(&islands.islands, Island {
			state = .Asleep,
			lookups = [dynamic]Entity_Lookup {},
			awake_island_index_index = -1,
		});
	}
}

add_rigid_body_to_island :: proc(islands: ^Islands, island_index: int, lookup: Entity_Lookup, rigid_body: ^Rigid_Body_Entity) {
	append(&islands.islands[island_index].lookups, lookup);
	rigid_body.island_index = island_index;
}

clear_islands :: proc(islands: ^Islands) {
	clear(&islands.awake_island_indices);
}

init_island :: proc(islands: ^Islands, lookup: Entity_Lookup, rigid_body: ^Rigid_Body_Entity) {
	island := Island {
		state = .Awake,
		lookups = [dynamic]Entity_Lookup {lookup},
		awake_island_index_index = len(islands.awake_island_indices),
	};

	island_index: int;

	if index, ok := pop_safe(&islands.free_islands); ok {
		islands.islands[index] = island;
		island_index = index;
	} else {
		append(&islands.islands, island);
		island_index = len(islands.islands) - 1;
	}

	rigid_body.island_index = island_index;
	append(&islands.awake_island_indices, island_index);
}

car_collision_maybe_wake_island :: proc(islands: ^Islands, entities_woken_up: ^[dynamic]Entity_Lookup, nearby_rigid_body: ^Rigid_Body_Entity) {
	nearby_island := &islands.islands[nearby_rigid_body.island_index];

	if nearby_island.state == .Asleep {
		nearby_island.state = .Awake;
		append(&islands.awake_island_indices, nearby_rigid_body.island_index);
		nearby_island.awake_island_index_index = len(islands.awake_island_indices) - 1;

		append(entities_woken_up, ..nearby_island.lookups[:]);
	}
}

maybe_wake_island_post_solve :: proc(islands: ^Islands, rigid_body: ^Rigid_Body_Entity, entities_woken_up: ^[dynamic]Entity_Lookup) {
	island := &islands.islands[rigid_body.island_index];
	if island.state == .Free || island.state == .Awake do return;

	append(entities_woken_up, ..island.lookups[:]);
	append(&islands.free_islands, rigid_body.island_index);
	island.state = .Free;
	delete(island.lookups);
}

rigid_body_collision_merge_islands :: proc(islands: ^Islands, entities_woken_up: ^[dynamic]Entity_Lookup, provoking_lookup: Entity_Lookup, provoking_rigid_body, nearby_rigid_body: ^Rigid_Body_Entity) {
	provoking_island_index := provoking_rigid_body.island_index;
	nearby_island_index := nearby_rigid_body.island_index;

	if provoking_island_index == nearby_island_index do return;
	
	provoking_island := &islands.islands[provoking_island_index];
	nearby_island := &islands.islands[nearby_island_index];

	append(&provoking_island.lookups, ..nearby_island.lookups[:]);

	for lookup in nearby_island.lookups {
		nearby_rigid_body := get_entity(lookup).variant.(^Rigid_Body_Entity);
		nearby_rigid_body.island_index = provoking_island_index;
	}

	switch nearby_island.state {
	case .Asleep:
		append(entities_woken_up, ..nearby_island.lookups[:]);
	case .Awake:
		unordered_remove(&islands.awake_island_indices, nearby_island.awake_island_index_index);

		if nearby_island.awake_island_index_index != len(islands.awake_island_indices) {
			swapped_island_index := islands.awake_island_indices[nearby_island.awake_island_index_index];
			swapped_island := &islands.islands[swapped_island_index];
			swapped_island.awake_island_index_index = nearby_island.awake_island_index_index;
		}
	case .Free:
		unreachable();
	}

	append(&islands.free_islands, nearby_island_index);
	nearby_island.state = .Free;
	delete(nearby_island.lookups);
}

sleep_islands :: proc(islands: ^Islands, awake_rigid_body_lookups: ^[dynamic]Entity_Lookup) {
	SLEEP_DURATION: f32 : 2;

	clear(awake_rigid_body_lookups);

	for island_index in islands.awake_island_indices {
		island := &islands.islands[island_index];
		asleep := true;

		when ODIN_DEBUG do assert(len(island.lookups) > 0);

		for lookup in island.lookups {
			rigid_body := get_entity(lookup).variant.(^Rigid_Body_Entity);

			if rigid_body.sleep_duration < SLEEP_DURATION {
				asleep = false;
				break;
			}
		}

		if asleep {
			island.state = .Asleep;
			island.awake_island_index_index = -1;
		} else {
			append(awake_rigid_body_lookups, ..island.lookups[:]);

			append(&islands.free_islands, island_index);
			island.state = .Free;
			delete(island.lookups);
		}
	}
}

remove_rigid_body_from_island :: proc(islands: ^Islands, lookup: Entity_Lookup, rigid_body: ^Rigid_Body_Entity) {
	island := &islands.islands[rigid_body.island_index];

	if island.state == .Asleep {
		unimplemented();
	}

	index, ok := slice.linear_search(island.lookups[:], lookup);
	assert(ok);
	unordered_remove(&island.lookups, index);

	if len(island.lookups) == 0 {
		unordered_remove(&islands.awake_island_indices, island.awake_island_index_index);
		
		if island.awake_island_index_index != len(islands.awake_island_indices) {
			swapped_island_index := islands.awake_island_indices[island.awake_island_index_index];
			swapped_island := &islands.islands[swapped_island_index];
			swapped_island.awake_island_index_index = island.awake_island_index_index;
		}

		append(&islands.free_islands, rigid_body.island_index);
		island.state = .Free;
		delete(island.lookups);
	}
}

update_island_helpers :: proc(islands: ^Islands) {
	for lookup in islands.island_helpers {
		remove_geometry(lookup);
	}

	clear(&islands.island_helpers);

	for &island in islands.islands {
		if island.state == .Free do continue;

		bounds_min := linalg.Vector3f32 { max(f32), max(f32), max(f32) };
		bounds_max := linalg.Vector3f32 { min(f32), min(f32), min(f32) };

		for lookup in island.lookups {
			entity := get_entity(lookup);

			for hull in &entity.collision_hulls {
				bounds_min = linalg.min(bounds_min, hull.global_bounds.min);
				bounds_max = linalg.max(bounds_max, hull.global_bounds.max);
			}
		}

		geometry, geometry_lookup := create_geometry("island visualizer", .KeepRender);

		color := island.state == .Asleep ? [?]f32 {1, 1, 1} : [?]f32 {0, 1, 0};
		geometry_make_box_helper(geometry, bounds_min, bounds_max, color);
		append(&islands.island_helpers, geometry_lookup);
	}
}

cleanup_islands :: proc(islands: ^Islands) {
	delete(islands.free_islands);
	delete(islands.awake_island_indices);
	delete(islands.island_helpers);

	for island in &islands.islands {
		if island.state == .Free do continue;

		delete(island.lookups);
	}

	delete(islands.islands);
}