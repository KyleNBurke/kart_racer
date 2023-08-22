from bpy.types import Context, Depsgraph, Object, Mesh, Curve, Spline, BezierSplinePoint
from . import util
from .util import WObject

VERSION = 4

def export(operator, context: Context):
	depsgraph: Depsgraph = context.evaluated_depsgraph_get()
	graph = util.create_scene_graph(depsgraph)
	util.print_graph(graph, 0)
	util.debug_export_graph(graph, operator.filepath)
	file = open(operator.filepath, 'wb')

	util.write_u32(file, VERSION)

	export_spawn_point(graph, file)
	export_ground_collision_meshes(depsgraph, graph, file)
	mesh_name_to_index_max = export_geometries(depsgraph, graph, file)
	export_inanimate_entities(graph, file, mesh_name_to_index_max)
	export_rigid_bodies(graph, file, mesh_name_to_index_max)
	export_oil_slicks(depsgraph, graph, file, mesh_name_to_index_max)
	export_bumpers(depsgraph, graph, file, mesh_name_to_index_max)
	export_boost_jets(depsgraph, graph, file, mesh_name_to_index_max)
	export_ai_paths(depsgraph, graph, file)

	file.close()
	print("Exported", operator.filepath)

	write_reload_trigger_file(operator.filepath)

	return {'FINISHED'}

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

		kg_type = w_object.object.kg_type
		if kg_type == 'ground_collision_mesh' or kg_type == 'ground_collision_mesh_and_inanimate':
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

		kg_types = [
			'inanimate',
			'rigid_body',
			'oil_slick',
			'bumper',
			'boost_jet',
			'ground_collision_mesh_and_inanimate'
		]
		
		if object.kg_type in kg_types:
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
		object: Object = w_object.object
		util.write_string(file, object.data.name_full)
		indices, attributes = util.calculate_indices_local_positions_normals_colors(depsgraph, object)
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

		kg_type = w_object.object.kg_type
		if kg_type == 'inanimate' or kg_type == 'ground_collision_mesh_and_inanimate':
			print(w_object.unique_name)
			w_objects.append(w_object)
	
	print()
	util.write_u32(file, len(w_objects))

	for w_object in w_objects:
		util.write_string(file, w_object.unique_name)
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
				case 'fire':
					status_effect = 2
				case 'exploding_shock_barrel':
					status_effect = 3
				case 'exploding_fire_barrel':
					status_effect = 4
			
			assert(status_effect is not None)
			
			util.write_string(file, w_object.unique_name)
			util.write_game_pos_ori_scale_from_blender_matrix(file, w_object.final_world_matrix)
			util.write_u32(file, mesh_index)
			util.write_f32(file, object.kg_rigid_body_mass)
			util.write_vec3(file, game_dimensions)
			util.write_b8(file, object.kg_rigid_body_collision_exclude)
			util.write_u32(file, status_effect)
			export_hulls(file, w_object)
			util.write_cursor_check(file)

def export_oil_slicks(depsgraph: Depsgraph, graph, file, mesh_name_to_index_map):
	print("--- Oil slicks ---")

	w_objects = []
	to_visit = graph.copy()

	while to_visit:
		w_object: WObject = to_visit.pop(0)
		to_visit.extend(w_object.children_w_objects)
		object: Object = w_object.object

		if object.kg_type == 'oil_slick':
			print(w_object.unique_name)
			w_objects.append(w_object)
	
	print()
	util.write_u32(file, len(w_objects))

	for w_object in w_objects:
		util.write_string(file, w_object.unique_name)
		util.write_game_pos_ori_scale_from_blender_matrix(file, w_object.final_world_matrix)

		mesh_index = mesh_name_to_index_map[w_object.object.data.name_full]
		util.write_u32(file, mesh_index)

		util.write_u32(file, w_object.object.kg_oil_slick_particles_count)

		# Find hull
		hull_w_object = None

		for child_w_object in w_object.children_w_objects:
			if child_w_object.object.kg_type == 'hull':
				hull_w_object = child_w_object
				break
		
		# Export hull
		hull_object = hull_w_object.object
		assert hull_object.kg_hull_type == 'mesh'
		util.write_game_pos_ori_scale_from_blender_matrix(file, hull_object.matrix_local)

		indices, positions = util.calculate_indices_local_positions(depsgraph, hull_object)
		util.write_indices_attributes(file, indices, positions)

		util.write_cursor_check(file)

