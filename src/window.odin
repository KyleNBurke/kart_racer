package main;

import "core:c";
import "core:runtime";
import "vendor:glfw";

Callback_State :: struct {
	framebuffer_size_change: bool,
	minimized: bool,
	config_changed: bool,
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

	glfw.SetFramebufferSizeCallback(window^, framebuffer_size_callback);
	glfw.SetWindowIconifyCallback(window^, iconify_callback);
	glfw.SetWindowMaximizeCallback(window^, maximized_callback);
	glfw.SetWindowContentScaleCallback(window^, content_scale_callback);
	glfw.SetKeyCallback(window^, key_callback);
}

framebuffer_size_callback : glfw.FramebufferSizeProc : proc "c" (window: glfw.WindowHandle, width, height: c.int) {
	callback_state := cast(^Callback_State) glfw.GetWindowUserPointer(window);
	callback_state.framebuffer_size_change = true;
	
	context = runtime.default_context();
	config.window_width = int(width);
	config.window_height = int(height);

	callback_state.config_changed = true;
}

iconify_callback : glfw.WindowIconifyProc : proc "c" (window: glfw.WindowHandle, iconified: c.int) {
	callback_state := cast(^Callback_State) glfw.GetWindowUserPointer(window);
	callback_state.minimized = iconified == 1 ? true : false;
}

maximized_callback : glfw.WindowMaximizeProc : proc "c" (window: glfw.WindowHandle, maximized: c.int) {
	context = runtime.default_context();
	config.window_state = maximized == 1 ? .Maximized : .Normal;
	
	callback_state := cast(^Callback_State) glfw.GetWindowUserPointer(window);
	callback_state.config_changed = true;
}

content_scale_callback : glfw.WindowContentScaleProc : proc "c" (window: glfw.WindowHandle, xscale, yscale: f32) {
	
}

key_callback : glfw.KeyProc : proc "c" (window: glfw.WindowHandle, key, scancode, action, mods: c.int) {
	context = runtime.default_context()
	callback_state := cast(^Callback_State) glfw.GetWindowUserPointer(window);

	if action == glfw.PRESS {
		switch key {
			case glfw.KEY_ESCAPE:
				glfw.SetWindowShouldClose(window, true);
		}

		camera_handle_key_press(&callback_state.game.camera, key, window);
	}
}