package main;

import "core:fmt";
import "vendor:glfw";
import "render";

main :: proc() {
	/*glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API);

	if glfw.Init() != 1 {
		fmt.println("Failed to initialize GLFW");
		return;
	}

	defer glfw.Terminate();

	window := glfw.CreateWindow(1080, 720, "Kart Guys", nil, nil);
	defer glfw.DestroyWindow(window);

	if window == nil {
		fmt.println("Failed to create window");
		return;
	}*/

	vulkan := render.init_vulkan();

	/*for !glfw.WindowShouldClose(window) {
		glfw.PollEvents();
	}*/
}