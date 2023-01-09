package main;

import "core:slice";

Entities :: struct {
	geometry_records: [dynamic]Geometry_Record,
	free_geometry_records: [dynamic]int,
	entity_records: [dynamic]Entity_Record,
	free_entity_records: [dynamic]int,
}

Geometry_Record :: struct {
	generation: u32,
	geometry: Geometry,
	entity_lookups: [dynamic]Entity_Lookup,
	freeable: bool,
}

Entity_Record :: struct {
	generation: u32,
	entity: ^Entity,
	geometry_record_index: int,
}

Lookup :: struct {
	index: int,
	generation: u32,
}

Geometry_Lookup :: distinct Lookup;
Entity_Lookup :: distinct Lookup;

add_geometry :: proc(using entities: ^Entities, geometry: Geometry, freeable: bool) -> Geometry_Lookup {
	if index, ok := pop_safe(&free_geometry_records); ok {
		record := &geometry_records[index];
		
		when ODIN_DEBUG do assert(len(record.entity_lookups) == 0);
		record.geometry = geometry;
		record.freeable = freeable;

		return Geometry_Lookup { index, record.generation };
	} else {
		append(&geometry_records, Geometry_Record {
			geometry = geometry,
			freeable = freeable,
		});

		return Geometry_Lookup { len(geometry_records) - 1, 0 };
	}
}

add_entity :: proc(using entities: ^Entities, geometry_lookup: Geometry_Lookup, entity: ^Entity) -> Entity_Lookup {
	geometry_record := &geometry_records[geometry_lookup.index];
	assert(geometry_lookup.generation == geometry_record.generation);

	entity_lookup: Entity_Lookup;

	if index, ok := pop_safe(&free_entity_records); ok {
		record := &entity_records[index];
		record.entity = entity;
		record.geometry_record_index = geometry_lookup.index;

		entity_lookup = Entity_Lookup { index, record.generation };
	} else {
		append(&entity_records, Entity_Record {
			entity = entity,
			geometry_record_index = geometry_lookup.index,
		});

		entity_lookup = Entity_Lookup { len(entity_records) - 1, 0 };
	}

	append(&geometry_record.entity_lookups, entity_lookup);
	return entity_lookup;
}

add_collision_hull_to_entity :: proc(using entities: ^Entities, collision_hull_grid: ^Collision_Hull_Grid, lookup: Entity_Lookup, hull: Collision_Hull) {
	record := &entity_records[lookup.index];
	assert(lookup.generation == record.generation);

	record_index := insert_into_collision_hull_grid(collision_hull_grid, lookup, hull);
	append(&record.entity.collision_hull_record_indices, record_index);
}

get_entity :: proc(using entities: ^Entities, $T: typeid, lookup: Entity_Lookup) -> ^T {
	record := &entity_records[lookup.index];
	assert(lookup.generation == record.generation);

	return record.entity.variant.(^T);
}

remove_entity :: proc(using entites: ^Entities, entity_lookup: Entity_Lookup) {
	entity_record := &entity_records[entity_lookup.index];
	assert(entity_lookup.generation == entity_record.generation);

	if len(entity_record.entity.collision_hull_record_indices) > 0 {
		unimplemented();
		// delete(entity_record.entity.collision_hull_record_indices);
	}

	geometry_record := &geometry_records[entity_record.geometry_record_index];

	removal_index, ok := slice.linear_search(geometry_record.entity_lookups[:], entity_lookup);
	assert(ok);
	unordered_remove(&geometry_record.entity_lookups, removal_index);

	if geometry_record.freeable && len(geometry_record.entity_lookups) == 0 {
		delete(geometry_record.geometry.indices);
		delete(geometry_record.geometry.attributes);

		geometry_record.generation += 1;
		append(&free_geometry_records, entity_record.geometry_record_index);
	}

	free(entity_record.entity);
	entity_record.generation += 1;
	append(&free_entity_records, entity_lookup.index);
}

cleanup_entities :: proc(using entites: ^Entities) {
	for record, i in &geometry_records {\
		if slice.contains(free_geometry_records[:], i) do continue;

		delete(record.geometry.indices);
		delete(record.geometry.attributes);
		delete(record.entity_lookups);
	}

	delete(geometry_records);
	delete(free_geometry_records);

	for record, i in &entity_records {
		if slice.contains(free_entity_records[:], i) do continue;

		delete(record.entity.collision_hull_record_indices);
		free(record.entity);
	}

	delete(entity_records);
	delete(free_entity_records);
}