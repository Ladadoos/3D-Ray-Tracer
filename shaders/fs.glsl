#version 410 core
in vec2 texelCoordinate;

uniform sampler2D screenTexture;

out vec4 outColor;

void main() {
	outColor = texture(screenTexture, texelCoordinate);
}
