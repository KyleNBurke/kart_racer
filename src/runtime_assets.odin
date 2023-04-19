package main;

import "core:math/linalg";

Runtime_Assets :: struct {
	cloud_hull_transform: linalg.Matrix4f32,
	shock_barrel_shrapnel: [dynamic]Shock_Barrel_Shrapnel,
}

Shock_Barrel_Shrapnel :: struct {
	geometry_lookup: Geometry_Lookup,
	position: linalg.Vector3f32,
	orientation: linalg.Quaternionf32,
	size: linalg.Vector3f32,
	dimensions: linalg.Vector3f32,
	hull_local_transform: linalg.Matrix4f32,
}

cleanup_runtime_assets :: proc(assets: ^Runtime_Assets) {
	delete(assets.shock_barrel_shrapnel);
}