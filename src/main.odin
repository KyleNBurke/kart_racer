package main;

import "core:fmt";
import "core:c";
import "vendor:glfw";
import "render";

main :: proc() {
	fmt.assertf(glfw.Init() == 1, "Failed to initialize GLFW");
	defer glfw.Terminate();

	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API);
	window := glfw.CreateWindow(1080, 720, "Kart Guys", nil, nil);
	fmt.assertf(window != nil, "Failed to create window");
	defer glfw.DestroyWindow(window);

	glfw.SetKeyCallback(window, key_callback);
	glfw.SetFramebufferSizeCallback(window, framebuffer_size_callback);
	glfw.SetWindowContentScaleCallback(window, content_scale_callback);

	vulkan := render.init_vulkan(window);
	defer render.cleanup_vulkan(&vulkan);

	for !glfw.WindowShouldClose(window) {
		glfw.PollEvents();
	}
}

key_callback : glfw.KeyProc : proc "c" (window: glfw.WindowHandle, key, scancode, action, mods: i32) {
	switch key {
		case glfw.KEY_ESCAPE:
			glfw.SetWindowShouldClose(window, true);
	}
}

framebuffer_size_callback : glfw.FramebufferSizeProc : proc "c" (window: glfw.WindowHandle, width, height: i32) {
	
}

content_scale_callback : glfw.WindowContentScaleProc : proc "c" (window: glfw.WindowHandle, xscale, yscale: f32) {
	
}