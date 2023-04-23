package main;

import "core:slice";

entities_geos := Entities_Geos {};

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

On_No_Entities :: enum {
	Keep,       // Will not free the geometry
	KeepRender, // Will not free the geometry and will render it with an identity matrix
	Free,       // Free the geometry
}

init_entities_geos :: proc() {
	null_entity_record := Entity_Record {
		generation = 1,
		entity = nil,
		geometry_record_index = -1,
	};

	append(&entities_geos.entity_records, null_entity_record);
}

add_geometry :: proc(geometry: Geometry, on_no_entities: On_No_Entities = .Free) -> Geometry_Lookup {
	if index, ok := pop_safe(&entities_geos.free_geometry_records); ok {
		record := &entities_geos.geometry_records[index];
		
		when ODIN_DEBUG {
			assert(record.freed);
			assert(len(record.entity_lookups) == 0);
		}
		
		record.freed = false;
		record.geometry = geometry;
		record.on_no_entities = on_no_entities;

		return Geometry_Lookup { index, record.generation };
	} else {
		append(&entities_geos.geometry_records, Geometry_Record {
			freed = false,
			geometry = geometry,
			on_no_entities = on_no_entities,
		});

		return Geometry_Lookup { len(entities_geos.geometry_records) - 1, 0 };
	}
}

add_entity :: proc(geometry_lookup: Maybe(Geometry_Lookup), entity: ^Entity) -> Entity_Lookup {
	if geometry_lookup, ok := geometry_lookup.?; ok {
		geometry_record := &entities_geos.geometry_records[geometry_lookup.index];
		assert(geometry_lookup.generation == geometry_record.generation);
	}

	geometry_record_index: int = ---;

	if geometry_lookup, ok := geometry_lookup.?; ok {
		geometry_record_index = geometry_lookup.index;
	} else {
		geometry_record_index = -1;
	}

	entity_lookup: Entity_Lookup = ---;

	if index, ok := pop_safe(&entities_geos.free_entity_records); ok {
		record := &entities_geos.entity_records[index];
		record.entity = entity;
		record.geometry_record_index = geometry_record_index;

		entity_lookup = Entity_Lookup { index, record.generation };
	} else {
		append(&entities_geos.entity_records, Entity_Record {
			entity = entity,
			geometry_record_index = geometry_record_index,
		});

		entity_lookup = Entity_Lookup { len(entities_geos.entity_records) - 1, 0 };
	}

	entity.lookup = entity_lookup;
	
	if geometry_lookup, ok := geometry_lookup.?; ok {
		geometry_record := &entities_geos.geometry_records[geometry_lookup.index];
		append(&geometry_record.entity_lookups, entity_lookup);
	}
	
	return entity_lookup;
}

get_geometry :: proc(lookup: Geometry_Lookup) -> ^Geometry {
	record := &entities_geos.geometry_records[lookup.index];
	assert(lookup.generation == record.generation);

	return &record.geometry;
}

get_entity :: proc(lookup: Entity_Lookup) -> ^Entity {
	record := &entities_geos.entity_records[lookup.index];
	assert(lookup.generation == record.generation);

	return record.entity;
}

remove_geometry :: proc(lookup: Geometry_Lookup) {
	record := &entities_geos.geometry_records[lookup.index];
	assert(lookup.generation == record.generation);

	assert(len(record.entity_lookups) == 0); // We just haven't yet needed to destroy a geometry with entities. Shouldn't be an issue to do.

	delete(record.geometry.indices);
	delete(record.geometry.attributes);

	record.freed = true;
	record.generation += 1;
	append(&entities_geos.free_geometry_records, lookup.index);
}

remove_entity :: proc(entity_lookup: Entity_Lookup) {
	entity_record := &entities_geos.entity_records[entity_lookup.index];
	assert(entity_lookup.generation == entity_record.generation);

	entity := entity_record.entity;
	
	if entity_record.geometry_record_index == -1 do unimplemented();
	geometry_record := &entities_geos.geometry_records[entity_record.geometry_record_index];

	removal_index, ok := slice.linear_search(geometry_record.entity_lookups[:], entity_lookup);
	assert(ok);
	unordered_remove(&geometry_record.entity_lookups, removal_index);

	if len(geometry_record.entity_lookups) == 0 && geometry_record.on_no_entities == .Free {
		delete(geometry_record.geometry.indices);
		delete(geometry_record.geometry.attributes);

		geometry_record.freed = true;
		geometry_record.generation += 1;
		append(&entities_geos.free_geometry_records, entity_record.geometry_record_index);
	}

	#partial switch e in entity.variant {
	case ^Rigid_Body_Entity:
		delete(e.shock_particles);
	}

	for hull in &entity.collision_hulls {
		delete(hull.indices);
		delete(hull.positions);
	}

	delete(entity.collision_hulls);
	free(entity);
	entity_record.generation += 1;
	append(&entities_geos.free_entity_records, entity_lookup.index);
}

cleanup_entities_geos :: proc() {
	for record, i in &entities_geos.geometry_records {
		delete(record.entity_lookups);
		
		if slice.contains(entities_geos.free_geometry_records[:], i) do continue;

		delete(record.geometry.indices);
		delete(record.geometry.attributes);
	}

	delete(entities_geos.geometry_records);
	delete(entities_geos.free_geometry_records);

	for i in 1..<len(entities_geos.entity_records) {
		record := &entities_geos.entity_records[i];
		if slice.contains(entities_geos.free_entity_records[:], i) do continue;

		entity := record.entity;

		for hull in &entity.collision_hulls {
			delete(hull.indices);
			delete(hull.positions);
		}

		delete(entity.collision_hulls);
		free(entity);
	}

	delete(entities_geos.entity_records);
	delete(entities_geos.free_entity_records);
}