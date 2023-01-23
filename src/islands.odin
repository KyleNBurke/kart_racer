package main;

import "core:math/linalg";

Islands :: struct {
	islands: [dynamic]Island,
	free_islands: [dynamic]int,
	awake_island_indices: [dynamic]int,
	island_helpers: [dynamic]Geometry_Lookup,
}

Island :: struct {
	free: bool,
	asleep: bool,
	lookups: [dynamic]Entity_Lookup,
	awake_island_index_index: int,
}

init_islands :: proc(islands: ^Islands, count: u32) {
	assert(len(islands.islands) == 0);
	assert(len(islands.awake_island_indices) == 0);

	for i in 0..<count {
		append(&islands.islands, Island {
			free = false,
			asleep = true,
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
		free = false,
		asleep = false,
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

	if nearby_island.asleep {
		nearby_island.asleep = false;
		append(&islands.awake_island_indices, nearby_rigid_body.island_index);
		nearby_island.awake_island_index_index = len(islands.awake_island_indices) - 1;

		append(entities_woken_up, ..nearby_island.lookups[:]);
	}
}

rigid_body_collision_merge_islands :: proc(islands: ^Islands, entities_geos: ^Entities_Geos, entities_woken_up: ^[dynamic]Entity_Lookup, provoking_lookup: Entity_Lookup, provoking_rigid_body, nearby_rigid_body: ^Rigid_Body_Entity) {
	provoking_island_index := provoking_rigid_body.island_index;
	nearby_island_index := nearby_rigid_body.island_index;

	if provoking_island_index == nearby_island_index do return;
	
	provoking_island := &islands.islands[provoking_island_index];
	nearby_island := &islands.islands[nearby_island_index];

	append(&provoking_island.lookups, ..nearby_island.lookups[:]);

	for lookup in nearby_island.lookups {
		nearby_rigid_body := get_entity(entities_geos, lookup).variant.(^Rigid_Body_Entity);
		nearby_rigid_body.island_index = provoking_island_index;
	}

	if nearby_island.asleep {
		nearby_island.asleep = false;
		append(entities_woken_up, ..nearby_island.lookups[:]);
	} else {
		unordered_remove(&islands.awake_island_indices, nearby_island.awake_island_index_index);
		if nearby_island.awake_island_index_index != len(islands.awake_island_indices) {
			swapped_island_index := islands.awake_island_indices[nearby_island.awake_island_index_index];
			swapped_island := &islands.islands[swapped_island_index];
			swapped_island.awake_island_index_index = nearby_island.awake_island_index_index;
		}
	}

	append(&islands.free_islands, nearby_island_index);
	nearby_island.free = true;
	delete(nearby_island.lookups);
}

sleep_islands :: proc(islands: ^Islands, entities_geos: ^Entities_Geos, awake_rigid_body_lookups: ^[dynamic]Entity_Lookup) {
	SLEEP_DURATION: f32 : 2;

	clear(awake_rigid_body_lookups);

	for island_index in islands.awake_island_indices {
		island := &islands.islands[island_index];
		asleep := true;

		when ODIN_DEBUG do assert(len(island.lookups) > 0);

		for lookup in island.lookups {
			rigid_body := get_entity(entities_geos, lookup).variant.(^Rigid_Body_Entity);

			if rigid_body.sleep_duration < SLEEP_DURATION {
				asleep = false;
				break;
			}
		}

		if asleep {
			island.asleep = true;
			island.awake_island_index_index = -1;
		} else {
			append(awake_rigid_body_lookups, ..island.lookups[:]);

			append(&islands.free_islands, island_index);
			island.free = true;
			delete(island.lookups);
		}
	}
}

update_island_helpers :: proc(islands: ^Islands, entities_geos: ^Entities_Geos) {
	for lookup in islands.island_helpers {
		remove_geometry(entities_geos, lookup);
	}

	clear(&islands.island_helpers);

	for island, island_index in &islands.islands {
		if island.free do continue;

		bounds_min := linalg.Vector3f32 { max(f32), max(f32), max(f32) };
		bounds_max := linalg.Vector3f32 { min(f32), min(f32), min(f32) };

		for lookup in island.lookups {
			entity := get_entity(entities_geos, lookup);

			for hull in &entity.collision_hulls {
				bounds_min = linalg.min(bounds_min, hull.global_bounds.min);
				bounds_max = linalg.max(bounds_max, hull.global_bounds.max);
			}
		}

		color := [?]f32 {1, 1, 1} if island.asleep else [?]f32 {0, 1, 0};
		geo := init_box_helper(bounds_min, bounds_max, color);
		geo_lookup := add_geometry(entities_geos, geo, .Render);
		append(&islands.island_helpers, geo_lookup);
	}
}

cleanup_islands :: proc(islands: ^Islands) {
	delete(islands.free_islands);
	delete(islands.awake_island_indices);
	delete(islands.island_helpers);

	for island in &islands.islands {
		if island.free do continue;

		delete(island.lookups);
	}

	delete(islands.islands);
}