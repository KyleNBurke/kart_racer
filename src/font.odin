package main;

import "core:fmt";
import "core:strings";
import "core:os";
import "core:c";
import "core:slice";
import tt "vendor:stb/truetype";
import "core:math";

/*
In the future we could implement sub pixel rendering, possibly with this oversampling approach.
https://github.com/nothings/stb/tree/master/tests/oversample

There is also no kerning currently, however this truetype package does have a kerning table we can use.
*/

CODE_POINTS_COUNT :: 126 - 33;
CURSOR_CHECK: u32le : 0b10101010_10101010_10101010_10101010;

Font :: struct {
	name: string,
	base_size: u32,
	cached_file_path: string,
	ascent: f32,
	descent: f32,
	space_advance: f32,
	glyphs: map[rune]Glyph,
}

Glyph :: struct {
	atlas_pos_x: u32,
	atlas_pos_y: u32,
	width: u32,
	height: u32,
	offset_x: i32,
	offset_y: i32,
	advance: f32,
}

init_font :: proc(name: string, base_size: u32, content_scale: f32) -> Font {
	scaled_size := math.round(f32(base_size) * content_scale);
	scaled_size_u32 := u32(scaled_size);
	cached_file_path := fmt.tprintf("build/fonts/%v%v.cfont", name, scaled_size_u32);

	if os.exists(cached_file_path) {
		fmt.printf("Loading font %v at scaled size %v\n", name, scaled_size_u32);
		return load_cached(name, base_size, cached_file_path);
	} else {
		fmt.printf("Generating font %v at scaled size %v\n", name, scaled_size_u32);
		return generate_and_save(name, base_size, scaled_size, cached_file_path);
	}
}

