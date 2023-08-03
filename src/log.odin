package main;

import "core:fmt";

// We could move this into it's own package if we remove the dependency on the config struct.
// Perhaps we should make a build system which sets -define:VERBOSE_LOGGING based on a config file.
// Then we could disable the proc if that is undefined/set to false. That's probably a better way to
// handle initialization stuff because those things can be constants. It can be done to any
// initialization constant we might want like SHOW_HULL_HELPERS for example.

@(disabled = !ODIN_DEBUG)
log_verbose :: proc(args: ..any, sep := " ") {
	if !config.verbose_logging do return;

	fmt.print(args, sep);
}

@(disabled = !ODIN_DEBUG)
log_verbosef :: proc(fmt_str: string, args: ..any) {
	if !config.verbose_logging do return;
	
	fmt.printf(fmt_str, ..args);
}