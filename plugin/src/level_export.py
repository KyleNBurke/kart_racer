import struct
from . import util

def export(operator, context):
	depsgraph = context.evaluated_depsgraph_get()
	instance_objs = depsgraph.object_instances

	# print("Instance objects:")
	# for instance_obj in instance_objs:
	# 	print(util.instance_obj_name(instance_obj))
	# print("-------------------------")

	kgl_filepath = operator.filepath
	txt_filepath = operator.filepath + ".txt"

	kgl_file = open(kgl_filepath, 'wb')
	txt_file = open(txt_filepath, 'w')

	export_spawn_point(kgl_file, txt_file, instance_objs)
	export_ground_collision_meshes(kgl_file, txt_file, instance_objs)
	mesh_name_to_index_map = export_geometries(kgl_file, txt_file, instance_objs)
	export_inanimate_entities(kgl_file, txt_file, instance_objs, mesh_name_to_index_map)
	export_rigid_body_islands(kgl_file, txt_file, instance_objs, mesh_name_to_index_map)

	kgl_file.close()
	print("Exported", kgl_filepath)

	txt_file.close()
	print("Exported", txt_filepath)

	return {'FINISHED'}

def export_spawn_point(kgl_file, txt_file, instance_objs):
	name = None
	position_game = [0.0, 5.0, 0.0]
	rotation_game = [0.0, 0.0, 0.0, 1.0]

	for instance_obj in instance_objs:
		if instance_obj.object.kg_type == 'spawn_point':
			name = util.instance_obj_name(instance_obj)

			position = instance_obj.matrix_world.to_translation()
			position_game = [position[0], position[2], -position[1]]

			rotation = instance_obj.matrix_world.to_quaternion()
			rotation_game = [rotation[1], rotation[3], -rotation[2], rotation[0]]

			break
	
	txt_file.write("Spawn point: " + str(name) + "\n")
	util.write_vec3(kgl_file, position_game)
	util.write_quat(kgl_file, rotation_game)
	
	txt_file.write("\tposition: " + util.vec3_to_string(position_game) + "\n")
	txt_file.write("\trotation: " + util.quat_to_string(rotation_game) + "\n")
	txt_file.write("\n")

def export_ground_collision_meshes(kgl_file, txt_file, instance_objs):
	class Ground:
		name = None
		indices = None
		positions = None
	
	size = 0
	grounds = []

	for instance_obj in instance_objs:
		if instance_obj.object.kg_type == 'ground_collision_mesh':
			mesh = instance_obj.object.data
			mesh.calc_loop_triangles()

			vertex_map = {}
			next_index = 0
			indices = []

			for triangle in mesh.loop_triangles:
				for i in range(3):
					vertex_index = triangle.vertices[i]
					vertex = instance_obj.matrix_world @ mesh.vertices[vertex_index].co
					vertex_game = (vertex[0], vertex[2], -vertex[1])

					size = max(size, abs(vertex_game[0]))
					size = max(size, abs(vertex_game[2]))

					if vertex_game in vertex_map:
						index = vertex_map[vertex_game]
						indices.append(index)
					else:
						vertex_map[vertex_game] = next_index
						indices.append(next_index)
						next_index += 1
			
			positions = []

			for vertex in vertex_map.keys():
				for coord in vertex:
					positions.append(coord)
			
			ground = Ground()
			ground.name = util.instance_obj_name(instance_obj);
			ground.indices = indices
			ground.positions = positions
			
			grounds.append(ground)
	
	txt_file.write("Ground grid size: " + str(size) + "\n")
	txt_file.write("Ground collision meshes: " + str(len(grounds)) + "\n")

	kgl_file.write(struct.pack("<f", size))
	kgl_file.write(struct.pack("<I", len(grounds)))

	for g in grounds:
		util.write_indices_attributes(kgl_file, txt_file, g.indices, g.positions, g.name)

	txt_file.write("\n")

