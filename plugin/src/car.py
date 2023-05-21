from bpy.types import Context, Depsgraph
from . import util
from .util import WObject

VERSION = 1

def export(operator, context: Context):
	depsgraph: Depsgraph = context.evaluated_depsgraph_get()
	graph = util.create_scene_graph(depsgraph)
	file = open(operator.filepath, 'wb')

	util.write_u32(file, VERSION)
	export_geometry(depsgraph, graph, file)
	export_bottom_hull(graph, file)
	export_upper_dome(graph, file)
	export_wheel(depsgraph, graph, file)
	util.write_cursor_check(file)
	
	file.close()
	print("Exported", operator.filepath)
	return {'FINISHED'}

def export_geometry(depsgraph: Depsgraph, graph, file):
	def compare(w_object: WObject):
		return w_object.object.name == "car"

	car_w_object = util.search_graph_one(graph, compare)
	assert(car_w_object is not None)

	indices, attributes = util.calculate_indices_local_positions_normals_colors(depsgraph, car_w_object.object)
	util.write_indices_attributes(file, indices, attributes)

	util.write_cursor_check(file)

def export_bottom_hull(graph, file):
	def compare(w_object: WObject):
		return w_object.object.name == "bottom_hull"

	hull_w_object = util.search_graph_one(graph, compare)
	assert(hull_w_object is not None)

	util.write_game_pos_ori_scale_from_blender_matrix(file, hull_w_object.object.matrix_local)

def export_upper_dome(graph, file):
	def compare(w_object: WObject):
		return w_object.object.name == "upper_dome"

	hull_w_object = util.search_graph_one(graph, compare)
	assert(hull_w_object is not None)

	util.write_game_pos_ori_scale_from_blender_matrix(file, hull_w_object.object.matrix_local)

def export_wheel(depsgraph: Depsgraph, graph, file):
	def compare(w_object: WObject):
		return w_object.object.name == "wheel"

	wheel_w_object = util.search_graph_one(graph, compare)
	assert(wheel_w_object is not None)

	indices, attributes = util.calculate_indices_local_positions_normals_colors(depsgraph, wheel_w_object.object)
	util.write_indices_attributes(file, indices, attributes)

	radius = wheel_w_object.object.dimensions.z / 2
	util.write_f32(file, radius)

	util.write_cursor_check(file)