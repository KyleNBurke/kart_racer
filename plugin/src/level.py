from bpy.types import Context, Depsgraph, Object, Mesh
import bpy
from . import util

class WObject:
	def __init__(self):
		self.depth: int = None
		self.parent_w_object: WObject = None
		self.object: Object = None
		self.children_w_objects = []
		self.instance_w_object: WObject = None
		self.unique_name = None
		self.final_world_matrix = None

def export(operator, context: Context):
	depsgraph: Depsgraph = context.evaluated_depsgraph_get()
	graph = create_scene_graph(depsgraph)
	debug_export_graph(graph, operator.filepath)

	file = open(operator.filepath, 'wb')

	export_spawn_point(graph, file)
	export_ground_collision_meshes(depsgraph, graph, file)
	mesh_name_to_index_max = export_geometries(depsgraph, graph, file)
	export_inanimate_entities(graph, file, mesh_name_to_index_max)
	export_rigid_bodies(graph, file, mesh_name_to_index_max)

	file.close()
	print("Exported", operator.filepath)
	return {'FINISHED'}

def create_scene_graph(depsgraph: Depsgraph):
	graph = []

	# Find root nodes
	for object in depsgraph.scene.objects:
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

	# Print graph
	print("--- Graph ---")
	to_visit = graph.copy()

	while to_visit:
		w_object: WObject = to_visit.pop()

		for i in range(w_object.depth):
			print("    ", end="")
		
		print(w_object.object.name_full, "(" + w_object.object.kg_type + ")")
		to_visit.extend(w_object.children_w_objects)
	
	print()
	
	return graph

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

def export_spawn_point(graph, file):
	spawn_point_w_object = None
	to_visit = graph.copy()

	while to_visit:
		w_object: WObject = to_visit.pop(0)
		to_visit.extend(w_object.children_w_objects)

		if w_object.object.kg_type == 'spawn_point':
			spawn_point_w_object = w_object
			break
	
	position_game = [0.0, 5.0, 0.0]
	orientation_game = [0.0, 0.0, 0.0, 1.0]
	
	if spawn_point_w_object is None:
		print("No spawn point found")
	else:
		print("Spawn point object:", spawn_point_w_object.unique_name)
		matrix = spawn_point_w_object.object.matrix_world

		position_game = util.blender_position_to_game_position(matrix.to_translation())
		orientation_game = util.blender_orientation_to_game_orientation(matrix.to_quaternion())
	
	print()
	util.write_vec3(file, position_game)
	util.write_quat(file, orientation_game)

def export_ground_collision_meshes(depsgraph: Depsgraph, graph, file):
	print("-- Ground collision meshes ---")

	w_objects = []
	to_visit = graph.copy()

	while to_visit:
		w_object: WObject = to_visit.pop(0)
		to_visit.extend(w_object.children_w_objects)

		if w_object.object.kg_type == 'ground_collision_mesh':
			print(w_object.unique_name)
			w_objects.append(w_object)
	
	print()
	meshes_data = []
	size = 0
	
	for w_object in w_objects:
		indices, positions = util.calculate_indices_global_positions(w_object.final_world_matrix, depsgraph, w_object.object) # Have this (and other) procs just take in the non-eval'd object?
		meshes_data.append((indices, positions))

		for i in range(int(len(positions) / 3)):
			x = positions[i * 3]
			z = positions[i * 3 + 2]

			size = max(size, abs(x))
			size = max(size, abs(z))
	
	print("Grid size:", size)
	print()

	util.write_f32(file, size)
	util.write_u32(file, len(meshes_data))

	for mesh_data in meshes_data:
		indices, positions = mesh_data
		util.write_indices_attributes(file, indices, positions)
		util.write_cursor_check(file)

