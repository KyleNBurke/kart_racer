#version 450
#extension GL_ARB_separate_shader_objects : enable

layout(set = 0, binding = 0, std140) uniform FrameData {
	mat4 projectionMatrix;
	mat4 viewMatrix;
	mat4 camera_mat;
};

layout(set = 1, binding = 0, std140) buffer InstanceData {
	mat4 modelMatrix[];
};

layout(location = 0) in vec3 inPosition;
layout(location = 1) in vec3 inColor;

layout(location = 0) out vec3 fragColor;

void main() {
	gl_Position = projectionMatrix * viewMatrix * modelMatrix[gl_InstanceIndex] * vec4(inPosition, 1.0);
	fragColor = inColor;
}