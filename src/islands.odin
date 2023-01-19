package main;

import "core:math/linalg";
import "core:slice";

Islands :: struct {
	nodes: [dynamic]Node,
	root_node_indices: [dynamic]int,
	asleep_islands: [dynamic][dynamic]Entity_Lookup,
	free_asleep_island_indices: [dynamic]int,
	island_helpers: [dynamic]Geometry_Lookup,
}

Node :: struct {
	parent_index: int,
	kind: union { Internal_Node, Leaf_Node },
	root_node_index: int,
}

Internal_Node :: struct {
	child_a_index, child_b_index: int,
}

Leaf_Node :: struct {
	entity_lookup: Entity_Lookup,
}

clear_islands :: proc(using islands: ^Islands) {
	clear(&nodes);
	clear(&root_node_indices);
}

init_island :: proc(using islands: ^Islands, lookup: Entity_Lookup, rigid_body: ^Rigid_Body_Entity) {
	append(&nodes, Node {
		parent_index = -1,
		kind = Leaf_Node { lookup },
		root_node_index = len(root_node_indices),
	});

	node_index := len(nodes) - 1;
	append(&root_node_indices, node_index);

	rigid_body.node_index = node_index;
}

merge_islands :: proc(using islands: ^Islands, entities_geos: ^Entities_Geos, entities_woken_up: ^[dynamic]Entity_Lookup, provoking_rigid_body, nearby_rigid_body: ^Rigid_Body_Entity) {
	if nearby_rigid_body.asleep_island_index != -1 {
		wake_island(islands, entities_geos, nearby_rigid_body.asleep_island_index, entities_woken_up);
	}

	link_nodes(islands, provoking_rigid_body.node_index, nearby_rigid_body.node_index);
}

wake_island :: proc(using islands: ^Islands, entities_geos: ^Entities_Geos, asleep_island_index: int, entities_woken_up: ^[dynamic]Entity_Lookup) {
	for lookup in asleep_islands[asleep_island_index] {
		rigid_body := get_entity(entities_geos, lookup).variant.(^Rigid_Body_Entity);
		rigid_body.asleep_island_index = -1;
		rigid_body.sleep_duration = 0;

		append(&nodes, Node {
			parent_index = -1,
			kind = Leaf_Node { lookup },
			root_node_index = len(root_node_indices),
		});

		node_index := len(nodes) - 1;
		append(&root_node_indices, node_index);

		rigid_body.node_index = node_index;
		append(entities_woken_up, lookup);
	}

	delete(asleep_islands[asleep_island_index]);
	append(&free_asleep_island_indices, asleep_island_index);
}

link_nodes :: proc(using islands: ^Islands, node_a_index, node_b_index: int) {
	root_a_index := find_root_node_index(islands, node_a_index);
	root_b_index := find_root_node_index(islands, node_b_index);

	if root_a_index == root_b_index do return;

	root_a_index_index := nodes[root_a_index].root_node_index;
	root_b_index_index := nodes[root_b_index].root_node_index;

	append(&nodes, Node {
		parent_index = -1,
		kind = Internal_Node { root_a_index, root_b_index },
		root_node_index = root_a_index_index,
	});

	parent_index := len(nodes) - 1;

	nodes[root_a_index].parent_index = parent_index;
	nodes[root_b_index].parent_index = parent_index;

	root_node_indices[root_a_index_index] = parent_index;
	root_node_indices[root_b_index_index] = -1;
}

find_root_node_index :: proc(using islands: ^Islands, node_index: int) -> int {
	root_index := node_index;

	for {
		parent_index := nodes[root_index].parent_index;

		if parent_index != -1 {
			root_index = parent_index;
		} else {
			return root_index;
		}
	}
}

