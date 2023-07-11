package main;

import "core:os";
import "core:fmt";
import "core:unicode/utf8";
import "core:strings";
import "core:strconv";
import "core:reflect";
import "core:slice";
import "vendor:glfw";

CONFIG_FILE :: "res/config.txt";

Window_State :: enum { Normal, Maximized };

Config :: struct {
	window_state: Window_State,
	window_width: int,
	window_height: int,
	window_pos_x: int,
	window_pos_y: int,
	level: string,
	contact_point_helpers: bool,
	hull_helpers: bool,
	island_helpers: bool,
	init_sleeping_islands: bool,
	explosion_helpers: bool,
}

Config_Map :: map[string]string;

config := Config {
	window_width = 1280,
	window_height = 720,
	window_pos_x = 50,
	window_pos_y = 50,
};

load_config :: proc() {
	data, data_ok := os.read_entire_file_from_filename(CONFIG_FILE, context.temp_allocator);
	assert(data_ok, fmt.tprintf("Failed to load config file %s", CONFIG_FILE));
	
	data_map := make(Config_Map, 10, context.temp_allocator);
	line := make([dynamic]rune, context.temp_allocator);
	split_index, j: int;

	for i in 0..<len(data) {
		r, _ := utf8.decode_rune(data[i:]);
		assert(r != utf8.RUNE_ERROR);
		
		if r == '\n' || i == len(data) - 1 {
			if i == len(data) - 1 {
				append(&line, r);
			}
			
			key := utf8.runes_to_string(line[:split_index], context.temp_allocator);
			value := utf8.runes_to_string(line[split_index + 1:], context.temp_allocator);

			key = strings.trim_space(key);
			value = strings.trim_space(value);

			data_map[key] = value;

			clear(&line);
			j = 0;
		} else {
			if r == '=' {
				split_index = j;
			}

			append(&line, r);
			j += 1;
		}
	}

	set :: proc(field: reflect.Struct_Field, $T: typeid, v: T) {
		ptr := cast(uintptr) &config + field.offset;
		(cast(^T) ptr)^ = v;
	}
	
	fields := reflect.struct_fields_zipped(Config);

	for field in &fields {
		s, ok := data_map[field.name];

		if !ok {
			value := reflect.struct_field_value(config, field);
			fmt.println(fmt.tprintf("[config] %s not found, using default value %v", field.name, value));
			continue;
		}
		
		#partial switch field_variant in field.type.variant {
		case reflect.Type_Info_Boolean:
			b, ok := strconv.parse_bool(s);
			assert(ok, fmt.tprintf("[config] Could not parse '%s' as a bool for field %s", s, field.name));
			set(field, bool, b);
			
		case reflect.Type_Info_String:
			s_copy := strings.clone(s);
			set(field, string, s_copy);

		case reflect.Type_Info_Named:
			if field_base_variant, ok := field_variant.base.variant.(reflect.Type_Info_Enum); ok {
				index, found := slice.linear_search(field_base_variant.names[:], s);
				assert(found, fmt.tprintf("[config] Enum variant %s not found for enum %s of field %s", s, field_variant.name, field.name));
				
				enum_value := field_base_variant.values[index];
				set(field, reflect.Type_Info_Enum_Value, enum_value);
			}

		case reflect.Type_Info_Integer:
			i, ok := strconv.parse_int(s);
			assert(ok);
			set(field, int, i);
		}
	}

	fmt.printf("Loaded config file %s\n", CONFIG_FILE);
}

update_config_from_window_change :: proc(window: glfw.WindowHandle) {
	maximized := glfw.GetWindowAttrib(window, glfw.MAXIMIZED);

	if maximized == 1 {
		config.window_state = .Maximized;
	} else {
		config.window_state = .Normal;

		framebuffer_width, framebuffer_height := glfw.GetFramebufferSize(window);
		config.window_width = int(framebuffer_width);
		config.window_height = int(framebuffer_height);

		pos_x, pos_y := glfw.GetWindowPos(window);
		config.window_pos_x = int(pos_x);
		config.window_pos_y = int(pos_y);
	}

	save_config();
}

save_config :: proc() {
	data := make([dynamic]u8, context.temp_allocator);
	fields := reflect.struct_fields_zipped(Config);

	for field in &fields {
		name := transmute([]u8) field.name;
		append(&data, ..name);

		s := " = ";
		s_u8 := transmute([]u8) s;
		append(&data, ..s_u8);
		
		value := reflect.struct_field_value(config, field);
		value_string: string;

		#partial switch field_variant in field.type.variant {
		case reflect.Type_Info_Boolean:
			b, _ := reflect.as_bool(value);
			value_string = b ? "t" : "f";

		case reflect.Type_Info_String:
			value_string, _ = reflect.as_string(value);

		case reflect.Type_Info_Named:
			if _, ok := field_variant.base.variant.(reflect.Type_Info_Enum); ok {
				value_string = reflect.enum_string(value);
			}

		case reflect.Type_Info_Integer:
			i, _ := reflect.as_int(value);
			value_string = fmt.tprintf("%v", i);
		}

		value_u8 := transmute([]u8) value_string;
		append(&data, ..value_u8);

		s = "\n";
		s_u8 = transmute([]u8) s;
		append(&data, ..s_u8);
	}

	success := os.write_entire_file(CONFIG_FILE, data[:]);
	assert(success);
	
	fmt.printf("Saved config file %s\n", CONFIG_FILE);
}

cleanup_config :: proc() {
	delete(config.level);
}