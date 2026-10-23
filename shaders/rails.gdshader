shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;
// Track drawn from vertex colours, but only over the map: nothing past the edge of the picture.
uniform vec2 half_extent = vec2(10.0, 5.0);
varying vec3 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (abs(world.x) > half_extent.x || abs(world.z) > half_extent.y) {
		discard;
	}
	ALBEDO = COLOR.rgb;
}