def export_geometries(kgl_file, txt_file, instance_objs):
	class Geometry:
		name = None
		indices = None
		attributes = None

	geometries = []
	mesh_name_to_index_map = {}
	mesh_index = 0

	for instance_obj in instance_objs:
		obj = instance_obj.object
		kg_type = obj.kg_type

		if kg_type == 'inanimate' or kg_type == 'rigid_body' or kg_type == 'oil_slick' or kg_type == 'oil_barrel_mine' or kg_type == 'oil_barrel_mine_oil_slick':
			assert obj.type == 'MESH', util.instance_obj_name(instance_obj) + " is marked to have it's mesh exported yet it's not a mesh object"

			mesh = obj.data

			if mesh.name_full in mesh_name_to_index_map:
				continue

			indices, attributes = util.get_indices_local_positions_normals_colors(mesh)

			mesh_name_to_index_map.update({ mesh.name_full: mesh_index })
			mesh_index += 1

			geometry = Geometry()
			geometry.name = mesh.name_full
			geometry.indices = indices
			geometry.attributes = attributes
			geometries.append(geometry)
	
	txt_file.write("Geometries: " + str(mesh_index) + "\n")
	kgl_file.write(struct.pack("<I", len(geometries)))

	for g in geometries:
		util.write_indices_attributes(kgl_file, txt_file, g.indices, g.attributes, g.name)
	
	txt_file.write("\n")
	
	return mesh_name_to_index_map

def export_inanimate_entities(kgl_file, txt_file, instance_objs, mesh_name_to_index_map):
	class Entity:
		name = None
		position = None
		rotation = None
		scale = None
		mesh_index = None
		hulls = None
	
	entities = []

	for instance_obj in instance_objs:
		if instance_obj.object.kg_type == 'inanimate':
			entity = Entity()
			entity.name = util.instance_obj_name(instance_obj)

			position, rotation, scale = util.get_position_rotation_scale(instance_obj.matrix_world)
			entity.position = position
			entity.rotation = rotation
			entity.scale = scale

			entity.mesh_index = mesh_name_to_index_map[instance_obj.object.data.name_full]
			entity.hulls = util.get_hulls(instance_obj, instance_objs)

			entities.append(entity)
	
	txt_file.write("Inanimate entities: " + str(len(entities)) + "\n")
	kgl_file.write(struct.pack("<I", len(entities)))

	for entity in entities:
		txt_file.write("\t" + entity.name + "\n")
		txt_file.write("\t\tposition: " + util.vec3_to_string(entity.position) + "\n")
		txt_file.write("\t\trotation: " + util.quat_to_string(entity.rotation) + "\n")
		txt_file.write("\t\tscale:    " + util.vec3_to_string(entity.scale) + "\n")
		txt_file.write("\t\tgeometry index: " + str(entity.mesh_index) + "\n")
		
		util.write_vec3(kgl_file, entity.position)
		util.write_quat(kgl_file, entity.rotation)
		util.write_vec3(kgl_file, entity.scale)
		kgl_file.write(struct.pack("<I", entity.mesh_index))

		txt_file.write("\t\thulls: " + str(len(entity.hulls)) + "\n")
		kgl_file.write(struct.pack("<I", len(entity.hulls)))

		for hull in entity.hulls:
			txt_file.write("\t\t\t" + hull.name + "\n")
			txt_file.write("\t\t\t\tlocal position: " + util.vec3_to_string(hull.local_position) + "\n")
			txt_file.write("\t\t\t\tlocal rotation: " + util.quat_to_string(hull.local_rotation) + "\n")
			txt_file.write("\t\t\t\tlocal scale:    " + util.vec3_to_string(hull.local_scale) + "\n")
			txt_file.write("\t\t\t\ttype: " + str(hull.hull_type) + "\n")

			if hull.hull_type == 2:
				assert(False)

			util.write_vec3(kgl_file, hull.local_position)
			util.write_quat(kgl_file, hull.local_rotation)
			util.write_vec3(kgl_file, hull.local_scale)
			kgl_file.write(struct.pack("<I", hull.hull_type))

	txt_file.write("\n")

