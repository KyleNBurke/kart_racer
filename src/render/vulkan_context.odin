package render;

import "core:fmt";
import "core:os";
import "core:runtime";
import "vendor:glfw";
import vk "vendor:vulkan";

REQUIRED_DEBUG_INSTANCE_EXTENSIONS := [?]cstring {"VK_EXT_debug_utils"}; // This should only happen in debug mode
REQUIRED_DEBUG_LAYERS := [?]cstring {"VK_LAYER_KHRONOS_validation"};

VulkanContext :: struct {
    instance: vk.Instance,
}

init_vulkan_context :: proc() -> VulkanContext {
    // #Todo: Ensure required instance extensions are available

    // Ensure required layers are available
    when ODIN_DEBUG {
        available_layers_count: u32;
        fmt.printf("before");
		vk.EnumerateInstanceLayerProperties(&available_layers_count, nil);
        fmt.printf("after: %v", available_layers_count);
		available_layers := make([]vk.LayerProperties, available_layers_count);
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

    // Create instance
    instance: vk.Instance;
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
            debug_messenger_create_info: vk.DebugUtilsMessengerCreateInfoEXT;
            debug_messenger_create_info.sType = .DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT;
            debug_messenger_create_info.messageSeverity = {.WARNING, .ERROR};
            debug_messenger_create_info.messageType = {.GENERAL, .VALIDATION, .PERFORMANCE};
            debug_messenger_create_info.pfnUserCallback = debug_message_callback;
            // debug_messenger_create_info.pUserData = the context?

            create_info.ppEnabledLayerNames = &REQUIRED_DEBUG_LAYERS[0];
            create_info.enabledLayerCount = cast(u32) len(REQUIRED_DEBUG_LAYERS);
            create_info.pNext = &debug_messenger_create_info;
        } else {
            create_info.enabledLayerCount = 0;
        }
        
        if vk.CreateInstance(&create_info, nil, &instance) != .SUCCESS {
            fmt.eprintln("Failed to create Vulkan instance\n");
            os.exit(1);
        } else {
            fmt.println("Worked");
        }
    }

    return VulkanContext {
        instance,
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