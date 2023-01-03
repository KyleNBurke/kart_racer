package entity;

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

		entity_lookup = Entity_Lookup { index, record.generation };
	} else {
		append(&entity_records, Entity_Record {
			entity = entity,
		});

		entity_lookup = Entity_Lookup { len(entity_records) - 1, 0 };
	}

	append(&geometry_record.entity_lookups, entity_lookup);
	return entity_lookup;
}

get_entity :: proc(using entities: ^Entities, $T: typeid, lookup: Entity_Lookup) -> ^T {
	record := &entity_records[lookup.index];
	assert(lookup.generation == record.generation);

	return record.entity.variant.(^T);
}