def export_rigid_body_islands(kgl_file, txt_file, instance_objs, mesh_name_to_index_map):
	class Island:
		bodies = None
	
	class RigidBody:
		name = None
		position = None
		rotation = None
		scale = None
		mesh_index = None
		hulls = None
		mass = None
		dimensions = None
		collision_exclude = None
	
	islands = []
	
	for instance_obj in instance_objs:
		if instance_obj.object.kg_type == 'rigid_body_island':
			island = Island()
			island.bodies = []

			for other_instance_obj in instance_objs:
				if other_instance_obj.object.kg_type == 'rigid_body' and util.is_child(instance_obj, other_instance_obj):
					body = RigidBody()
					body.name = util.instance_obj_name(instance_obj)

					position, rotation, scale = util.get_position_rotation_scale(other_instance_obj.matrix_world)
					body.position = position
					body.rotation = rotation
					body.scale = scale
					
					body.mesh_index = mesh_name_to_index_map[other_instance_obj.object.data.name_full]
					body.hulls = util.get_hulls(other_instance_obj, instance_objs)
					
					obj = other_instance_obj.object
					body.mass = obj.kg_rigid_body_mass
					dimensions = obj.dimensions
					body.dimensions = [dimensions[0], dimensions[2], dimensions[1]]
					body.collision_exclude = obj.kg_rigid_body_collision_exclude

					island.bodies.append(body)

			islands.append(island)
	
	txt_file.write("Rigid body islands: " + str(len(islands)) + "\n")
	kgl_file.write(struct.pack("<I", len(islands)))

	for island in islands:
		txt_file.write("\tBodies: " + str(len(island.bodies)) + "\n")
		kgl_file.write(struct.pack("<I", len(island.bodies)))

		for body in island.bodies:
			txt_file.write("\t\t" + body.name + "\n")
			txt_file.write("\t\t\tposition: " + util.vec3_to_string(body.position) + "\n")
			txt_file.write("\t\t\trotation: " + util.quat_to_string(body.rotation) + "\n")
			txt_file.write("\t\t\tscale:    " + util.vec3_to_string(body.scale) + "\n")
			txt_file.write("\t\t\tgeometry index: " + str(body.mesh_index) + "\n")

			util.write_vec3(kgl_file, body.position)
			util.write_quat(kgl_file, body.rotation)
			util.write_vec3(kgl_file, body.scale)
			kgl_file.write(struct.pack("<I", body.mesh_index))

			txt_file.write("\t\t\thulls: " + str(len(body.hulls)) + "\n")
			kgl_file.write(struct.pack("<I", len(body.hulls)))

			for hull in body.hulls:
				txt_file.write("\t\t\t\t" + hull.name + "\n")
				txt_file.write("\t\t\t\t\tlocal position: " + util.vec3_to_string(hull.local_position) + "\n")
				txt_file.write("\t\t\t\t\tlocal rotation: " + util.quat_to_string(hull.local_rotation) + "\n")
				txt_file.write("\t\t\t\t\tlocal scale:    " + util.vec3_to_string(hull.local_scale) + "\n")
				txt_file.write("\t\t\t\t\ttype: " + str(hull.hull_type) + "\n")

				if hull.hull_type == 2:
					assert(False)

				util.write_vec3(kgl_file, hull.local_position)
				util.write_quat(kgl_file, hull.local_rotation)
				util.write_vec3(kgl_file, hull.local_scale)
				kgl_file.write(struct.pack("<I", hull.hull_type))
			
			txt_file.write("\t\t\tmass: " + str(body.mass) + "\n")
			txt_file.write("\t\t\tdimensions: " + util.vec3_to_string(body.dimensions) + "\n")
			txt_file.write("\t\t\tcollision_exclude: " + str(body.collision_exclude) + "\n")

			kgl_file.write(struct.pack("<f", body.mass))
			util.write_vec3(kgl_file, body.dimensions)
			kgl_file.write(struct.pack("<?", body.collision_exclude))
	
	txt_file.write("\n")