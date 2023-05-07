import struct
import bpy
from bpy.types import Depsgraph, Object, Mesh

class WObject:
	def __init__(self):
		self.depth: int = None
		self.parent_w_object: WObject = None
		self.object: Object = None
		self.children_w_objects = []
		self.instance_w_object: WObject = None
		self.unique_name = None
		self.final_world_matrix = None

def create_scene_graph(depsgraph: Depsgraph):
	graph = []

	# Find root nodes
	for object in depsgraph.scene.objects:
		if object.kg_shared_ignore:
			continue

		if object.parent is None:
			root_w_object = WObject()
			root_w_object.depth = 0
			root_w_object.object = object
			root_w_object.unique_name = object.name_full
			root_w_object.final_world_matrix = object.matrix_world
			graph.append(root_w_object)
	
	# Process root nodes to find the rest of the graph
	w_objects_to_process = graph.copy()

	while w_objects_to_process:
		w_object: WObject = w_objects_to_process.pop()
		object = w_object.object

		# Find the children of this object
		child_objects = None
		instance_collection = object.instance_collection

		if instance_collection is None:
			child_objects = object.children
		else:
			child_objects = []

			for child_object in instance_collection.objects:
				if child_object.parent is None:
					child_objects.append(child_object)

		# Add each child to the graph
		for child_object in child_objects:
			if child_object.kg_shared_ignore:
					continue
			
			child_w_object: WObject = WObject()
			child_w_object.depth = w_object.depth + 1
			child_w_object.parent_w_object = w_object
			child_w_object.object = child_object

			if instance_collection is None:
				child_w_object.instance_w_object = w_object.instance_w_object
			else:
				child_w_object.instance_w_object = w_object
			
			if child_w_object.instance_w_object is None:
				child_w_object.unique_name = child_object.name_full
				child_w_object.final_world_matrix = child_object.matrix_world
			else:
				child_w_object.unique_name = child_w_object.instance_w_object.object.name_full + " -> " + child_object.name_full
				child_w_object.final_world_matrix = child_w_object.instance_w_object.final_world_matrix @ child_object.matrix_world

			w_object.children_w_objects.append(child_w_object)
			w_objects_to_process.append(child_w_object)
	
	return graph

# properties: 0 for level, 1 for runtime assets
def print_graph(graph, properties: int):
	print("--- Graph ---")
	to_visit = graph.copy()

	while to_visit:
		w_object: WObject = to_visit.pop()

		for i in range(w_object.depth):
			print("    ", end="")
		
		t = None
		if properties == 0:
			t = w_object.object.kg_type
		elif properties == 1:
			t = w_object.object.kg_rta_type
		else:
			assert False
		
		print(w_object.object.name_full, "(" + t + ")")
		to_visit.extend(w_object.children_w_objects)
	
	print()

def debug_export_graph(graph, filepath):
	file = open(filepath + ".txt", 'w')
	to_visit = graph.copy()

	while to_visit:
		w_object: WObject = to_visit.pop()

		for i in range(w_object.depth):
			file.write("    ")
		
		file.write(w_object.object.name_full + " (" + w_object.object.kg_type + ")" + "\n")
		to_visit.extend(w_object.children_w_objects)

	file.close()

def iterate_graph(graph, func):
	to_visit = graph.copy()

	while to_visit:
		w_object: WObject = to_visit.pop(0)
		to_visit.extend(w_object.children_w_objects)
		
		func(w_object)

def search_graph(graph, func):
	w_objects = []
	to_visit = graph.copy()

	while to_visit:
		w_object: WObject = to_visit.pop(0)
		to_visit.extend(w_object.children_w_objects)

		if func(w_object):
			w_objects.append(w_object)
	
	return w_objects

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

def write_string(file, v):
	s = bytes(v, 'utf-8')
	file.write(struct.pack("<I%ds" % len(s), len(s), s))

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

def calculate_indices_local_positions(depsgraph: Depsgraph, object: Object):
	eval_object = object.evaluated_get(depsgraph)
	eval_mesh: Mesh = bpy.data.meshes.new_from_object(eval_object)
	eval_mesh.calc_loop_triangles()

	vertex_map = {}
	next_index = 0
	indices = []

	for triangle in eval_mesh.loop_triangles:
		for i in range(3):
			vertex_index = triangle.vertices[i]
			vertex = eval_mesh.vertices[vertex_index].co
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