def export_geometries(depsgraph: Depsgraph, graph, file):
	print("-- Meshes ---")

	w_objects = []
	mesh_name_to_index_map = {}
	mesh_index = 0
	to_visit = graph.copy()

	while to_visit:
		w_object: WObject = to_visit.pop(0)
		to_visit.extend(w_object.children_w_objects)
		object: Object = w_object.object

		kg_type = object.kg_type
		if kg_type == 'inanimate' or kg_type == 'rigid_body':
			mesh: Mesh = object.data

			if mesh.name_full in mesh_name_to_index_map:
				continue

			print(mesh.name_full)

			# We save the w_object and not the mesh because I guess you need to evalutate the object first then get the evalutated mesh from that.
			# So if multiple w_objects all have the same mesh, we just save the first w_object
			w_objects.append(w_object)

			mesh_name_to_index_map[mesh.name_full] = mesh_index
			mesh_index += 1
	
	print()
	util.write_u32(file, len(w_objects))
	
	for w_object in w_objects:
		indices, attributes = util.calculate_indices_local_positions_normals_colors(depsgraph, w_object.object)
		util.write_indices_attributes(file, indices, attributes)
		util.write_cursor_check(file)

	return mesh_name_to_index_map

def export_inanimate_entities(graph, file, mesh_name_to_index_map):
	print("--- Inanimate entities ---")

	w_objects = []
	to_visit = graph.copy()

	while to_visit:
		w_object: WObject = to_visit.pop(0)
		to_visit.extend(w_object.children_w_objects)
		object: Object = w_object.object

		if object.kg_type == 'inanimate':
			print(w_object.unique_name)
			w_objects.append(w_object)
	
	print()
	util.write_u32(file, len(w_objects))

	for w_object in w_objects:
		util.write_game_pos_ori_scale_from_blender_matrix(file, w_object.final_world_matrix)

		mesh_index = mesh_name_to_index_map[w_object.object.data.name_full]
		util.write_u32(file, mesh_index)

		export_hulls(file, w_object)

		util.write_cursor_check(file)

def export_hulls(file, w_object: WObject):
	hull_w_objects = []

	for child_w_object in w_object.children_w_objects:
		if child_w_object.object.kg_type == 'hull':
			hull_w_objects.append(child_w_object)
	
	util.write_u32(file, len(hull_w_objects))

	for hull_w_object in hull_w_objects:
		object = hull_w_object.object
		util.write_game_pos_ori_scale_from_blender_matrix(file, object.matrix_local)

		assert object.kg_hull_type != 'mesh'
		hull_type = None

		match object.kg_hull_type:
			case 'box':
				hull_type = 0
			case 'cylinder':
				hull_type = 1
			case 'mesh':
				hull_type = 2
		
		assert hull_type is not None
		util.write_u32(file, hull_type)

def export_rigid_bodies(graph, file, mesh_name_to_index_map):
	print("--- Rigid body islands ---")
	
	islands = []
	to_visit = graph.copy()

	while to_visit:
		w_object: WObject = to_visit.pop(0)
		object: Object = w_object.object

		if object.kg_type == 'rigid_body_island':
			print(w_object.unique_name)

			rigid_bodies = []
			to_visit_in_island = w_object.children_w_objects.copy()

			while to_visit_in_island:
				w_object_in_island: WObject = to_visit_in_island.pop(0)
				to_visit_in_island.extend(w_object_in_island.children_w_objects)
				object_in_island: Object = w_object_in_island.object

				if object_in_island.kg_type == 'rigid_body':
					print("    " + w_object_in_island.unique_name)
					rigid_bodies.append(w_object_in_island)
			
			assert len(rigid_bodies) > 0, "Rigid body island " + w_object.unique_name + " has no rigid bodies."
			islands.append(rigid_bodies)

		else:
			to_visit.extend(w_object.children_w_objects)
	
	print()
	util.write_u32(file, len(islands))

	for island in islands:
		util.write_u32(file, len(island))

		for w_object in island:
			object: Object = w_object.object
			mesh_index = mesh_name_to_index_map[object.data.name_full]
			game_dimensions = util.blender_scale_to_game_scale(object.dimensions)

			status_effect = None
			match object.kg_rigid_body_status_effect:
				case 'none':
					status_effect = 0
				case 'shock':
					status_effect = 1
			
			util.write_game_pos_ori_scale_from_blender_matrix(file, w_object.final_world_matrix)
			util.write_u32(file, mesh_index)
			util.write_f32(file, object.kg_rigid_body_mass)
			util.write_vec3(file, game_dimensions)
			util.write_b8(file, object.kg_rigid_body_collision_exclude)
			util.write_u32(file, status_effect)
			export_hulls(file, w_object)
			util.write_cursor_check(file)
