package main;

import "core:slice";

Entities_Geos :: struct {
	geometry_records: [dynamic]Geometry_Record,
	free_geometry_records: [dynamic]int,
	entity_records: [dynamic]Entity_Record,
	free_entity_records: [dynamic]int,
}

Geometry_Record :: struct {
	freed: bool,
	generation: u32,
	geometry: Geometry,
	entity_lookups: [dynamic]Entity_Lookup,
	on_no_entities: On_No_Entities,
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

On_No_Entities :: enum {Free, Render}

add_geometry :: proc(using entities_geos: ^Entities_Geos, geometry: Geometry, on_no_entities: On_No_Entities = .Free) -> Geometry_Lookup {
	if index, ok := pop_safe(&free_geometry_records); ok {
		record := &geometry_records[index];
		
		when ODIN_DEBUG {
			assert(record.freed);
			assert(len(record.entity_lookups) == 0);
		}
		
		record.freed = false;
		record.geometry = geometry;
		record.on_no_entities = on_no_entities;

		return Geometry_Lookup { index, record.generation };
	} else {
		append(&geometry_records, Geometry_Record {
			freed = false,
			geometry = geometry,
			on_no_entities = on_no_entities,
		});

		return Geometry_Lookup { len(geometry_records) - 1, 0 };
	}
}

add_entity :: proc(using entities_geos: ^Entities_Geos, geometry_lookup: Geometry_Lookup, entity: ^Entity) -> Entity_Lookup {
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

add_collision_hull_to_entity :: proc(using entities_geos: ^Entities_Geos, collision_hull_grid: ^Collision_Hull_Grid, lookup: Entity_Lookup, hull: Collision_Hull) {
	record := &entity_records[lookup.index];
	assert(lookup.generation == record.generation);

	record_index := insert_into_collision_hull_grid(collision_hull_grid, lookup, hull);
	append(&record.entity.collision_hull_record_indices, record_index);
}

get_geometry :: proc(using entities_geos: ^Entities_Geos, lookup: Geometry_Lookup) -> ^Geometry {
	record := &geometry_records[lookup.index];
	assert(lookup.generation == record.generation);

	return &record.geometry;
}

get_entity :: proc(using entities_geos: ^Entities_Geos, lookup: Entity_Lookup) -> ^Entity {
	record := &entity_records[lookup.index];
	assert(lookup.generation == record.generation);

	return record.entity;
}

remove_geometry :: proc(using entities_geos: ^Entities_Geos, lookup: Geometry_Lookup) {
	record := &geometry_records[lookup.index];
	assert(lookup.generation == record.generation);

	assert(len(record.entity_lookups) == 0); // We just haven't yet needed to destroy an geometry with entities. Shouldn't be an issue to do.

	delete(record.geometry.indices);
	delete(record.geometry.attributes);

	record.freed = true;
	record.generation += 1;
	append(&free_geometry_records, lookup.index);
}

remove_entity :: proc(using entities_geos: ^Entities_Geos, entity_lookup: Entity_Lookup) {
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

	if geometry_record.on_no_entities == .Free && len(geometry_record.entity_lookups) == 0 {
		delete(geometry_record.geometry.indices);
		delete(geometry_record.geometry.attributes);

		geometry_record.freed = true;
		geometry_record.generation += 1;
		append(&free_geometry_records, entity_record.geometry_record_index);
	}

	free(entity_record.entity);
	entity_record.generation += 1;
	append(&free_entity_records, entity_lookup.index);
}

cleanup_entities_geos :: proc(using entities_geos: ^Entities_Geos) {
	for record, i in &geometry_records {
		delete(record.entity_lookups);
		
		if slice.contains(free_geometry_records[:], i) do continue;

		delete(record.geometry.indices);
		delete(record.geometry.attributes);
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