package main;

import "core:math";
import "vendor:glfw";

Gamepad :: struct {
	curr_state: glfw.GamepadState,
	prev_state: glfw.GamepadState,
	deadzone_radius: f32,
}

update_gamepad_state :: proc(gamepad: ^Gamepad) {
	gamepad.prev_state = gamepad.curr_state;

	// #todo: Use the gamepad that is getting input.
	glfw.GetGamepadState(glfw.JOYSTICK_1, &gamepad.curr_state);
}

gamepad_button_pressed :: proc(using gamepad: ^Gamepad, button: int) -> bool {
	return prev_state.buttons[button] == 0 && curr_state.buttons[button] == 1;
}

gamepad_button_released :: proc(using gamepad: ^Gamepad, button: int) -> bool {
	return prev_state.buttons[button] == 1 && curr_state.buttons[button] == 0;
}

gamepad_button_held :: proc(using gamepad: ^Gamepad, button: int) -> bool {
	return curr_state.buttons[button] == 1;
}

gamepad_axis_raw_pos :: proc(using gamepad: ^Gamepad, axis: int) -> f32 {
	return curr_state.axes[axis];
}

gamepad_stick_adjusted_pos :: proc(using gamepad: ^Gamepad, axis: int) -> f32 {
	when ODIN_DEBUG {
		assert(axis != glfw.GAMEPAD_AXIS_LEFT_TRIGGER && axis != glfw.GAMEPAD_AXIS_RIGHT_TRIGGER);
	}

	pos := curr_state.axes[axis];

	// Adjust for deadzone
	adjusted: f32 = 0;

	if abs(pos) > deadzone_radius {
		adjusted = -(pos - deadzone_radius * math.sign(pos)) / (1 - deadzone_radius);
	}

	return adjusted;
}

gamepad_trigger_pos :: proc(using gamepad: ^Gamepad, axis: int) -> f32 {
	when ODIN_DEBUG {
		assert(axis == glfw.GAMEPAD_AXIS_LEFT_TRIGGER || axis == glfw.GAMEPAD_AXIS_RIGHT_TRIGGER);
	}

	// Remap to [0, 1]
	return (curr_state.axes[axis] + 1.0) / 2.0;
}