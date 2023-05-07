package main;

import "core:math";

animate_bumpers :: proc(lookups: []Entity_Lookup, dt: f32) {
	ANIMATION_LENGTH :: 0.8;
	FREQUENCY :: 2;

	for lookup in lookups {
		bumper := get_entity(lookup).variant.(^Bumper_Entity);
		if !bumper.animating do continue;

		if bumper.animation_duration > ANIMATION_LENGTH {
			bumper.animating = false;
			bumper.size.x = 1;
			bumper.size.z = 1;
			update_entity_transform(bumper);

			continue;
		}

		lifetime_multiplier := bumper.animation_duration / ANIMATION_LENGTH;

		shrink := (1 - lifetime_multiplier);
		size := 1 + 0.5 * math.sin(math.TAU * lifetime_multiplier * FREQUENCY) * shrink * shrink;

		bumper.size.x = size;
		bumper.size.z = size;
		update_entity_transform(bumper);

		bumper.animation_duration += dt;
	}
}