package entity;

Entities :: struct {
	geometry_records: [dynamic]GeometryRecord,
}

GeometryRecord :: struct {
	geometry: Geometry,
	entities: [dynamic]Entity,
}

init_entites :: proc() -> Entities {
	return Entities {};
}

add_geometry :: proc(using entities: ^Entities, geometry: Geometry) -> int {
	record := GeometryRecord {
		geometry,
		make([dynamic]Entity),
	};

	append(&geometry_records, record);
	return len(geometry_records) - 1;
}

add_entity :: proc(using entities: ^Entities, geometry_record: int, entity: Entity) {
	append(&geometry_records[geometry_record].entities, entity);
}