generate_and_save :: proc(name: string, base_size: u32, scaled_size: f32, cached_file_path: string) -> Font {
	Temp_Glyph :: struct {
		code_point: rune,
		using glyph: Glyph,
		bitmap: [^]byte,
	}

	ascent, descent, space_advance: f32;
	temp_glyphs: [CODE_POINTS_COUNT]Temp_Glyph;

	{ // Gather glyph metrics and render bitmaps
		ttf_path := fmt.tprintf("res/%v.ttf", name);
		data, success := os.read_entire_file_from_filename(ttf_path);
		defer delete(data);
		assert(success);

		font_info: tt.fontinfo;
		tt.InitFont(&font_info, &data[0], 0);

		scale := tt.ScaleForPixelHeight(&font_info, scaled_size);

		unscaled_ascent, unscaled_descent, unscaled_line_gap: i32;
		tt.GetFontVMetrics(&font_info, &unscaled_ascent, &unscaled_descent, &unscaled_line_gap);

		ascent = f32(unscaled_ascent) * scale;
		descent = f32(unscaled_descent) * scale;
		
		unscaled_space_advance_x: c.int;
		tt.GetCodepointHMetrics(&font_info, 32, &unscaled_space_advance_x, nil);
		space_advance = scale * f32(unscaled_space_advance_x);

		for i in 0..<CODE_POINTS_COUNT {
			code_point := rune(i + 33);
			width, height, offset_x, offset_y: c.int;
			bitmap := tt.GetCodepointBitmap(&font_info, 0, scale, code_point, &width, &height, &offset_x, &offset_y);

			unscaled_advance_x: c.int;
			tt.GetCodepointHMetrics(&font_info, code_point, &unscaled_advance_x, nil);

			temp_glyphs[i] = Temp_Glyph {
				code_point = code_point,
				glyph = Glyph {
					width = u32(width),
					height = u32(height),
					offset_x = offset_x,
					offset_y = offset_y,
					advance = scale * f32(unscaled_advance_x),
				},
				bitmap = bitmap,
			};
		}
	}

	atlas := make([dynamic]i16, context.temp_allocator);
	atlas_width: u32 = 0;
	atlas_height: u32 = 0;

	{ // Create atlas
		ordered :: proc(a, b: Temp_Glyph) -> bool {
			return (a.width * a.height) >= (b.width * b.height);
		}
		
		slice.sort_by(temp_glyphs[:], ordered);

		place :: proc(atlas: ^[dynamic]i16, atlas_width: u32, atlas_row: u32, atlas_col: u32, glyph: ^Temp_Glyph) {
			for glyph_row in 0..<glyph.height {
				for glyph_col in 0..<glyph.width {
					current_atlas_row := atlas_width * (atlas_row + glyph_row);
					current_atlas_col := atlas_col + glyph_col;
					atlas[current_atlas_row + current_atlas_col] = cast(i16) glyph.bitmap[glyph.width * glyph_row + glyph_col];
				}
			}

			glyph.atlas_pos_x = atlas_col;
			glyph.atlas_pos_y = atlas_row;
		}

		expand :: proc(atlas: ^[dynamic]i16, atlas_width, atlas_height: ^u32, additional_rows, additional_cols: u32) {
			old_atlas := slice.clone(atlas[:], context.temp_allocator);
			additional_items_count := (additional_rows * atlas_width^) + (additional_cols * atlas_height^) + (additional_rows * additional_cols);
			additional_items := make([]i16, additional_items_count, context.temp_allocator);
			append(atlas, ..additional_items);
			
			new_atlas_width := atlas_width^ + additional_cols;
			new_atlas_height := atlas_height^ + additional_rows;

			for row in 0..<atlas_height^ {
				for col in 0..<atlas_width^ {
					atlas[new_atlas_width * row + col] = old_atlas[atlas_width^ * row + col];
				}

				for col in atlas_width^..<new_atlas_width {
					atlas[new_atlas_width * row + col] = -1;
				}
			}

			for row in atlas_height^..<new_atlas_height {
				for col in 0..<new_atlas_width {
					atlas[new_atlas_width * row + col] = -1;
				}
			}

			atlas_width^ = new_atlas_width;
			atlas_height^ = new_atlas_height;
		}

		glyph_loop: for glyph in &temp_glyphs {
			if atlas_width >= glyph.width && atlas_height >= glyph.height {
				atlas_row_end := atlas_height - glyph.height;
				atlas_col_end := atlas_width - glyph.width;

				for atlas_col in 0..=atlas_col_end {
					atlas_row_loop: for atlas_row in 0..=atlas_row_end {
						for glyph_row in 0..<glyph.height {
							for glyph_col in 0..<glyph.width {
								texel := atlas[atlas_width * (atlas_row + glyph_row) + (atlas_col + glyph_col)];

								if texel != -1 {
									// Glyph cannot fit here, move to next position
									continue atlas_row_loop;
								}
							}
						}

						// Glyph can fit here
						place(&atlas, atlas_width, atlas_row, atlas_col, &glyph);
						continue glyph_loop;
					}
				}
			}

			// Glyph cannot fit anywhere, expand atlas in shorter direction and place the glyph
			additional_rows, additional_cols, pos_row, pos_col: u32;

			if atlas_width + glyph.width <= atlas_height + glyph.height {
				additional_rows = glyph.height - min(glyph.height, atlas_height);
				additional_cols = glyph.width;
				pos_row = 0;
				pos_col = atlas_width;
			} else {
				additional_rows = glyph.height;
				additional_cols = glyph.width - min(glyph.width, atlas_width);
				pos_row = atlas_height;
				pos_col = 0;
			}

			expand(&atlas, &atlas_width, &atlas_height, additional_rows, additional_cols);
			place(&atlas, atlas_width, pos_row, pos_col, &glyph);
		}

		/*
		for row in 0..<atlas_height {
			for col in 0..<atlas_width {
				b := atlas[atlas_width * row + col];
				c: rune;

				if b == -1 {
					c = '.';
				} else if b > 100 {
					c = '#';
				} else {
					c = ' ';
				}
				
				fmt.printf("%v", c);
			}
			fmt.println();
		}
		*/
	}

	final_atlas := make([]u8, atlas_width * atlas_height, context.temp_allocator);
	glyphs: map[rune]Glyph;

	{ // Create the final atlas and glyphs
		for texel, i in &atlas {
			final_atlas[i] = texel == -1 ? 0 : u8(texel);
		}

		for temp_glyph in &temp_glyphs {
			glyphs[temp_glyph.code_point] = temp_glyph.glyph;
		}
	}

	{ // Save to file
		err := os.make_directory("build/fonts");
		assert(err == os.ERROR_NONE || err == os.ERROR_ALREADY_EXISTS);
		
		atlas_width_bytes := transmute([4]u8) u32le(atlas_width);
		atlas_height_bytes := transmute([4]u8) u32le(atlas_height);
		ascent_bytes := transmute([4]byte) f32le(ascent);
		descent_bytes := transmute([4]byte) f32le(descent);
		space_advance_bytes := transmute([4]byte) f32le(space_advance);
		glyph_count_bytes := transmute([4]byte) u32le(CODE_POINTS_COUNT);
		cursor_check_bytes := transmute([4]u8) CURSOR_CHECK;

		data := make([dynamic]u8, context.temp_allocator);

		append(&data, ..atlas_width_bytes[:]);
		append(&data, ..atlas_height_bytes[:]);
		append(&data, ..final_atlas[:]);
		append(&data, ..cursor_check_bytes[:]);
		append(&data, ..ascent_bytes[:]);
		append(&data, ..descent_bytes[:]);
		append(&data, ..space_advance_bytes[:]);
		append(&data, ..glyph_count_bytes[:]);

		for code_point, glyph in &glyphs {
			code_point_bytes  := transmute([4]byte) i32le(code_point);
			atlas_pos_x_bytes := transmute([4]byte) u32le(glyph.atlas_pos_x);
			atlas_pos_y_bytes := transmute([4]byte) u32le(glyph.atlas_pos_y);
			width_bytes       := transmute([4]byte) u32le(glyph.width);
			height_bytes      := transmute([4]byte) u32le(glyph.height);
			offset_x_bytes    := transmute([4]byte) i32le(glyph.offset_x);
			offset_y_bytes    := transmute([4]byte) i32le(glyph.offset_y);
			advance_bytes     := transmute([4]byte) f32le(glyph.advance);

			append(&data, ..code_point_bytes[:]);
			append(&data, ..atlas_pos_x_bytes[:]);
			append(&data, ..atlas_pos_y_bytes[:]);
			append(&data, ..width_bytes[:]);
			append(&data, ..height_bytes[:]);
			append(&data, ..offset_x_bytes[:]);
			append(&data, ..offset_y_bytes[:]);
			append(&data, ..advance_bytes[:]);
		}

		append(&data, ..cursor_check_bytes[:]);

		success := os.write_entire_file(cached_file_path, data[:]);
		assert(success);
	}

	return Font {
		name = name,
		base_size = base_size,
		cached_file_path = cached_file_path,
		ascent = ascent,
		descent = descent,
		space_advance = space_advance,
		glyphs = glyphs,
	};
}