sleep_islands :: proc(using islands: ^Islands, entities_geos: ^Entities_Geos, awake_rigid_body_lookups: ^[dynamic]Entity_Lookup) {
	clear(awake_rigid_body_lookups);

	for root_node_index in root_node_indices {
		if root_node_index == -1 do continue;

		island_asleep := true;
		lookups := make([dynamic]Entity_Lookup, context.temp_allocator);
		indices_to_visit := make([dynamic]int, context.temp_allocator);
		node_index, ok := root_node_index, true;

		for ok {
			node := &nodes[node_index];
			switch n in node.kind {
				case Internal_Node:
					append(&indices_to_visit, n.child_a_index, n.child_b_index);
				
				case Leaf_Node:
					rigid_body := get_entity(entities_geos, n.entity_lookup).variant.(^Rigid_Body_Entity);
					if rigid_body.sleep_duration < 2.0 do island_asleep = false;

					append(&lookups, n.entity_lookup);
			}

			node_index, ok = pop_safe(&indices_to_visit);
		}

		if island_asleep {
			asleep_island_index: int;

			if index, ok := pop_safe(&free_asleep_island_indices); ok {
				asleep_island_index = index;
			} else {
				append(&asleep_islands, [dynamic]Entity_Lookup {});
				asleep_island_index = len(asleep_islands) - 1;
			}

			for lookup in lookups {
				rigid_body := get_entity(entities_geos, lookup).variant.(^Rigid_Body_Entity);
				rigid_body.asleep_island_index = asleep_island_index;
			}

			asleep_islands[asleep_island_index] = slice.clone_to_dynamic(lookups[:]);
		} else {
			append(awake_rigid_body_lookups, ..lookups[:]);
		}
	}
}

update_island_helpers :: proc(using islands: ^Islands, collision_hull_grid: ^Collision_Hull_Grid, entities_geos: ^Entities_Geos) {
	for lookup in island_helpers {
		remove_geometry(entities_geos, lookup);
	}

	clear(&island_helpers);

	for root_node_index in root_node_indices {
		if root_node_index == -1 do continue;

		bounds_min := linalg.Vector3f32 { max(f32), max(f32), max(f32) };
		bounds_max := linalg.Vector3f32 { min(f32), min(f32), min(f32) };
		indices_to_visit := make([dynamic]int, context.temp_allocator);
		node_index, ok := root_node_index, true;

		for ok {
			node := &nodes[node_index];

			switch n in node.kind {
				case Internal_Node:
					append(&indices_to_visit, n.child_a_index, n.child_b_index);
				
				case Leaf_Node:
					entity := get_entity(entities_geos, n.entity_lookup);

					for hull_index in entity.collision_hull_record_indices {
						hull := &collision_hull_grid.hull_records[hull_index].hull;
						bounds_min = linalg.min(bounds_min, hull.global_bounds.min);
						bounds_max = linalg.max(bounds_max, hull.global_bounds.max);
					}
			}

			node_index, ok = pop_safe(&indices_to_visit);
		}

		geo := init_box_helper(bounds_min, bounds_max, [?]f32 {0, 1, 0});
		geo_lookup := add_geometry(entities_geos, geo, .Render);
		append(&island_helpers, geo_lookup);
	}

	for island, island_index in &asleep_islands {
		if slice.contains(free_asleep_island_indices[:], island_index) do continue;

		bounds_min := linalg.Vector3f32 { max(f32), max(f32), max(f32) };
		bounds_max := linalg.Vector3f32 { min(f32), min(f32), min(f32) };

		for lookup in island {
			entity := get_entity(entities_geos, lookup);

			for hull_index in entity.collision_hull_record_indices {
				hull := &collision_hull_grid.hull_records[hull_index].hull;
				bounds_min = linalg.min(bounds_min, hull.global_bounds.min);
				bounds_max = linalg.max(bounds_max, hull.global_bounds.max);
			}
		}

		geo := init_box_helper(bounds_min, bounds_max, [?]f32 {1, 1, 1});
		geo_lookup := add_geometry(entities_geos, geo, .Render);
		append(&island_helpers, geo_lookup);
	}
}

cleanup_islands :: proc(using islands: ^Islands) {
	delete(nodes);
	delete(root_node_indices);
	delete(free_asleep_island_indices);
	delete(island_helpers);

	for island in &asleep_islands {
		delete(island);
	}

	delete(asleep_islands);
}