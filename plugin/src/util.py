import struct
import bpy
from bpy.types import Depsgraph, Object, Mesh

def blender_position_to_game_position(pos):
	return (pos[0], pos[2], -pos[1])

def blender_orientation_to_game_orientation(ori):
	return (ori[1], ori[3], -ori[2], ori[0])

def blender_scale_to_game_scale(scale):
	return (scale[0], scale[2], scale[1])

def write_b8(file, v):
	file.write(struct.pack("<?", v))

def write_u16(file, v):
	file.write(struct.pack("<H", v))

def write_u32(file, v):
	file.write(struct.pack("<I", v))

def write_f32(file, v):
	file.write(struct.pack("<f", v))

def write_cursor_check(file):
	file.write(struct.pack("<I", 0b10101010_10101010_10101010_10101010))

def write_vec3(file, vec):
	write_f32(file, vec[0])
	write_f32(file, vec[1])
	write_f32(file, vec[2])

def write_quat(file, quat):
	write_f32(file, quat[0])
	write_f32(file, quat[1])
	write_f32(file, quat[2])
	write_f32(file, quat[3])

def write_game_pos_ori_scale_from_blender_matrix(file, matrix):
	game_pos = blender_position_to_game_position(matrix.to_translation())
	game_ori = blender_orientation_to_game_orientation(matrix.to_quaternion())
	game_scale = blender_scale_to_game_scale(matrix.to_scale())

	write_vec3(file, game_pos)
	write_quat(file, game_ori)
	write_vec3(file, game_scale)

def write_indices_attributes(file, indices, attributes):
	write_u32(file, len(indices))

	for index in indices:
		write_u16(file, index)
	
	write_u32(file, len(attributes))

	for attribute in attributes:
		write_f32(file, attribute)

def calculate_indices_global_positions(matrix, depsgraph: Depsgraph, object: Object):
	eval_object = object.evaluated_get(depsgraph)
	eval_mesh: Mesh = bpy.data.meshes.new_from_object(eval_object)
	eval_mesh.calc_loop_triangles()

	vertex_map = {}
	next_index = 0
	indices = []

	for triangle in eval_mesh.loop_triangles:
		for i in range(3):
			vertex_index = triangle.vertices[i]
			vertex = matrix @ eval_mesh.vertices[vertex_index].co
			vertex_game = blender_position_to_game_position(vertex)

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
	
	return indices, positions

def calculate_indices_local_positions_normals_colors(depsgraph: Depsgraph, object: Object):
	eval_object = object.evaluated_get(depsgraph)
	eval_mesh: Mesh = bpy.data.meshes.new_from_object(eval_object)
	eval_mesh.calc_loop_triangles()
	vertex_colors = None

	color_attribute = eval_mesh.color_attributes.active_color
	if color_attribute is not None:
		assert color_attribute.domain == 'CORNER', "Cannot export vertex colors of color attribute " + color_attribute.name + " for mesh " + eval_mesh.name_full + " because it is not a face corner color attribute"
		vertex_colors = color_attribute.data
	
	vertex_map = {}
	next_index = 0
	indices = []

	for triangle in eval_mesh.loop_triangles:
		norm = triangle.normal
		norm_game = [norm[0], norm[2], -norm[1]]

		for i in range(3):
			pos_index = triangle.vertices[i]
			pos = eval_mesh.vertices[pos_index].co
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