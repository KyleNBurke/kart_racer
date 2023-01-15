import struct
from . import util

def export(operator, context):
	depsgraph = context.evaluated_depsgraph_get()
	instance_objs = depsgraph.object_instances

	file = open(operator.filepath, 'wb')

	export_car(file, instance_objs)

	file.close()
	print("Exported", operator.filepath)

	return {'FINISHED'}

def export_car(file, instance_objs):
	for instance_obj in instance_objs:
		if instance_obj.object.name == "car":
			indices, attributes = util.get_indices_local_positions_normals_colors(instance_obj.object.data)
			util.write_indices_attributes(file, indices, attributes)

			hulls = util.get_hulls(instance_obj, instance_objs)
			file.write(struct.pack("<I", len(hulls)))

			for hull in hulls:
				if hull.hull_type == 2:
					assert(False)

				util.write_vec3(file, hull.local_position)
				util.write_quat(file, hull.local_rotation)
				util.write_vec3(file, hull.local_scale)
				file.write(struct.pack("<I", hull.hull_type))
			
			break
	
	file.write(struct.pack("<I", util.POSITION_CHECK_VALUE))