def export_bumpers(depsgraph: Depsgraph, graph, file, mesh_name_to_index_map):
	print("--- Bumpers ---")

	def compare(w_object: WObject):
		return w_object.object.kg_type == 'bumper'
	
	w_objects = util.search_graph_many(graph, compare)

	util.write_u32(file, len(w_objects))

	for w_object in w_objects:
		print(w_object.unique_name)

		util.write_string(file, w_object.unique_name)
		util.write_game_pos_ori_scale_from_blender_matrix(file, w_object.final_world_matrix)

		mesh_index = mesh_name_to_index_map[w_object.object.data.name_full]
		util.write_u32(file, mesh_index)
	
		# Find hull
		hull_w_object = None

		for child_w_object in w_object.children_w_objects:
			if child_w_object.object.kg_type == 'hull':
				hull_w_object = child_w_object
				break
		
		hull_object = hull_w_object.object
		assert hull_object.kg_hull_type == 'cylinder'
		util.write_game_pos_ori_scale_from_blender_matrix(file, hull_object.matrix_local)

		util.write_cursor_check(file)
	
	print()

def export_boost_jets(depsgraph: Depsgraph, graph, file, mesh_name_to_index_map):
	print("--- Boost jets ---")

	def compare(w_object: WObject):
		return w_object.object.kg_type == 'boost_jet'
	
	w_objects = util.search_graph_many(graph, compare)

	util.write_u32(file, len(w_objects))

	for w_object in w_objects:
		print(w_object.unique_name)

		util.write_string(file, w_object.unique_name)
		util.write_game_pos_ori_scale_from_blender_matrix(file, w_object.final_world_matrix)

		mesh_index = mesh_name_to_index_map[w_object.object.data.name_full]
		util.write_u32(file, mesh_index)

		# Find hull
		hull_w_object = None

		for child_w_object in w_object.children_w_objects:
			if child_w_object.object.kg_type == 'hull':
				hull_w_object = child_w_object
				break
		
		hull_object = hull_w_object.object
		assert hull_object.kg_hull_type == 'box'
		util.write_game_pos_ori_scale_from_blender_matrix(file, hull_object.matrix_local)

		util.write_cursor_check(file)
	
	print()

def write_reload_trigger_file(filepath):
	trigger_filepath = filepath + ".reload"

	file = open(trigger_filepath, 'w')
	file.close()
	print("Wrote reload trigger file ", trigger_filepath)

def export_ai_paths(depsgraph: Depsgraph, graph, file):
	print("--- AI paths ---")

	def compare(w_object: WObject):
		return w_object.object.kg_type == 'ideal_path'

	w_object = util.search_graph_one(graph, compare)

	if w_object == None:
		print("No path found")
	else:
		print("Found path", w_object.unique_name)
		curve: Curve = w_object.object.data
		spline: Spline = curve.splines[0]

		util.write_u32(file, (len(spline.bezier_points) - 1) * 3 + 1)
		print((len(spline.bezier_points) - 1) * 3 + 1, "points")

		global_matrix = w_object.object.matrix_world

		for i in range(len(spline.bezier_points) - 1):
			handle_0 = spline.bezier_points[i]
			handle_1 = spline.bezier_points[i + 1]

			pos_0 = util.blender_position_to_game_position(global_matrix @ handle_0.co)
			pos_1 = util.blender_position_to_game_position(global_matrix @ handle_0.handle_right)
			pos_2 = util.blender_position_to_game_position(global_matrix @ handle_1.handle_left)
			
			util.write_vec3(file, pos_0)
			util.write_vec3(file, pos_1)
			util.write_vec3(file, pos_2)

			print(handle_0.co, handle_0.handle_right, handle_1.handle_left)
		
		# If the loop is closed, I don't think we need to write this end point since it's the beginning of the first curve
		handle = spline.bezier_points[-1]
		pos = util.blender_position_to_game_position(global_matrix @ handle.co)
		util.write_vec3(file, pos)

		print(handle.co)
	
	util.write_cursor_check(file)

	print()