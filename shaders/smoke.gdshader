shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;
// A puff of smoke that rises, widens and fades by the clock, always facing the camera. Each instance is a
// point (the top of a chimney, or a fire) in the city's own units, with a phase in INSTANCE_CUSTOM.x so
// that the puffs of one source follow one another, and a jitter in .y.

uniform bool dark = false;
uniform float life = 6.0;

varying float alpha;

void vertex() {
	float age = fract(TIME / life + INSTANCE_CUSTOM.x);
	float size = (3.0 + 9.0 * age) * (dark ? 1.5 : 1.0);
	vec3 drift = vec3(age * 6.0 + sin(TIME * 0.7 + INSTANCE_CUSTOM.y) * age * 2.0, age * (dark ? 40.0 : 28.0), age * 2.0);
	vec4 centre = MODEL_MATRIX * vec4(drift, 1.0);
	float unit = length(MODEL_MATRIX[0].xyz);
	vec4 eye = VIEW_MATRIX * centre + vec4(VERTEX.xy * size * unit, 0.0, 0.0);
	POSITION = PROJECTION_MATRIX * eye;
	alpha = (dark ? 0.75 : 0.5) * (1.0 - age) * min(1.0, age * 8.0);
}

void fragment() {
	ALBEDO = dark ? vec3(0.1, 0.1, 0.11) : vec3(0.78, 0.78, 0.8);
	ALPHA = alpha;
}
