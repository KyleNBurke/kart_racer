#version 450
#extension GL_ARB_separate_shader_objects : enable

layout(set = 0, binding = 0, std140) uniform FrameData {
	mat4 proj_mat;
	mat4 view_mat;
	mat4 camera_mat;
};

struct Particle {
	vec3 position;
	float size;
	vec3 color;
};

layout(set = 1, binding = 0, std140) readonly buffer InstanceData {
	Particle particles[];
};

vec2 vert_positions[4] = vec2[] (
	vec2( 1.0,  1.0),
	vec2( 1.0, -1.0),
	vec2(-1.0, -1.0),
	vec2(-1.0,  1.0)
);

int indices[6] = int[] (
	0, 1, 2,
	0, 2, 3
);

layout(location = 0) flat out vec3 fragColor;

void main() {
	vec3 camera_up = vec3(camera_mat[1][0], camera_mat[1][1], camera_mat[1][2]);
	vec3 camera_left = vec3(camera_mat[0][0], camera_mat[0][1], camera_mat[0][2]);

	int index = indices[gl_VertexIndex];
	vec2 vert_position = vert_positions[index];
	Particle particle = particles[gl_InstanceIndex];

	vec3 position = particle.position + camera_left * vert_position.x * particle.size + camera_up * vert_position.y * particle.size;
	gl_Position = proj_mat * view_mat * vec4(position, 1.0);

	fragColor = particles[gl_InstanceIndex].color;
}