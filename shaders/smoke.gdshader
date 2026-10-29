shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;
// A puff of smoke that rises, widens and fades by the clock, always facing the camera. Each instance is a
// point (the top of a chimney, or a fire) in the city's own units, with a phase in INSTANCE_CUSTOM.x so
// that the puffs of one source follow one another, and a jitter in .y.

uniform bool dark = false;
uniform float life = 6.0;
uniform float scale_mul = 1.0;   // size of the puffs
uniform float rise_mul = 1.0;    // how high they climb
uniform float strength = 1.0;    // how thick

varying float alpha;
varying float seed;

void vertex() {
	float age = fract(TIME / life + INSTANCE_CUSTOM.x);
	float size = (3.0 + 9.0 * age) * (dark ? 1.5 : 1.0) * scale_mul;
	vec3 drift = vec3(age * 6.0 + sin(TIME * 0.7 + INSTANCE_CUSTOM.y) * age * 2.0, age * (dark ? 40.0 : 28.0) * rise_mul, age * 2.0);
	vec4 centre = MODEL_MATRIX * vec4(drift, 1.0);
	float unit = length(MODEL_MATRIX[0].xyz);
	vec4 eye = VIEW_MATRIX * centre + vec4(VERTEX.xy * size * unit, 0.0, 0.0);
	POSITION = PROJECTION_MATRIX * eye;
	alpha = (dark ? 0.85 : 0.72) * strength * (1.0 - age) * min(1.0, age * 8.0);
	seed = INSTANCE_CUSTOM.y * 1.37 + floor(TIME / life + INSTANCE_CUSTOM.x) * 2.11;
}

void fragment() {
	// A round puff with a ragged edge (a few lobes, different for each puff), thicker in the middle, lit from above.
	vec2 d = UV - 0.5;
	float r = length(d) * 2.0;
	float a = atan(d.y, d.x);
	float lobes = 0.09 * sin(a * 3.0 + seed) + 0.06 * sin(a * 5.0 - seed * 1.7) + 0.04 * sin(a * 8.0 + seed * 0.6);
	float puff = 1.0 - smoothstep(0.25 + lobes, 0.95 + lobes * 0.5, r);
	vec3 base = dark ? vec3(0.1, 0.1, 0.11) : vec3(0.78, 0.78, 0.8);
	ALBEDO = base * (0.82 + 0.3 * (1.0 - UV.y));
	ALPHA = alpha * puff;
}
