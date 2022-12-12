package render;

import "core:fmt";
import "core:os";
import "core:runtime";
import "vendor:glfw";
import vk "vendor:vulkan";

REQUIRED_DEBUG_INSTANCE_EXTENSIONS := [?]cstring {"VK_EXT_debug_utils"};
REQUIRED_DEBUG_LAYERS := [?]cstring {"VK_LAYER_KHRONOS_validation"};
REQUIRED_DEVICE_EXTENSIONS := [?]cstring {"VK_KHR_swapchain"};

init_vulkan_context :: proc(window: glfw.WindowHandle) -> VulkanContext {
	vulkan_context: VulkanContext;
	using vulkan_context;

	// Load the the Vulkan instance proc addresses
	{
		context.user_ptr = &instance;
		set_proc_address : vk.SetProcAddressType : proc(p: rawptr, name: cstring) {
			(cast(^rawptr)p)^ = glfw.GetInstanceProcAddress((^vk.Instance)(context.user_ptr)^, name);
		}

		vk.load_proc_addresses(set_proc_address);
	}

	// Ensure required instance extensions are available
	when ODIN_DEBUG {
		available_instance_extensions_count: u32;
		vk.EnumerateInstanceExtensionProperties(nil, &available_instance_extensions_count, nil);
		available_instance_extensions := make([]vk.ExtensionProperties, available_instance_extensions_count);
		defer delete(available_instance_extensions);
		vk.EnumerateInstanceExtensionProperties(nil, &available_instance_extensions_count, raw_data(available_instance_extensions));

		instance_extension: for required_extension in REQUIRED_DEBUG_INSTANCE_EXTENSIONS {
			for available_extension in &available_instance_extensions {
				if required_extension == cstring(&available_extension.extensionName[0]) do continue instance_extension;
			}
			
			fmt.panicf("Required device extension %q not available\n", required_extension);
		}
	}

	// Ensure required layers are available
	when ODIN_DEBUG {
		available_layers_count: u32;
		vk.EnumerateInstanceLayerProperties(&available_layers_count, nil);
		available_layers := make([]vk.LayerProperties, available_layers_count);
		defer delete(available_layers);
		vk.EnumerateInstanceLayerProperties(&available_layers_count, raw_data(available_layers));

		layer: for required_layer in REQUIRED_DEBUG_LAYERS {
			for available_layer in &available_layers {
				if required_layer == cstring(&available_layer.layerName[0]) do continue layer;
			}
			
			fmt.panicf("Required layer %q not available\n", required_layer);
		}
	}

	debug_messenger_create_info: vk.DebugUtilsMessengerCreateInfoEXT;

	// Create instance
	{
		required_extensions: [dynamic]cstring;

		when ODIN_DEBUG {
			for required_extension in REQUIRED_DEBUG_INSTANCE_EXTENSIONS {
				append(&required_extensions, required_extension);
			}
		}

		for glfw_extension in glfw.GetRequiredInstanceExtensions() {
			append(&required_extensions, glfw_extension);
		}

		app_info: vk.ApplicationInfo;
		app_info.sType = .APPLICATION_INFO;
		app_info.pApplicationName = "Vulkan game";
		app_info.applicationVersion = vk.MAKE_VERSION(0, 0, 1);
		app_info.pEngineName = "Vulkan engine";
		app_info.engineVersion = vk.MAKE_VERSION(0, 0, 1);
		app_info.apiVersion = vk.API_VERSION_1_3;

		create_info: vk.InstanceCreateInfo;
		create_info.sType = .INSTANCE_CREATE_INFO;
		create_info.pApplicationInfo = &app_info;
		create_info.ppEnabledExtensionNames = raw_data(required_extensions);
		create_info.enabledExtensionCount = cast(u32) len(required_extensions);

		when ODIN_DEBUG {
			debug_messenger_create_info.sType = .DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT;
			debug_messenger_create_info.messageSeverity = {.WARNING, .ERROR};
			debug_messenger_create_info.messageType = {.GENERAL, .VALIDATION, .PERFORMANCE};
			debug_messenger_create_info.pfnUserCallback = debug_message_callback;

			create_info.ppEnabledLayerNames = &REQUIRED_DEBUG_LAYERS[0];
			create_info.enabledLayerCount = cast(u32) len(REQUIRED_DEBUG_LAYERS);
			create_info.pNext = &debug_messenger_create_info;
		}

		r := vk.CreateInstance(&create_info, nil, &instance);
		fmt.assertf(r == .SUCCESS, "Failed to create Vulkan instance. Result: %v\n", r);
	}

	// Setup debug messenger
	when ODIN_DEBUG {
		proc_: vk.ProcCreateDebugUtilsMessengerEXT = cast(vk.ProcCreateDebugUtilsMessengerEXT) vk.GetInstanceProcAddr(instance, "vkCreateDebugUtilsMessengerEXT");
		fmt.assertf(proc_ != nil, "Failed to get create debug messenger proc address\n");
		proc_(instance, &debug_messenger_create_info, nil, &debug_messenger_ext);
	}

	// Create surface
	r :=  glfw.CreateWindowSurface(instance, window, nil, &window_surface);
	fmt.assertf(r == .SUCCESS, "Failed to create window surface. Result: %v\n", r);

	// Find suitable physical device
	{
		devices_count: u32;
		vk.EnumeratePhysicalDevices(instance, &devices_count, nil);
		devices := make([]vk.PhysicalDevice, devices_count);
		defer delete(devices);
		vk.EnumeratePhysicalDevices(instance, &devices_count, raw_data(devices));

		for device in devices {
			available_extensions_count: u32;
			vk.EnumerateDeviceExtensionProperties(device, nil, &available_extensions_count, nil);
			available_extensions := make([]vk.ExtensionProperties, available_extensions_count);
			defer delete(available_extensions);
			vk.EnumerateDeviceExtensionProperties(device, nil, &available_extensions_count, raw_data(available_extensions));

			device_extension: for required_extension in REQUIRED_DEVICE_EXTENSIONS {
				for available_extension in &available_extensions {
					if required_extension == cstring(&available_extension.extensionName[0]) do continue device_extension;
				}
				
				fmt.panicf("Required device extension %q not available\n", required_extension);
			}

			features: vk.PhysicalDeviceFeatures;
			vk.GetPhysicalDeviceFeatures(device, &features);
			if !features.geometryShader do continue;

			formats_count: u32;
			vk.GetPhysicalDeviceSurfaceFormatsKHR(device, window_surface, &formats_count, nil);
			if formats_count == 0 do continue;

			present_modes_count: u32;
			vk.GetPhysicalDeviceSurfacePresentModesKHR(device, window_surface, &present_modes_count, nil);
			if present_modes_count == 0 do continue;

			queue_family_properties_count: u32;
			vk.GetPhysicalDeviceQueueFamilyProperties(device, &queue_family_properties_count, nil);
			queue_family_properties := make([]vk.QueueFamilyProperties, queue_family_properties_count);
			defer delete(queue_family_properties);
			vk.GetPhysicalDeviceQueueFamilyProperties(device, &queue_family_properties_count, raw_data(queue_family_properties));

			current_graphics_queue_family := -1;
			for queue_family_property, i in queue_family_properties {
				if .GRAPHICS in queue_family_property.queueFlags {
					current_graphics_queue_family = i;
					break;
				}
			}

			if current_graphics_queue_family == -1 do continue;

			current_present_queue_family := -1;
			for queue_family_property, i in queue_family_properties {
				supported: b32;
				vk.GetPhysicalDeviceSurfaceSupportKHR(device, u32(i), window_surface, &supported);

				if supported {
					current_present_queue_family = i;
					break;
				}
			}

			if current_present_queue_family == -1 do continue;

			// This device is suitable
			physical_device = device;
			graphics_queue_family = u32(current_graphics_queue_family);
			present_queue_family = u32(current_present_queue_family);
			
			break;
		}

		fmt.assertf(physical_device != nil, "Failed to find suitable physical device\n");
	}

	// Create logical device
	{
		queue_create_infos: [dynamic]vk.DeviceQueueCreateInfo;
		defer delete(queue_create_infos);

		queue_priority := f32(1.0);

		graphics_queue_create_info: vk.DeviceQueueCreateInfo;
		graphics_queue_create_info.sType = .DEVICE_QUEUE_CREATE_INFO;
		graphics_queue_create_info.queueFamilyIndex = graphics_queue_family;
		graphics_queue_create_info.queueCount = 1;
		graphics_queue_create_info.pQueuePriorities = &queue_priority;
		append(&queue_create_infos, graphics_queue_create_info);

		if graphics_queue_family != present_queue_family {
			present_queue_create_info: vk.DeviceQueueCreateInfo;
			present_queue_create_info.sType = .DEVICE_QUEUE_CREATE_INFO;
			present_queue_create_info.queueFamilyIndex = present_queue_family;
			present_queue_create_info.queueCount = 1;
			present_queue_create_info.pQueuePriorities = &queue_priority;
			append(&queue_create_infos, present_queue_create_info);
		}

		logical_device_create_info: vk.DeviceCreateInfo;
		logical_device_create_info.sType = .DEVICE_CREATE_INFO;
		logical_device_create_info.ppEnabledExtensionNames = &REQUIRED_DEVICE_EXTENSIONS[0];
		logical_device_create_info.enabledExtensionCount = cast(u32) len(REQUIRED_DEVICE_EXTENSIONS);
		logical_device_create_info.pQueueCreateInfos = raw_data(queue_create_infos);
		logical_device_create_info.queueCreateInfoCount = cast(u32) len(queue_create_infos);

		when ODIN_DEBUG {
			logical_device_create_info.ppEnabledLayerNames = &REQUIRED_DEBUG_LAYERS[0];
			logical_device_create_info.enabledLayerCount = cast(u32) len(REQUIRED_DEBUG_LAYERS);
		}

		r := vk.CreateDevice(physical_device, &logical_device_create_info, nil, &logical_device);
		fmt.assertf(r == .SUCCESS, "Failed to create logical device. Result: %v\n", r);

		vk.GetDeviceQueue(logical_device, graphics_queue_family, 0, &graphics_queue);
		vk.GetDeviceQueue(logical_device, present_queue_family, 0, &present_queue);
	}

	return vulkan_context;
}

