package main;

import "core:fmt";
import "core:strings";
import "core:os";
import "core:c";
import "core:slice";
import tt "vendor:stb/truetype";

CODE_POINTS_COUNT :: 126 - 33;

Font :: struct {
	name: string,
	base_size: u32,
	fnt_path: string,
	ascent: f32,
	descent: f32,
	space_advance: f32,
	glyphs: [CODE_POINTS_COUNT]Glyph,
}

Glyph :: struct {
	code_point: rune,
	atlas_pos_x: u32,
	atlas_pos_y: u32,
	width: u32,
	height: u32,
	offset_x: i32,
	offset_y: i32,
	advance: f32,
}

init_font :: proc(name: string, base_size: u32, content_scale: f32) -> Font {
	scaled_size := cast(u32) (f32(base_size) * content_scale);
	path := fmt.tprintf("build/fonts/%v%v.cfont", name, scaled_size);

	if os.exists(path) {
		fmt.printf("Loading font %v at scaled size %v\n", name, scaled_size);
		return Font{};
	} else {
		fmt.printf("Generating font %v at scaled size %v\n", name, scaled_size);
		return generate_and_save(name, scaled_size);
	}
}

generate_and_save :: proc(name: string, scaled_size: u32) -> Font {
	TempGlyph :: struct {
		code_point: rune,
		bitmap: [^]byte,
		width: u32,
		height: u32,
		offset_x: i32,
		offset_y: i32,
		atlas_pos_x: u32,
		atlas_pos_y: u32,
		advance: f32,
	}

	ascent, descent, space_advance: f32;
	temp_glyphs: [CODE_POINTS_COUNT]TempGlyph; // Cleanup

	{ // Gather glyph metrics and render bitmaps
		ttf_path := fmt.tprintf("res/%v.ttf", name);
		// file, error := os.open(ttf_path, os.O_WRONLY | os.O_CREATE);
		// defer os.close(file);
		buffer, success := os.read_entire_file_from_filename(ttf_path);

		if !success {
			panic("Failed to open .ttf file\n");
		}

		font_info: tt.fontinfo;
		tt.InitFont(&font_info, &buffer[0], 0);

		unscaled_ascent, unscaled_descent, unscaled_line_gap: i32;
		scale := tt.ScaleForPixelHeight(&font_info, f32(scaled_size));
		tt.GetFontVMetrics(&font_info, &unscaled_ascent, &unscaled_descent, &unscaled_line_gap);

		ascent = f32(unscaled_ascent) * scale;
		descent = f32(unscaled_descent) * scale;
		// space_advance...

		for i in 0..<CODE_POINTS_COUNT {
			code_point := rune(i + 33);
			width, height, offset_x, offset_y: c.int;
			bitmap := tt.GetCodepointBitmap(&font_info, 0, scale, code_point, &width, &height, &offset_x, &offset_y); // Cleanup (eventually)

			advance, bearing: c.int;
			tt.GetCodepointHMetrics(&font_info, rune(i), &advance, &bearing);

			temp_glyphs[i] = TempGlyph {
				code_point = code_point,
				bitmap = bitmap,
				width = u32(width),
				height = u32(height),
				offset_x = offset_x,
				offset_y = offset_y,
				advance = f32(advance) * scale,
			};
		}
	}

	atlas: [dynamic]i16;
	atlas_width: u32 = 0;
	atlas_height: u32 = 0;

	{ // Create atlas
		ordered :: proc(a, b: TempGlyph) -> bool {
			return (a.width * a.height) <= (b.width * b.height);
		}
		
		slice.sort_by(temp_glyphs[:], ordered);
		slice.reverse(temp_glyphs[:]); // Couldn't get reverse_sort_by() to work

		place :: proc(atlas: ^[dynamic]i16, atlas_width: u32, atlas_row: u32, atlas_col: u32, glyph: ^TempGlyph) {
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
			old_atlas := slice.clone(atlas[:]);
			additional_items_count := (additional_rows * atlas_width^) + (additional_cols * atlas_height^) + (additional_rows * additional_cols);
			additional_items := make([]i16, additional_items_count);
			append(atlas, ..additional_items);
			delete(additional_items);
			
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

	final_atlas := make([]u8, atlas_width * atlas_height); // Cleanup
	glyphs: [CODE_POINTS_COUNT]Glyph;

	{ // Create the final atlas and glyphs
		for texel, i in &atlas {
			final_atlas[i] = texel == -1 ? 0 : u8(texel);
		}

		for temp_glyph, i in &temp_glyphs {
			glyphs[i] = Glyph {
				code_point = temp_glyph.code_point,
				atlas_pos_x = temp_glyph.atlas_pos_x,
				atlas_pos_y = temp_glyph.atlas_pos_y,
				width = temp_glyph.width,
				height = temp_glyph.height,
				offset_x = temp_glyph.offset_x,
				offset_y = temp_glyph.offset_y,
			};
		}

		ordered :: proc(a, b: Glyph) -> bool {
			return a.code_point < b.code_point;
		}

		slice.sort_by(glyphs[:], ordered);
	}

	{ // Save to file
		
	}

	return Font {
		ascent = ascent,
		descent = descent,
		space_advance = space_advance,
		glyphs = glyphs,
	};
}
