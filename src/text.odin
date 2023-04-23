package main;

Text :: struct {
	indices: [dynamic]u16,
	attributes: [dynamic]f32,
	position_x, position_y: f32,
}

init_text :: proc(position_x, position_y: f32, font: ^Font, s: string) -> Text {
	text := Text {
		position_x = position_x,
		position_y = position_y,
	};

	set_text_string(&text, font, s);
	return text;
}

set_text_string :: proc(using text: ^Text, font: ^Font, s: string) {
	clear(&indices);
	clear(&attributes);

	char_count := 0;
	cursor_pos: f32 = 0;

	for code_point in s {
		if code_point == ' ' {
			cursor_pos += f32(font.space_advance);
			continue;
		}

		glyph := &font.glyphs[code_point];
		index_offset := u16(char_count * 4);
		
		append(&indices,
			index_offset, index_offset + 1, index_offset + 2,
			index_offset, index_offset + 2, index_offset + 3,
		);

		glyph_atlas_pos_x := f32(glyph.atlas_pos_x);
		glyph_atlas_pos_y := f32(glyph.atlas_pos_y);
		glyph_width := f32(glyph.width);
		glyph_height := f32(glyph.height);
		glyph_offset_x := f32(glyph.offset_x);
		glyph_offset_y := f32(glyph.offset_y);
		
		screen_pos_x := cursor_pos + glyph_offset_x;
		screen_pos_y := glyph_offset_y;

		append(&attributes,
			screen_pos_x, screen_pos_y, glyph_atlas_pos_x, glyph_atlas_pos_y,
			screen_pos_x, screen_pos_y + glyph_height, glyph_atlas_pos_x, glyph_atlas_pos_y + glyph_height,
			screen_pos_x + glyph_width, screen_pos_y + glyph_height, glyph_atlas_pos_x + glyph_width, glyph_atlas_pos_y + glyph_height,
			screen_pos_x + glyph_width, screen_pos_y, glyph_atlas_pos_x + glyph_width, glyph_atlas_pos_y,
		);

		char_count += 1;
		cursor_pos += f32(glyph.advance);
	}
}

cleanup_text :: proc(using text: ^Text) {
	delete(text.indices);
	delete(text.attributes);
}