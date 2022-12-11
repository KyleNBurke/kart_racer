package main;

import "core:fmt";
import "core:strings";
import "core:os";
import "core:c";
import "core:slice";
import tt "vendor:stb/truetype";

Font :: struct {
	name: string,
	base_size: u32,
	fnt_path: string,
}

init_font :: proc(name: string, base_size: u32, content_scale: f32) {
	scaled_size := cast(u32) (f32(base_size) * content_scale);
	path := fmt.tprintf("build/fonts/%v%v.cfont", name, scaled_size);

	if os.exists(path) {
		fmt.printf("Loading font %v at scaled size %v\n", name, scaled_size);	
	} else {
		fmt.printf("Generating font %v at scaled size %v\n", name, scaled_size);
		generate_and_save(name, scaled_size);
	}
}

generate_and_save :: proc(name: string, scaled_size: u32) {
	UnplacedGlyph :: struct {
		code_point: rune,
		bitmap: [^]byte,
		width: u32,
		height: u32,
		bearing_x: u32,
		bearing_y: u32,
		advance: u32,
	}

	code_points_count :: 126 - 33;
	glyphs: [code_points_count]UnplacedGlyph;

	{ // Gather glyph metrics and render bitmaps
		ttf_path := fmt.tprintf("res/%v.ttf", name);
		// file, error := os.open(ttf_path, os.O_WRONLY | os.O_CREATE);
		// defer os.close(file);
		buffer, success := os.read_entire_file_from_filename(ttf_path);

		if !success {
			fmt.panicf("Failed to open .ttf file\n");
		}

		font_info: tt.fontinfo;
		tt.InitFont(&font_info, &buffer[0], 0);

		ascent, descent, line_gap: i32;
		scale := tt.ScaleForPixelHeight(&font_info, f32(scaled_size));
		tt.GetFontVMetrics(&font_info, &ascent, &descent, &line_gap);

		for i in 0..<code_points_count {
			code_point := rune(i + 33);
			width, height, offset_x, offset_y: c.int;
			bitmap := tt.GetCodepointBitmap(&font_info, 0, scale, code_point, &width, &height, &offset_x, &offset_y); // Cleanup (eventually)
		
			advance, bearing: c.int;
			tt.GetCodepointHMetrics(&font_info, rune(i), &advance, &bearing);

			glyphs[i] = UnplacedGlyph {
				code_point = code_point,
				bitmap = bitmap,
				width = u32(width),
				height = u32(height),
				bearing_x = u32(offset_x),
				bearing_y = u32(offset_y),
			};
		}
	}

	atlas: [dynamic]i16;
	atlas_width: u32 = 0;
	atlas_height: u32 = 0;

	{ // Create atlas
		ordered :: proc(a, b: UnplacedGlyph) -> bool {
			return (a.width * a.height) <= (b.width * b.height);
		}
		
		slice.sort_by(glyphs[:], ordered);
		slice.reverse(glyphs[:]); // Couldn't get reverse_sort_by() to work

		expand_and_place :: proc(atlas: ^[dynamic]i16, atlas_width: ^u32, atlas_height: ^u32, glyph_width: u32, glyph_height: u32) {
			
		}

		place :: proc(atlas: ^[dynamic]i16, atlas_width: u32, atlas_row: u32, atlas_col: u32, glyph: ^UnplacedGlyph) {
			for glyph_row in 0..<glyph.height {
				for glyph_col in 0..<glyph.width {
					current_atlas_row := atlas_width * atlas_row * glyph_row;
					current_atlas_col := atlas_col + glyph_col;
					atlas[current_atlas_row + current_atlas_col] = cast(i16) glyph.bitmap[glyph.width * glyph_row + glyph_col];
				}
			}
		}

		for glyph in glyphs {
			// atlas_row_end := atlas_width - glyph.width;
			if glyph.width >= atlas_width || glyph.height >= atlas_height {
				// Glyph will not fit
				// expand_and_place(&atlas, &atlas_width, &atlas_height, glyph.width, glyph.height);

				if atlas_width + glyph.width > atlas_height + glyph.height {
					
				} else {
					
				}
			}

			for atlas_row in 0..<atlas_height {
				atlas_col_loop: for atlas_col in 0..<atlas_width {
					for glyph_row in 0..<glyph.height {
						for glyph_col in 0..<glyph.width {
							texel := atlas[atlas_width * atlas_row + atlas_col];

							if texel == -1 {
								// Glyph cannot fit here, move to next position
								continue atlas_col_loop;
							}
						}
					}

					// Glyph can fit here
					place(&atlas, atlas_width, atlas_height);
				}
			}
		}
	}

	{ // Save to file
		
	}
}
