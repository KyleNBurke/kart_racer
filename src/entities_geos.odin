package main;

import "core:slice";
import "core:strings";
import "core:math/linalg";
import "core:fmt";

Entities_Geos :: struct {
	geometries: [dynamic]Geometry,
	free_geometries: [dynamic]int,
	entities: [dynamic]^Entity,
	free_entities: [dynamic]int,
}

Lookup :: struct {
	index: int,
	generation: u32,
}

Geometry_Lookup :: distinct Lookup;
Entity_Lookup :: distinct Lookup;

entities_geos := Entities_Geos {};

create_geometry :: proc(name: string, on_no_entities: On_No_Entities = .Free) -> (geometry: ^Geometry, lookup: Geometry_Lookup) {
	if index, ok := pop_safe(&entities_geos.free_geometries); ok {
		geometry = &entities_geos.geometries[index];
		lookup = { index, geometry.generation };
		
		delete(geometry.name);
		geometry.name = strings.clone(name);
		geometry.free = false;
		geometry.on_no_entities = on_no_entities;
	} else {
		new_geometry := Geometry {
			name = strings.clone(name),
			on_no_entities = on_no_entities,
		};

		append(&entities_geos.geometries, new_geometry);
		index := len(entities_geos.geometries) - 1;

		geometry = &entities_geos.geometries[index];
		lookup = { index, 0 };
	}

	log_verbosef("Created geometry '%s'\n", geometry.name);

	return;
}

create_entity :: proc(name: string, geometry_lookup: Maybe(Geometry_Lookup), $T: typeid) -> (entity: ^T, entity_lookup: Entity_Lookup) {
	entity = new(T);
	entity.variant = entity;
	entity.name = strings.clone(name);

	// Default the position, orientation and size.
	entity.position = VEC3_ZERO;
	entity.orientation = linalg.QUATERNIONF32_IDENTITY;
	entity.size = VEC3_ONE;
	update_entity_transform(entity);

	if index, ok := pop_safe(&entities_geos.free_geometries); ok {
		current_entity := entities_geos.entities[index];
		entity.generation = current_entity.generation;
		free(current_entity);
		entities_geos.entities[index] = entity;

		entity_lookup = { index, entity.generation };
	} else {
		append(&entities_geos.entities, entity);
		index := len(entities_geos.entities) - 1;

		entity_lookup = { index, 0 };
	}

	if lookup, ok := geometry_lookup.?; ok {
		geometry := get_geometry(lookup);

		append(&geometry.entity_lookups, entity_lookup);
		entity.geometry_lookup = lookup;
	}

	log_verbosef("Created entity '%s'\n", entity.name);

	return;
}

remove_scene_associated_entities :: proc() {
	for entity, index in entities_geos.entities {
		if entity.free || !entity.scene_associated do continue;

		lookup := Entity_Lookup { index, entity.generation };
		remove_entity(lookup);
	}
}

get_geometry :: proc(lookup: Geometry_Lookup) -> ^Geometry {
	geometry := &entities_geos.geometries[lookup.index];
	assert(lookup.generation == geometry.generation);

	return geometry;
}

get_entity :: proc(lookup: Entity_Lookup) -> ^Entity {
	entity := entities_geos.entities[lookup.index];
	assert(lookup.generation == entity.generation);

	return entity;
}

remove_geometry :: proc(geometry_lookup: Geometry_Lookup) {
	geometry := get_geometry(geometry_lookup);

	entity_lookups_count := len(geometry.entity_lookups);
	assert(entity_lookups_count == 0, fmt.tprintf("Cannot remove geometry '%s', it has %v entities.", geometry.name, entity_lookups_count));

	geometry.free = true;
	geometry.generation += 1;
	append(&entities_geos.free_geometries, geometry_lookup.index);

	log_verbosef("Removed geometry '%s'\n", geometry.name);
}

// @(private="file")
remove_entity :: proc(entity_lookup: Entity_Lookup) {
	entity := get_entity(entity_lookup);

	// Remove the entity_lookup from the associated geometry
	if geometry_lookup, ok := entity.geometry_lookup.?; ok {
		geometry := get_geometry(geometry_lookup);
		entity_lookups := &geometry.entity_lookups;

		removal_index, found := slice.linear_search(entity_lookups[:], entity_lookup);
		assert(found);
		unordered_remove(entity_lookups, removal_index);

		// If we removed the last entity from the geometry, free it if needed
		if len(entity_lookups) == 0 && geometry.on_no_entities == .Free {
			geometry.free = true;
			geometry.generation += 1;
			append(&entities_geos.free_geometries, geometry_lookup.index);

			log_verbosef("Removed geometry '%s'\n", geometry.name);
		}
	}

	// Free the entity resources. Note, we do not free the actual entity here because we need to reference the freed and generation variables.
	// The generation variable is used in the create_entity proc.
	for &hull in entity.collision_hulls {
		delete(hull.indices);
		delete(hull.positions);
	}

	entity_name := strings.clone(entity.name, context.temp_allocator);

	delete(entity.name);
	delete(entity.collision_hulls);
	entity.free = true;
	entity.generation += 1;
	append(&entities_geos.free_entities, entity_lookup.index);

	// Free the variant specific resources.
	switch variant in entity.variant {
	case ^Rigid_Body_Entity:
		delete(variant.shock_particles);
		delete(variant.fire_particles);
	case ^Car_Entity:
		delete(variant.shock_particles);
		delete(variant.fire_particles);
	case ^Cloud_Entity:
		delete(variant.particles);
	case ^Oil_Slick_Entity:
		delete(variant.fire_particles);
	case ^Boost_Jet_Entity:
		delete(variant.particles);
	case ^Inanimate_Entity, ^Bumper_Entity:
	}
	
	log_verbosef("Removed entity '%s'\n", entity_name);
}

cleanup_entities_geos :: proc() {
	for &geometry in entities_geos.geometries {
		// Freed or not, we must delete the inner resources
		delete(geometry.name)
		delete(geometry.entity_lookups);
		delete(geometry.indices);
		delete(geometry.attributes);
	}

	delete(entities_geos.geometries);
	delete(entities_geos.free_geometries);

	for entity in entities_geos.entities {
		// If the entity has been marked free, then we've already deleted the inner resources.
		if entity.free {
			free(entity);
			continue
		};

		delete(entity.name);
		delete(entity.collision_hulls);

		switch variant in entity.variant {
		case ^Rigid_Body_Entity:
			delete(variant.fire_particles);
			delete(variant.shock_particles);
			
		case ^Oil_Slick_Entity:
			delete(variant.fire_particles);

		case ^Cloud_Entity:
			delete(variant.particles);
		
		case ^Car_Entity:
			delete(variant.shock_particles);
			delete(variant.fire_particles);
			
		case ^Boost_Jet_Entity:
			delete(variant.particles);

		case ^Inanimate_Entity, ^Bumper_Entity:
		}

		free(entity);
	}

	delete(entities_geos.entities);
	delete(entities_geos.free_entities);
}