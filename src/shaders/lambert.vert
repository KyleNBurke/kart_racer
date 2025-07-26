#version 450
#extension GL_ARB_separate_shader_objects : enable

const vec3 ambientLightColor = vec3(0.2, 0.2, 0.2);
const vec3 directionalLightDirection = normalize(vec3(0.2, -1.0, 0.2));
const vec3 directionalLightColor = vec3(0.5, 0.5, 0.5);

layout(set = 0, binding = 0, std140) uniform FrameData {
	mat4 projectionMat;
	mat4 viewMat;
	mat4 camera_mat;
};

layout(set = 1, binding = 0, std140) readonly buffer InstanceData {
	mat4 modelMat[];
};

layout(location = 0) in vec3 inPosition;
layout(location = 1) in vec3 inNormal;
layout(location = 2) in vec3 inColor;

layout(location = 0) out vec3 fragColor;

void main() {
	vec4 vertexPositionObjectSpaceVec4 = modelMat[gl_InstanceIndex] * vec4(inPosition, 1.0);
	vec3 vertexPositionObjectSpaceVec3 = vec3(vertexPositionObjectSpaceVec4);
	vec3 vertexNormalObjectSpace = normalize(transpose(inverse(mat3(modelMat[gl_InstanceIndex]))) * inNormal);
	
	gl_Position = projectionMat * viewMat * vertexPositionObjectSpaceVec4;

	float directionalLightSB = max(dot(vertexNormalObjectSpace, -directionalLightDirection), 0.0f);
	vec3 finalDirectionalLightColor = directionalLightColor * directionalLightSB;

	fragColor = (ambientLightColor + finalDirectionalLightColor) * inColor;
}