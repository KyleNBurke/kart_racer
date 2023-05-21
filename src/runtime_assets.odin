package main;

import "core:math/linalg";

Runtime_Assets :: struct {
	shock_barrel_shrapnel: [dynamic]Shock_Barrel_Shrapnel_Asset,
	oil_slicks: [dynamic]Oil_Slick_Asset,
}

Shock_Barrel_Shrapnel_Asset :: struct {
	geometry_lookup: Geometry_Lookup,
	position: linalg.Vector3f32,
	orientation: linalg.Quaternionf32,
	size: linalg.Vector3f32,
	dimensions: linalg.Vector3f32,
	hull_local_position:    linalg.Vector3f32,
	hull_local_orientation: linalg.Quaternionf32,
	hull_local_size:        linalg.Vector3f32,
}

Oil_Slick_Asset :: struct {
	geometry_lookup: Geometry_Lookup,
	hull_local_position:    linalg.Vector3f32,
	hull_local_orientation: linalg.Quaternionf32,
	hull_local_size:        linalg.Vector3f32,
	hull_indices: [dynamic]u16,
	hull_positions:  [dynamic]f32,
}

cleanup_runtime_assets :: proc(assets: ^Runtime_Assets) {
	delete(assets.shock_barrel_shrapnel);
	
	for oil_slick_asset in &assets.oil_slicks {
		delete(oil_slick_asset.hull_indices);
		delete(oil_slick_asset.hull_positions);
	}

	delete(assets.oil_slicks);
}