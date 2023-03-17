package main;

import "core:os";
import "core:fmt";
import "core:unicode/utf8";
import "core:strings";

Config :: struct {
	level: string,
}

load_config :: proc() -> Config {
	file_path :: "res/config.txt";

	data, data_ok := os.read_entire_file_from_filename(file_path, context.temp_allocator);
	assert(data_ok, fmt.tprintf("Failed to load config file %s", file_path));

	data_map := make(map[string]string, 10, context.temp_allocator);
	line := make([dynamic]rune, context.temp_allocator);
	split_index, j: int;

	for i in 0..<len(data) {
		r, e := utf8.decode_rune(data[i:]);
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

	level, ok := data_map["level"];
	assert(ok);

	config := Config {
		level,
	};
	
	fmt.printf("Loaded config file %s\n", file_path);
	return config;
}