#version 410 core
in vec2 vertex;

out vec2 texelCoordinate;

void main() {
  gl_Position = vec4(vertex, 1.0, 1.0);

  //-1..+1 to 0..1
  texelCoordinate = vertex * 0.5 + vec2(0.5, 0.5);
}
