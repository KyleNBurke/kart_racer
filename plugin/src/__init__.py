bl_info = {
	"name": "Kart Guys Level Exporter",
	"blender": (3, 2, 0),
	"category": "Import-Export",
	"location": "File > Export > Kart Guys"
}

if "bpy" in locals():
	import importlib
	importlib.reload(util)
	importlib.reload(level)
	importlib.reload(car)
else:
	import bpy

	from bpy_extras.io_utils import ExportHelper

	from . import util
	from . import level
	from . import car

class KartGuysLevelExporter(bpy.types.Operator, ExportHelper):
	bl_idname = "level.kgl"
	bl_label = "Export"

	filename_ext = ".kgl"
	filter_glob: bpy.props.StringProperty(default="*.kgl", options={'HIDDEN'}, maxlen=255)

	def execute(self, context):
		return level.export(self, context)

class KartGuysCarExporter(bpy.types.Operator, ExportHelper):
	bl_idname = "car.kgc"
	bl_label = "Export"

	filename_ext = ".kgc"
	filter_glob: bpy.props.StringProperty(default="*.kgc", options={'HIDDEN'}, maxlen=255)

	def execute(self, context):
		return car.export(self, context)

class KartGuysObjectPanel(bpy.types.Panel):
	bl_idname = 'PROPERTIES_PT_kart_guys_object_panel'
	bl_label = 'Kart Guys Properties'
	bl_space_type = 'PROPERTIES'
	bl_region_type = 'WINDOW'
	bl_context = "object"

	def draw(self, context):
		self.layout.prop(context.object, "kg_type", text="Type")

		kg_type = context.object.kg_type

		if kg_type == 'rigid_body':
			self.layout.prop(context.object, "kg_rigid_body_mass", text="Mass")
			self.layout.prop(context.object, "kg_rigid_body_collision_exclude", text="Collision exclude")
		elif kg_type == 'hull':
			self.layout.prop(context.object, "kg_hull_type", text="Hull type")

def level_exporter_menu_item(self, context):
	self.layout.operator(KartGuysLevelExporter.bl_idname, text="Kart Guys level (.kgl)")

def car_exporter_menu_item(self, context):
	self.layout.operator(KartGuysCarExporter.bl_idname, text="Kart Guys car (.kgc)")

def register():
	bpy.utils.register_class(KartGuysLevelExporter)
	bpy.types.TOPBAR_MT_file_export.append(level_exporter_menu_item)

	bpy.utils.register_class(KartGuysCarExporter)
	bpy.types.TOPBAR_MT_file_export.append(car_exporter_menu_item)

	bpy.utils.register_class(KartGuysObjectPanel)

	bpy.types.Object.kg_type = bpy.props.EnumProperty(items=[
		('none', "None", "", 0),
		('spawn_point', "Spawn point", "", 1),
		('ground_collision_mesh', "Ground collision mesh", "", 2),
		('inanimate', "Inanimate", "", 3),
		('rigid_body_island', "Rigid body island", "", 4),
		('rigid_body', "Rigid body", "", 5),
		('hull', "Hull", "", 6),
		('oil_slick', "Oil slick", "", 7),
		('oil_slick_collision_mesh', "Oil slick collision mesh", "", 8),
		('oil_barrel_mine', "Oil barrel mine", "", 9),
		('oil_barrel_mine_instance', "Oil barrel mine instance", "", 10),
		('oil_barrel_mine_oil_slick', "Oil barrel mine oil slick", "", 11),
		('boost_jet', "Boost jet", "", 12)
	])
	bpy.types.Object.kg_rigid_body_mass = bpy.props.FloatProperty(default = 1.0)
	bpy.types.Object.kg_rigid_body_collision_exclude = bpy.props.BoolProperty()
	bpy.types.Object.kg_hull_type = bpy.props.EnumProperty(items=[
		('box', "Box", "", 0),
		('cylinder', "Cylinder", "", 1),
		('mesh', "Mesh", "", 2)
	])

def unregister():
	bpy.utils.unregister_class(KartGuysLevelExporter)
	bpy.types.TOPBAR_MT_file_export.remove(level_exporter_menu_item)

	bpy.utils.unregister_class(KartGuysCarExporter)
	bpy.types.TOPBAR_MT_file_export.remove(car_exporter_menu_item)

	bpy.utils.unregister_class(KartGuysObjectPanel)

	del bpy.types.Object.kg_type
	del bpy.types.Object.kg_rigid_body_mass
	del bpy.types.Object.kg_rigid_body_collision_exclude
	del bpy.types.Object.kg_hull_type

if __name__ == '__main__':
	register()