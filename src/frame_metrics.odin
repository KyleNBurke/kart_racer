package main;

import "core:fmt";

UPDATE_INTERVAL_SECS: f32 : 0.5;

Frame_Metrics :: struct {
	duration: f32,
	frame_count: int,
	text_index: int,
}

init_frame_metrics :: proc(font: ^Font, texts: ^[dynamic]Text) -> Frame_Metrics {
	text := init_text(30, 30, font, "...");
	append(texts, text);

	return Frame_Metrics {
		text_index = len(texts) - 1,
	};
}

update_frame_metrics :: proc(using frame_metrics: ^Frame_Metrics, font: ^Font, texts: []Text, dt: f32) {
	duration += dt;
	frame_count += 1;

	if duration > UPDATE_INTERVAL_SECS {
		fps := f32(frame_count) / duration;

		s := fmt.tprintf("%.0ffps", fps);
		set_text_string(&texts[text_index], font, s);

		duration = 0;
		frame_count = 0;
	}
}