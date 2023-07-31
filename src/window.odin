package main;

import "core:c";
import "core:runtime";
import "vendor:glfw";

Callback_State :: struct {
	framebuffer_size_change: bool,
	minimized: bool,
	window_config_changed: bool,
	game: ^Game,
}

init_window :: proc(window: ^glfw.WindowHandle) {
	assert(glfw.Init() == 1);

	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API);

	if config.window_state == .Maximized {
		glfw.WindowHint(glfw.MAXIMIZED, 1);
	}
	
	window_width := cast(c.int) config.window_width;
	window_height := cast(c.int) config.window_height;
	window^ = glfw.CreateWindow(window_width, window_height, "Kart Guys", nil, nil);
	assert(window != nil);

	if config.window_state == .Normal {
		// In GLFW 3.4, there is a hint for the position we can use
		window_pos_x := cast(c.int) config.window_pos_x;
		window_pos_y := cast(c.int) config.window_pos_y;
		glfw.SetWindowPos(window^, window_pos_x, window_pos_y);
	}

	glfw.SetFramebufferSizeCallback(window^, framebuffer_size_callback);
	glfw.SetWindowPosCallback(window^, pos_callback);
	glfw.SetWindowIconifyCallback(window^, iconify_callback);
	glfw.SetWindowMaximizeCallback(window^, maximized_callback);
	glfw.SetWindowContentScaleCallback(window^, content_scale_callback);
	glfw.SetKeyCallback(window^, key_callback);
}

framebuffer_size_callback : glfw.FramebufferSizeProc : proc "c" (window: glfw.WindowHandle, width, height: c.int) {
	callback_state := cast(^Callback_State) glfw.GetWindowUserPointer(window);
	callback_state.framebuffer_size_change = true
	callback_state.window_config_changed = true;
}

pos_callback : glfw.WindowPosProc : proc "c" (window: glfw.WindowHandle, xpos, ypos: c.int) {
	callback_state := cast(^Callback_State) glfw.GetWindowUserPointer(window);
	callback_state.window_config_changed = true;
}

iconify_callback : glfw.WindowIconifyProc : proc "c" (window: glfw.WindowHandle, iconified: c.int) {
	callback_state := cast(^Callback_State) glfw.GetWindowUserPointer(window);
	callback_state.minimized = iconified == 1 ? true : false;
}

maximized_callback : glfw.WindowMaximizeProc : proc "c" (window: glfw.WindowHandle, maximized: c.int) {
	callback_state := cast(^Callback_State) glfw.GetWindowUserPointer(window);
	callback_state.window_config_changed = true;
}

content_scale_callback : glfw.WindowContentScaleProc : proc "c" (window: glfw.WindowHandle, xscale, yscale: f32) {
	
}

key_callback : glfw.KeyProc : proc "c" (window: glfw.WindowHandle, key, scancode, action, mods: c.int) {
	context = runtime.default_context()
	callback_state := cast(^Callback_State) glfw.GetWindowUserPointer(window);
	game := callback_state.game;

	if action == glfw.PRESS {
		switch key {
		case glfw.KEY_ESCAPE:
			glfw.SetWindowShouldClose(window, true);
		
		case glfw.KEY_F5:
			game.single_stepping = !game.single_stepping;
		
		case glfw.KEY_F6:
			game.step = true;
		
		case glfw.KEY_R:
			// #todo: Since this gets called in a separate thread, weird stuff could happen if for example, the car
			// is in the middle of constraint resolution and it depends on the car's position for correctness. Instead,
			// we should probably flip a boolean requesting the car's position be reset and do it in the main loop.
			// This is really just some debug shit so for now I don't really care.
			respawn_car(game.car, game.scene.spawn_position, game.scene.spawn_orientation);
		}

		camera_handle_key_press(&callback_state.game.camera, key, window);
	}
}