#version 450
#extension GL_ARB_separate_shader_objects : enable

layout(set = 0, binding = 0, std140) uniform FrameData {
	mat4 projectionMatrix;
	mat4 viewMatrix;
	mat4 camera_mat;
};

// We're not just using the existing layout (set = 1) with the model matrix array because we use
// gl_InstanceIndex do index into the array and the two arrays are not parallel so we can't use the
// same index. This does mean we duplicate the model matrix for emissive geometries since it exists
// here and in the other layout (set = 1).

struct InstanceData {
	mat4 modelMatrix;
	vec3 color;
};

layout(set = 2, binding = 0, std140) buffer InstanceDataBlock {
	InstanceData instanceDataArray[];
};

layout(location = 0) in vec3 inPosition;

layout(location = 0) flat out vec3 fragColor;

void main() {
	InstanceData instanceData = instanceDataArray[gl_InstanceIndex];
	
	gl_Position = projectionMatrix * viewMatrix * instanceData.modelMatrix * vec4(inPosition, 1.0);
	fragColor = instanceData.color;
}