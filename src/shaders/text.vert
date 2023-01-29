#version 450
#extension GL_ARB_separate_shader_objects : enable

layout(push_constant) uniform push_constants {
	vec2 half_screen_size;
	vec2 position;
};

layout(location = 0) in vec2 inPosition;
layout(location = 1) in vec2 inTexPosition;

layout(location = 0) out vec2 fragTexPosition;

void main() {
	vec2 rounded_position = round(inPosition + position);
	vec2 normalized_position = rounded_position / half_screen_size - vec2(1.0, 1.0);
	gl_Position = vec4(normalized_position, 0.0, 1.0);

	fragTexPosition = inTexPosition;
}