package render;

import "core:fmt";
import "core:os";
import "core:runtime";
import "vendor:glfw";
import vk "vendor:vulkan";

REQUIRED_DEBUG_INSTANCE_EXTENSIONS := [?]cstring {"VK_EXT_debug_utils"};
REQUIRED_DEBUG_LAYERS := [?]cstring {"VK_LAYER_KHRONOS_validation"};

VulkanContext :: struct {
    instance: vk.Instance,
    debug_messenger_ext: vk.DebugUtilsMessengerEXT,
    surface: vk.SurfaceKHR,
    physical_device: PhysicalDevice,
}

PhysicalDevice :: struct {
    handle: vk.PhysicalDevice,
    graphics_queue_family: u32,
    present_queue_family: u32,
}

// #Todo: Def make a proc that checks the return value of the vulkan calls and asserts it's success, if it's not, exit and log the result code.
// Logging the result code will be very useful.

init_vulkan_context :: proc(window: glfw.WindowHandle) -> VulkanContext {
    instance: vk.Instance;

    // Load the the Vulkan instance proc addresses
    {
        context.user_ptr = &instance;
        set_proc_address : vk.SetProcAddressType : proc(p: rawptr, name: cstring) {
            (cast(^rawptr)p)^ = glfw.GetInstanceProcAddress((^vk.Instance)(context.user_ptr)^, name);
        }

        vk.load_proc_addresses(set_proc_address);
    }

    // #Todo: Ensure required instance extensions are available

    // Ensure required layers are available
    when ODIN_DEBUG {
        available_layers_count: u32;
		vk.EnumerateInstanceLayerProperties(&available_layers_count, nil);
		available_layers := make([]vk.LayerProperties, available_layers_count); // Need to clean this up?
		vk.EnumerateInstanceLayerProperties(&available_layers_count, raw_data(available_layers));

        outer: for required_layer in REQUIRED_DEBUG_LAYERS {
            for available_layer in &available_layers {
                if required_layer == cstring(&available_layer.layerName[0]) do continue outer;
            }
            
            // Look into fmt.panic();
            fmt.eprintf("Required layer %q not available\n", required_layer);
            os.exit(1);
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
        } else {
            create_info.enabledLayerCount = 0; // Should default to 0 already right?
        }
        
        if vk.CreateInstance(&create_info, nil, &instance) != .SUCCESS {
            fmt.eprintln("Failed to create Vulkan instance\n");
            os.exit(1);
        }
    }

    // Setup debug messenger
    debug_messenger_ext: vk.DebugUtilsMessengerEXT;
    when ODIN_DEBUG {
        proc_: vk.ProcCreateDebugUtilsMessengerEXT = cast(vk.ProcCreateDebugUtilsMessengerEXT) vk.GetInstanceProcAddr(instance, "vkCreateDebugUtilsMessengerEXT");

        if proc_ == nil {
            fmt.eprintln("Failed to get create debug messenger proc address");
            os.exit(1);
        } else {
            proc_(instance, &debug_messenger_create_info, nil, &debug_messenger_ext);
        }
    }

    // Create surface
    surface: vk.SurfaceKHR;
    if glfw.CreateWindowSurface(instance, window, nil, &surface) != .SUCCESS {
        fmt.eprintln("Failed to create window surface");
        os.exit(1);
    }

    // Find suitable physical device
    physical_device: PhysicalDevice;
    {
        devices_count: u32;
        vk.EnumeratePhysicalDevices(instance, &devices_count, nil);
        devices := make([]vk.PhysicalDevice, devices_count); // Need to clean this up?
        vk.EnumeratePhysicalDevices(instance, &devices_count, raw_data(devices));

        for device in devices {
            // #Todo: Ensure required device extensions are available

            features: vk.PhysicalDeviceFeatures;
            vk.GetPhysicalDeviceFeatures(device, &features);
            if !features.geometryShader do continue;

            formats_count: u32;
            vk.GetPhysicalDeviceSurfaceFormatsKHR(device, surface, &formats_count, nil);
            if formats_count == 0 do continue;

            present_modes_count: u32;
            vk.GetPhysicalDeviceSurfacePresentModesKHR(device, surface, &present_modes_count, nil);
            if present_modes_count == 0 do continue;

            queue_family_properties_count: u32;
            vk.GetPhysicalDeviceQueueFamilyProperties(device, &queue_family_properties_count, nil);
            queue_family_properties := make([]vk.QueueFamilyProperties, queue_family_properties_count);
            vk.GetPhysicalDeviceQueueFamilyProperties(device, &queue_family_properties_count, raw_data(queue_family_properties));

            graphics_queue_family := -1;
            for queue_family_property, i in queue_family_properties {
                if .GRAPHICS in queue_family_property.queueFlags {
                    graphics_queue_family = i;
                    break;
                }
            }

            if graphics_queue_family == -1 do continue;

            present_queue_family := -1;
            for queue_family_property, i in queue_family_properties {
                supported: b32;
                vk.GetPhysicalDeviceSurfaceSupportKHR(device, u32(i), surface, &supported);

                if supported {
                    present_queue_family = i;
                    break;
                }
            }

            if present_queue_family == -1 do continue;

            physical_device.handle = device;
            physical_device.graphics_queue_family = u32(graphics_queue_family);
            physical_device.present_queue_family = u32(present_queue_family);
            
            break;
        }

        if physical_device.handle == nil {
            fmt.eprintln("Failed to find suitable physical device");
            os.exit(1);
        }
    }

    // Create logical device
    logical_device: vk.Device;
    {
        
    }

    return VulkanContext {
        instance,
        debug_messenger_ext,
        surface,
        physical_device,
    };
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
    fmt.printf(severity, m_type, pCallbackData^.pMessage, "\n\n");

    return false;
}

cleanup_vulkan_context :: proc(using vulkan_context: ^VulkanContext) {
    vk.DestroySurfaceKHR(instance, surface, nil);

    // Cleanup debug messenger
    when ODIN_DEBUG {
        proc_: vk.ProcDestroyDebugUtilsMessengerEXT = cast(vk.ProcDestroyDebugUtilsMessengerEXT) vk.GetInstanceProcAddr(instance, "vkDestroyDebugUtilsMessengerEXT");

        if proc_ == nil {
            fmt.eprintln("Failed to get destroy debug messenger proc address");
            os.exit(1);
        } else {
            proc_(instance, debug_messenger_ext, nil);
        }
    }

    vk.DestroyInstance(instance, nil);
}