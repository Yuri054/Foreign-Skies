shader_type canvas_item;
// Paints the province bitmap: owner colors, borders and selection are all resolved here,
// so changing ownership only means rewriting one pixel of the `lookup` texture.

uniform sampler2D provinces : filter_nearest, repeat_disable;
uniform sampler2D lookup : filter_nearest, repeat_disable;  // color to paint each province
uniform sampler2D owners : filter_nearest, repeat_disable;  // owner color, for borders
uniform sampler2D marks : filter_nearest, repeat_disable;   // diplomacy: hatch colour, alpha > 0.5 = hatched
uniform sampler2D blocs : filter_nearest, repeat_disable;   // diplomacy: bloc colour, alpha > 0.5 = in a bloc
uniform sampler2D sea_zones : filter_nearest, repeat_disable; // red channel = sea zone id
uniform bool show_zones = false;
uniform sampler2D zone_colors : filter_nearest, repeat_disable; // 64x1: tint of each sea zone, alpha 0 = none
uniform bool zone_paint = false;
uniform bool hatch_marks = false; // hatch the provinces `marks` flags, outside the diplomacy mode too
uniform int selected_zone = 0;
uniform int hover_zone = 0;
uniform bool diplomacy = false;
uniform int lookup_width = 256;
uniform int max_id = 0;
uniform vec2 map_size = vec2(1.0);
uniform int mode = 0; // 1 raw province colors, anything else paints from `lookup`
uniform int selected_id = 0;
uniform int hover_id = 0;
uniform bool occupation_stripes = false; // stripe provinces whose painted colour is not their owner's
uniform float stripe_px = 9.0;

uniform vec4 sea_color : source_color = vec4(0.12, 0.2, 0.32, 1.0);
uniform vec4 background_color : source_color = vec4(0.58, 0.58, 0.54, 1.0);
uniform float border_px = 1.0;

const int SEA = 0;
const int BACKGROUND = -1;

int id_at(vec2 uv) {
	ivec3 c = ivec3(round(texture(provinces, uv).rgb * 255.0));
	if (c == ivec3(0)) {
		return SEA;
	}
	int id = c.r + c.g * 256;
	return id > max_id ? BACKGROUND : id;
}

int zone_at(vec2 uv) {
	return int(round(texture(sea_zones, uv).r * 255.0));
}

vec4 owner_color(int id) {
	ivec2 p = ivec2(id % lookup_width, id / lookup_width);
	return texelFetch(owners, p, 0);
}

vec4 paint_color(int id) {
	ivec2 p = ivec2(id % lookup_width, id / lookup_width);
	return texelFetch(lookup, p, 0);
}

vec4 mark_color(int id) {
	ivec2 p = ivec2(id % lookup_width, id / lookup_width);
	return texelFetch(marks, p, 0);
}

vec4 bloc_color(int id) {
	ivec2 p = ivec2(id % lookup_width, id / lookup_width);
	return texelFetch(blocs, p, 0);
}

vec3 base_color(int id, vec2 uv) {
	if (id == SEA) {
		return sea_color.rgb;
	}
	if (id == BACKGROUND) {
		return background_color.rgb;
	}
	if (mode == 1) {
		return texture(provinces, uv).rgb;
	}
	return paint_color(id).rgb;
}

void fragment() {
	int id = id_at(UV);
	vec3 col = base_color(id, UV);
	if (occupation_stripes && id > 0) {
		vec3 owner_rgb = owner_color(id).rgb;
		if (owner_rgb != col) {
			// Diagonal stripes of constant screen width: the occupier's colour over the owner's.
			vec2 map_px = UV * map_size;
			float px_per_screen = max(fwidth(UV.x) * map_size.x, 0.001);
			float band = fract((map_px.x + map_px.y) / (px_per_screen * stripe_px));
			col = band < 0.5 ? col : owner_rgb;
		}
	}

	if ((diplomacy || hatch_marks) && id > 0) {
		vec4 mark = mark_color(id);
		if (mark.a > 0.5) {
			// Hatching for guaranteed nations.
			vec2 map_px = UV * map_size;
			float px_per_screen = max(fwidth(UV.x) * map_size.x, 0.001);
			float band = fract((map_px.x - map_px.y) / (px_per_screen * stripe_px * 0.7));
			col = band < 0.5 ? col : mark.rgb;
		}
	}

	// Border width stays ~constant on screen but never drops below one bitmap texel.
	vec2 step_uv = max(fwidth(UV) * border_px, 1.0 / map_size);
	vec2 offsets[4] = vec2[](vec2(step_uv.x, 0.0), vec2(-step_uv.x, 0.0), vec2(0.0, step_uv.y), vec2(0.0, -step_uv.y));
	float province_edge = 0.0;
	float owner_edge = 0.0;
	float coast = 0.0;
	float bloc_edge = 0.0;
	vec3 bloc_rgb = vec3(0.0);
	for (int i = 0; i < 4; i++) {
		int n = id_at(UV + offsets[i]);
		if (n == id) {
			continue;
		}
		if (id > 0 && n > 0) {
			province_edge = 1.0;
			if (owner_color(id).rgb != owner_color(n).rgb) {
				owner_edge = 1.0;
			}
			if (diplomacy) {
				vec4 b1 = bloc_color(id);
				vec4 b2 = bloc_color(n);
				if (b1 != b2) {
					bloc_edge = 1.0;
					bloc_rgb = b1.a > 0.5 ? b1.rgb : b2.rgb;
				}
			}
		} else if (id > 0 || n > 0) {
			coast = 1.0;
		}
	}
	col = mix(col, vec3(0.0), province_edge * 0.25);
	col = mix(col, vec3(0.0), owner_edge * 0.5);
	col = mix(col, vec3(0.0), coast * 0.45);
	col = mix(col, bloc_rgb, bloc_edge * 0.9);

	if (id == SEA) {
		int zone = zone_at(UV);
		if (zone > 0 && zone_paint) {
			vec4 tint = texelFetch(zone_colors, ivec2(zone, 0), 0);
			col = mix(col, tint.rgb, tint.a);
		}
		if (zone > 0) {
			if (show_zones || zone == selected_zone) {
				for (int i = 0; i < 4; i++) {
					vec2 o = offsets[i] * 1.5;
					if (id_at(UV + o) == SEA && zone_at(UV + o) != zone) {
						col = mix(col, vec3(1.0), 0.45);
						break;
					}
				}
			}
			if (zone == selected_zone) {
				col = mix(col, vec3(1.0), 0.2);
			} else if (zone == hover_zone && show_zones) {
				col = mix(col, vec3(1.0), 0.08);
			}
		}
	}
	if (id > 0 && id == hover_id) {
		col = mix(col, vec3(1.0), 0.15);
	}
	if (id > 0 && id == selected_id) {
		col = mix(col, vec3(1.0), 0.35);
	}
	COLOR = vec4(col, 1.0);
}