debug_message_callback : vk.ProcDebugUtilsMessengerCallbackEXT : proc "system" (
	messageSeverity: vk.DebugUtilsMessageSeverityFlagsEXT,
	messageTypes: vk.DebugUtilsMessageTypeFlagsEXT,
	pCallbackData: ^vk.DebugUtilsMessengerCallbackDataEXT,
	pUserData: rawptr)-> b32
{
	severity: string;

	if .VERBOSE in messageSeverity {
		severity = "[verbose]";
	} else if .INFO in messageSeverity {
		severity = "[info]";
	} else if .WARNING in messageSeverity {
		severity = "[warning]";
	} else if .ERROR in messageSeverity {
		severity = "[error]";
	}

	m_type: string;

	if .GENERAL in messageTypes {
		m_type = "[general]";
	} else if .VALIDATION in messageTypes {
		m_type = "[validation]";
	} else if .PERFORMANCE in messageTypes {
		m_type = "[performance]";
	}

	context = runtime.default_context()
	fmt.println(severity, m_type, pCallbackData^.pMessage, "\n");

	return false;
}

cleanup_vulkan_context :: proc(using vulkan_context: ^VulkanContext) {
	vk.DestroyDevice(logical_device, nil);
	vk.DestroySurfaceKHR(instance, window_surface, nil);

	// Debug messenger
	when ODIN_DEBUG {
		proc_: vk.ProcDestroyDebugUtilsMessengerEXT = cast(vk.ProcDestroyDebugUtilsMessengerEXT) vk.GetInstanceProcAddr(instance, "vkDestroyDebugUtilsMessengerEXT");
		fmt.assertf(proc_ != nil, "Failed to get destroy debug messenger proc address\n");
		proc_(instance, debug_messenger_ext, nil);
	}

	vk.DestroyInstance(instance, nil);
}