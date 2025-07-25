bl_info = {
	"name": "Kart Guys Level Exporter",
	"blender": (3, 2, 0),
	"category": "Import-Export",
	"location": "File > Export > Kart Guys"
}

if "bpy" in locals():
	import importlib

	if "util" in locals():
		importlib.reload(util)
	
	if "level" in locals():
		importlib.reload(level)
	
	if "runtime_assets" in locals():
		importlib.reload(runtime_assets)
	
	if "car" in locals():
		importlib.reload(car)

import bpy
from bpy_extras.io_utils import ExportHelper
from . import util, level, runtime_assets, car

class KartGuysLevelExporter(bpy.types.Operator, ExportHelper):
	bl_idname = "level.kgl"
	bl_label = "Export"

	filename_ext = ".kgl"
	filter_glob: bpy.props.StringProperty(default="*.kgl", options={'HIDDEN'}, maxlen=255)

	def execute(self, context):
		return level.export(self, context)

class KartGuysRuntimeAssetsExporter(bpy.types.Operator, ExportHelper):
	bl_idname = "level.kga"
	bl_label = "Export"

	filename_ext = ".kga"
	filter_glob: bpy.props.StringProperty(default="*.kga", options={'HIDDEN'}, maxlen=255)

	def execute(self, context):
		return runtime_assets.export(self, context)

class KartGuysCarExporter(bpy.types.Operator, ExportHelper):
	bl_idname = "level.kgc"
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
		self.layout.prop(context.object, "kg_shared_ignore", text="Ignore")
		self.layout.prop(context.object, "kg_type", text="Type")

		kg_type = context.object.kg_type

		if kg_type == 'rigid_body':
			self.layout.prop(context.object, "kg_rigid_body_mass", text="Mass")
			self.layout.prop(context.object, "kg_rigid_body_collision_exclude", text="Collision exclude")
			self.layout.prop(context.object, "kg_rigid_body_status_effect", text="Status effect")
		elif kg_type == 'hull':
			self.layout.prop(context.object, "kg_hull_type", text="Hull type")
		elif kg_type == 'oil_slick':
			self.layout.prop(context.object, "kg_oil_slick_particles_count", text="Particles")

class KartGuysRuntimeAssetsPanel(bpy.types.Panel):
	bl_idname = 'PROPERTIES_PT_kart_guys_runtime_assets_panel'
	bl_label = 'Kart Guys Runtime Assets Properties'
	bl_space_type = 'PROPERTIES'
	bl_region_type = 'WINDOW'
	bl_context = "object"

	def draw(self, context):
		self.layout.prop(context.object, "kg_shared_ignore", text="Ignore")
		self.layout.prop(context.object, "kg_rta_type", text="Type")

def level_exporter_menu_item(self, context):
	self.layout.operator(KartGuysLevelExporter.bl_idname, text="Kart Guys level (.kgl)")

def runtime_assets_exporter_menu_item(self, context):
	self.layout.operator(KartGuysRuntimeAssetsExporter.bl_idname, text="Kart Guys runtime assets (.kga)")

def car_exporter_menu_item(self, context):
	self.layout.operator(KartGuysCarExporter.bl_idname, text="Kart Guys car (.kgc)")

def register():
	# Level
	bpy.utils.register_class(KartGuysLevelExporter)
	bpy.types.TOPBAR_MT_file_export.append(level_exporter_menu_item)

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
		('bumper', "Bumpler", "", 8),
		('boost_jet', "Boost jet", "", 9),
		('ground_collision_mesh_and_inanimate', "Ground collision mesh and inanimate", "", 10),
		('removed', "REMOVED", "", 11),
		('ai_spawn_point', "AI spawn point", "", 12),
		('ai_path_left', "AI path left", "", 13),
		('ai_path_right', "AI path right", "", 14),
	])
	bpy.types.Object.kg_hull_type = bpy.props.EnumProperty(items=[
		('box', "Box", "", 0),
		('cylinder', "Cylinder", "", 1),
		('mesh', "Mesh", "", 2)
	])
	bpy.types.Object.kg_rigid_body_mass = bpy.props.FloatProperty(default = 1.0)
	bpy.types.Object.kg_rigid_body_collision_exclude = bpy.props.BoolProperty()
	bpy.types.Object.kg_rigid_body_status_effect = bpy.props.EnumProperty(items=[
		('none', "None", "", 0),
		('shock', "Shock", "", 1),
		('fire', "Fire", "", 2),
		('exploding_shock_barrel', "Exploding shock barrel", "", 3),
		('exploding_fire_barrel', "Exploding fire barrel", "", 4)
	])
	bpy.types.Object.kg_oil_slick_particles_count = bpy.props.IntProperty(default=10)

	# Runtime assets
	bpy.utils.register_class(KartGuysRuntimeAssetsExporter)
	bpy.types.TOPBAR_MT_file_export.append(runtime_assets_exporter_menu_item)
	
	bpy.utils.register_class(KartGuysRuntimeAssetsPanel)

	bpy.types.Object.kg_shared_ignore = bpy.props.BoolProperty()
	bpy.types.Object.kg_rta_type = bpy.props.EnumProperty(items=[
		('none', "None", "", 0),
		('shock_barrel_shrapnel', "Shock barrel shrapnel", "", 1),
		('hull', "Hull", "", 2),
		('oil_slick', "Oil slick", "", 3)
	])

	# Car
	bpy.utils.register_class(KartGuysCarExporter)
	bpy.types.TOPBAR_MT_file_export.append(car_exporter_menu_item)

def unregister():
	# Level
	bpy.utils.unregister_class(KartGuysLevelExporter)
	bpy.types.TOPBAR_MT_file_export.remove(level_exporter_menu_item)

	bpy.utils.unregister_class(KartGuysObjectPanel)

	del bpy.types.Object.kg_type
	del bpy.types.Object.kg_hull_type
	del bpy.types.Object.kg_rigid_body_mass
	del bpy.types.Object.kg_rigid_body_collision_exclude
	del bpy.types.Object.kg_rigid_body_status_effect

	# Runtime assets
	bpy.utils.unregister_class(KartGuysRuntimeAssetsExporter)
	bpy.types.TOPBAR_MT_file_export.remove(runtime_assets_exporter_menu_item)
	
	bpy.utils.unregister_class(KartGuysRuntimeAssetsPanel)

	del bpy.types.Object.kg_shared_ignore
	del bpy.types.Object.kg_rta_type

	# Car
	bpy.utils.unregister_class(KartGuysCarExporter)
	bpy.types.TOPBAR_MT_file_export.remove(car_exporter_menu_item)

if __name__ == '__main__':
	register()