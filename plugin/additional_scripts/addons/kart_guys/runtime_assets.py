from bpy.types import Context, Depsgraph
from . import util
from .util import WObject

VERSION = 1

def export(operator, context: Context):
	depsgraph: Depsgraph = context.evaluated_depsgraph_get()
	graph = util.create_scene_graph(depsgraph)
	util.print_graph(graph, 1)
	file = open(operator.filepath, 'wb')

	util.write_u32(file, VERSION)

	export_shock_barrel_shrapnel(depsgraph, graph, file)
	export_oil_slicks(depsgraph, graph, file)

	file.close()
	print("Exported", operator.filepath)
	return {'FINISHED'}

def export_shock_barrel_shrapnel(depsgraph: Depsgraph, graph, file):
	print("--- Shock barrel shrapnel ---")

	w_objects = []
	to_visit = graph.copy()

	while to_visit:
		w_object: WObject = to_visit.pop(0)
		to_visit.extend(w_object.children_w_objects)

		if w_object.object.kg_rta_type == 'shock_barrel_shrapnel':
			print(w_object.unique_name)
			w_objects.append(w_object)
	
	print()
	util.write_u32(file, len(w_objects))
	
	for w_object in w_objects:
		object = w_object.object
		indices, attributes = util.calculate_indices_local_positions_normals_colors(depsgraph, object)
		util.write_indices_attributes(file, indices, attributes)
		util.write_game_pos_ori_scale_from_blender_matrix(file, w_object.final_world_matrix)

		game_dimensions = util.blender_scale_to_game_scale(object.dimensions)
		util.write_vec3(file, game_dimensions)

		hull_w_object = None

		for child_w_object in w_object.children_w_objects:
			if child_w_object.object.kg_rta_type == 'hull':
				hull_w_object = child_w_object
		
		assert(hull_w_object is not None)

		hull_object = hull_w_object.object
		util.write_game_pos_ori_scale_from_blender_matrix(file, hull_object.matrix_local)

		util.write_cursor_check(file)

def export_oil_slicks(depsgraph: Depsgraph, graph, file):
	print("--- Oil slicks ---")

	w_objects = []
	to_visit = graph.copy()

	while to_visit:
		w_object: WObject = to_visit.pop(0)
		to_visit.extend(w_object.children_w_objects)

		if w_object.object.kg_rta_type == 'oil_slick':
			print(w_object.unique_name)
			w_objects.append(w_object)
	
	print()
	util.write_u32(file, len(w_objects))

	for w_object in w_objects:
		object = w_object.object
		indices, attributes = util.calculate_indices_local_positions_normals_colors(depsgraph, object)
		util.write_indices_attributes(file, indices, attributes)

		hull_w_object = None

		for child_w_object in w_object.children_w_objects:
			if child_w_object.object.kg_rta_type == 'hull':
				hull_w_object = child_w_object
		
		assert(hull_w_object is not None)

		hull_object = hull_w_object.object
		util.write_game_pos_ori_scale_from_blender_matrix(file, hull_object.matrix_local)

		indices, positions = util.calculate_indices_local_positions(depsgraph, hull_object)
		util.write_indices_attributes(file, indices, positions)

		util.write_cursor_check(file)