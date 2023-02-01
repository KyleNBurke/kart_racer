import struct

POSITION_CHECK_VALUE = 0b10101010_10101010_10101010_10101010

def instance_obj_name(instance_obj):
	if instance_obj.is_instance:
		return  instance_obj.parent.name_full + " -> " + instance_obj.object.name_full
	else:
		return instance_obj.object.name_full

def is_child(parent_instance_obj, candidate_child_instance_obj):
	if parent_instance_obj.is_instance:
		if parent_instance_obj.parent == candidate_child_instance_obj.parent and parent_instance_obj.object == candidate_child_instance_obj.object.parent:
			return True
	else:
		if candidate_child_instance_obj.is_instance:
			if parent_instance_obj.object == candidate_child_instance_obj.parent and candidate_child_instance_obj.object.parent is None:
				return True
		else:
			if parent_instance_obj.object == candidate_child_instance_obj.object.parent:
				return True
	
	return False

def vec3_to_string(v):
	return "(" + str(v[0]) + ", " + str(v[1]) + ", " + str(v[2]) + ")"

def quat_to_string(q):
	return "(" + str(q[0]) + ", " + str(q[1]) + ", " + str(q[2]) + ", " + str(q[3]) + ")"

def write_f32(file, v):
	file.write(struct.pack("<f", v))

def write_vec3(kgl_file, v):
	kgl_file.write(struct.pack("<f", v[0]))
	kgl_file.write(struct.pack("<f", v[1]))
	kgl_file.write(struct.pack("<f", v[2]))

def write_quat(kgl_file, q):
	kgl_file.write(struct.pack("<f", q[0]))
	kgl_file.write(struct.pack("<f", q[1]))
	kgl_file.write(struct.pack("<f", q[2]))
	kgl_file.write(struct.pack("<f", q[3]))

def write_indices_attributes(kgl_file, indices, attributes):
	kgl_file.write(struct.pack("<I", len(indices)))

	for index in indices:
		kgl_file.write(struct.pack("<H", index))
	
	kgl_file.write(struct.pack("<I", len(attributes)))
	
	for attribute in attributes:
		kgl_file.write(struct.pack("<f", attribute))
	
def get_indices_local_positions_normals_colors(mesh):
	mesh.calc_loop_triangles()
	
	vertex_colors = None

	color_attribute = mesh.color_attributes.active_color
	if color_attribute is not None:
		assert color_attribute.domain == 'CORNER', "Cannot export vertex colors of color attribute " + color_attribute.name + " for mesh " + mesh.name_full + " because it is not a face corner color attribute"
		vertex_colors = color_attribute.data
	
	vertex_map = {}
	next_index = 0
	indices = []

	for triangle in mesh.loop_triangles:
		norm = triangle.normal
		norm_game = [norm[0], norm[2], -norm[1]]

		for i in range(3):
			pos_index = triangle.vertices[i]
			pos = mesh.vertices[pos_index].co
			pos_game = [pos[0], pos[2], -pos[1]]

			col_index = triangle.loops[i]
			col = [0.2, 0.2, 0.2]
			if vertex_colors is not None:
				col = vertex_colors[col_index].color

			vertex = (pos_game[0], pos_game[1], pos_game[2], norm_game[0], norm_game[1], norm_game[2], col[0], col[1], col[2])

			if vertex in vertex_map:
				index = vertex_map[vertex]
				indices.append(index)
			else:
				vertex_map[vertex] = next_index
				indices.append(next_index)
				next_index += 1
	
	attributes = []

	for vertex in vertex_map.keys():
		for attribute in vertex:
			attributes.append(attribute)
	
	return indices, attributes

def get_indices_local_positions(mesh):
	mesh.calc_loop_triangles()
	vertex_map = {}
	next_index = 0
	indices = []

	for triangle in mesh.loop_triangles:
		for i in range(3):
			pos_index = triangle.vertices[i]
			pos = mesh.vertices[pos_index].co
			pos_game = [pos[0], pos[2], -pos[1]]

			vertex = (pos_game[0], pos_game[1], pos_game[2])

			if vertex in vertex_map:
				index = vertex_map[vertex]
				indices.append(index)
			else:
				vertex_map[vertex] = next_index
				indices.append(next_index)
				next_index += 1
	
	positions = []

	for vertex in vertex_map.keys():
		for coord in vertex:
			positions.append(coord)
	
	return indices, positions

def get_position_rotation_scale(matrix):
	position = matrix.to_translation()
	position_game = [position[0], position[2], -position[1]]

	rotation = matrix.to_quaternion()
	rotation_game = [rotation[1], rotation[3], -rotation[2], rotation[0]]

	scale = matrix.to_scale()
	scale_game = [scale[0], scale[2], scale[1]]

	return position_game, rotation_game, scale_game

class Hull:
	name = None
	local_position = None
	local_rotation = None
	local_scale = None
	hull_type = None
	indices = None
	positions = None

def get_hulls(parent_instance_obj, instance_objs):
	hulls = []

	for other_instance_obj in instance_objs:
		if other_instance_obj.object.kg_type == 'hull' and is_child(parent_instance_obj, other_instance_obj):
			hull_obj = other_instance_obj.object
			hull = Hull()

			hull.name = instance_obj_name(other_instance_obj)

			position, rotation, scale = get_position_rotation_scale(hull_obj.original.matrix_local)
			hull.local_position = position
			hull.local_rotation = rotation
			hull.local_scale = scale

			if hull_obj.kg_hull_type == 'box':
				hull.hull_type = 0
			elif hull_obj.kg_hull_type == 'cylinder':
				hull.hull_type = 1
			elif hull_obj.kg_hull_type == 'mesh':
				hull.hull_type = 2

				indices, positions = get_indices_local_positions(hull_obj.data)
				hull.indices = indices
				hull.positions = positions
			
			hulls.append(hull)
	
	return hulls