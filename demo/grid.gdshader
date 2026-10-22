shader_type spatial;
// A quiet floor grid: one-metre lines, anti-aliased with fwidth.

uniform vec3 base : source_color = vec3(0.30, 0.32, 0.35);
uniform vec3 line : source_color = vec3(0.40, 0.43, 0.47);

varying vec3 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 g = abs(fract(world.xz - 0.5) - 0.5) / fwidth(world.xz);
	float l = 1.0 - min(min(g.x, g.y), 1.0);
	ALBEDO = mix(base, line, l * 0.85);
	ROUGHNESS = 0.92;
}
