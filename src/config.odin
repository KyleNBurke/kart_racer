package main;

import "core:os";
import "core:fmt";
import "core:unicode/utf8";
import "core:strings";
import "core:strconv";

config := Config {};

Config :: struct {
	level: string,
	contact_point_helpers: bool,
	hull_helpers: bool,
	island_helpers: bool,
	init_sleeping_islands: bool,
}

Config_Map :: map[string]string;

load_config :: proc() {
	file_path :: "res/config.txt";

	data, data_ok := os.read_entire_file_from_filename(file_path, context.temp_allocator);
	assert(data_ok, fmt.tprintf("Failed to load config file %s", file_path));

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

	get_string :: proc(data_map: ^Config_Map, key: string) -> string {
		s, ok := data_map[key];
		assert(ok);
		return s;
	}

	get_bool :: proc(data_map: ^Config_Map, key: string) -> bool {
		s, s_ok := data_map[key];
		assert(s_ok);

		b, b_ok := strconv.parse_bool(s);
		assert(b_ok);

		return b;
	}

	config.level = get_string(&data_map, "level");
	config.contact_point_helpers = get_bool(&data_map, "contact_point_helpers");
	config.hull_helpers = get_bool(&data_map, "hull_helpers");
	config.island_helpers = get_bool(&data_map, "island_helpers");
	config.init_sleeping_islands = get_bool(&data_map, "init_sleeping_islands");
	
	fmt.printf("Loaded config file %s\n", file_path);
}