load_cached :: proc(name: string, base_size: u32, cached_file_path: string) -> Font {
	data, success := os.read_entire_file_from_filename(cached_file_path, context.temp_allocator);
	assert(success);

	pos := 0;

	atlas_width  := cast(int) (cast(^u32le) &data[pos])^; pos += 4;
	atlas_height := cast(int) (cast(^u32le) &data[pos])^; pos += 4;
	pos += atlas_width * atlas_height;

	cursor_check := cast(^u32le) &data[pos]; pos += 4;
	assert(cursor_check^ == CURSOR_CHECK);

	ascent        := cast(f32) (cast(^f32le) &data[pos])^; pos += 4;
	descent       := cast(f32) (cast(^f32le) &data[pos])^; pos += 4;
	space_advance := cast(f32) (cast(^f32le) &data[pos])^; pos += 4;
	glyph_count   := cast(^u32le) &data[pos]; pos += 4;

	glyphs: map[rune]Glyph;

	for i in 0..<glyph_count^ {
		code_point  := cast(rune) (cast(^i32le) &data[pos])^; pos += 4;
		atlas_pos_x := cast(u32) (cast(^u32le) &data[pos])^; pos += 4;
		atlas_pos_y := cast(u32) (cast(^u32le) &data[pos])^; pos += 4;
		width       := cast(u32) (cast(^u32le) &data[pos])^; pos += 4;
		height      := cast(u32) (cast(^u32le) &data[pos])^; pos += 4;
		offset_x    := cast(i32) (cast(^i32le) &data[pos])^; pos += 4;
		offset_y    := cast(i32) (cast(^i32le) &data[pos])^; pos += 4;
		advance     := cast(f32) (cast(^f32le) &data[pos])^; pos += 4;

		glyphs[code_point] = Glyph {
			atlas_pos_x = atlas_pos_x,
			atlas_pos_y = atlas_pos_y,
			width = width,
			height = height,
			offset_x = offset_x,
			offset_y = offset_y,
			advance = advance,
		};
	}

	cursor_check = cast(^u32le) &data[pos]; pos += 4;
	assert(cursor_check^ == CURSOR_CHECK);

	return Font {
		name = name,
		base_size = base_size,
		cached_file_path = cached_file_path,
		ascent = ascent,
		descent = descent,
		space_advance = space_advance,
		glyphs = glyphs,
	};
}

cleanup_font :: proc(using font: ^Font) {
	delete(font.glyphs);
}