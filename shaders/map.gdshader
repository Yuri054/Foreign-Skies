shader_type canvas_item;
// Paints the province bitmap: owner colors, borders and selection are all resolved here,
// so changing ownership only means rewriting one pixel of the `lookup` texture.

uniform sampler2D provinces : filter_nearest, repeat_disable;
uniform sampler2D provinces_half : filter_nearest, repeat_disable;    // the same at half size, for far zooms
uniform sampler2D provinces_quarter : filter_nearest, repeat_disable; // and at quarter size
uniform sampler2D lookup : filter_nearest, repeat_disable;  // color to paint each province
uniform sampler2D owners : filter_nearest, repeat_disable;  // owner color, for borders
uniform sampler2D marks : filter_nearest, repeat_disable;   // diplomacy: hatch colour, alpha > 0.5 = hatched
uniform sampler2D blocs : filter_nearest, repeat_disable;   // diplomacy: bloc colour, alpha > 0.5 = in a bloc
uniform sampler2D sea_zones : filter_nearest, repeat_disable; // red channel = sea zone id
uniform bool show_zones = false;
uniform sampler2D zone_colors : filter_nearest, repeat_disable; // 64x1: tint of each sea zone, alpha 0 = none
uniform bool zone_paint = false;
uniform bool hatch_marks = false; // hatch the provinces `marks` flags, outside the diplomacy mode too
uniform sampler2D plans : filter_nearest, repeat_disable;   // plans of attack: stripe colour, alpha > 0.5 = in a planned advance
uniform bool plan_stripes = false;
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

// The painted land texture (data/map/land.jpg) blended into the land colours: how much (0 to 1) depends
// on how far the camera is zoomed in, and on the map mode (land_on).
uniform sampler2D land_texture : filter_linear_mipmap, repeat_disable;
uniform bool land_on = false;
uniform float land_blend = 0.0;
uniform float land_natural = 0.3;   // share of the ground's own colour in the blend; the rest is the nation's colour
uniform float land_washed = 1.0;    // how much of the ground's colour (against grey) is kept

const int SEA = 0;
const int BACKGROUND = -1;

// Which picture of the provinces to read: 0 full size, 1 half, 2 quarter, by how many map pixels a screen pixel covers.
int lod_for(vec2 uv) {
	float px = max(fwidth(uv.x) * map_size.x, fwidth(uv.y) * map_size.y);
	return px >= 3.0 ? 2 : (px >= 1.6 ? 1 : 0);
}

int id_at(vec2 uv, int lod) {
	vec3 raw = lod == 2 ? texture(provinces_quarter, uv).rgb : (lod == 1 ? texture(provinces_half, uv).rgb : texture(provinces, uv).rgb);
	ivec3 c = ivec3(round(raw * 255.0));
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
	int lod = lod_for(UV);
	int id = id_at(UV, lod);
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

	if (land_on && land_blend > 0.0 && id != SEA) {
		vec3 natural = texture(land_texture, UV).rgb;
		float grey = dot(natural, vec3(0.299, 0.587, 0.114));
		// The nation's colour is lit by the ground's light and dark; the ground's own colours, washed
		// out so they do not turn a nation's colour to mud, come in over it the closer the camera is.
		vec3 lit_nation = clamp(col * (0.45 + 1.0 * grey), 0.0, 1.0);
		vec3 washed = mix(vec3(grey), natural, land_washed);
		vec3 blended = mix(lit_nation, washed, land_natural);
		float strength = land_blend * (id == BACKGROUND ? 0.9 : 1.0);
		col = mix(col, blended, strength);
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

	if (plan_stripes && id > 0) {
		ivec2 pp = ivec2(id % lookup_width, id / lookup_width);
		vec4 plan = texelFetch(plans, pp, 0);
		if (plan.a > 0.5) {
			// The ground a plan of attack means to take: wide diagonal stripes in the army's colour, half seen through.
			vec2 map_px = UV * map_size;
			float px_per_screen = max(fwidth(UV.x) * map_size.x, 0.001);
			float band = fract((map_px.x - map_px.y) / (px_per_screen * stripe_px * 1.6));
			col = mix(col, plan.rgb, band < 0.35 ? 0.55 : 0.12);
		}
	}

	// Border width stays ~constant on screen but never drops below one bitmap texel.
	vec2 step_uv = max(fwidth(UV) * border_px, float(1 << lod) / map_size);
	vec2 offsets[4] = vec2[](vec2(step_uv.x, 0.0), vec2(-step_uv.x, 0.0), vec2(0.0, step_uv.y), vec2(0.0, -step_uv.y));
	float province_edge = 0.0;
	float owner_edge = 0.0;
	float coast = 0.0;
	float bloc_edge = 0.0;
	vec3 bloc_rgb = vec3(0.0);
	for (int i = 0; i < 4; i++) {
		int n = id_at(UV + offsets[i], lod);
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
	// Where the ground's colours wash out the nations' (close up), a national border also shows as a band of each
	// nation's own colour a few pixels wide on its side, and its lines are darker, so it still reads.
	float ground = land_on ? land_blend * land_natural : 0.0;
	if (id > 0 && ground > 0.0) {
		float band = 0.0;
		for (int i = 0; i < 4; i++) {
			int n = id_at(UV + offsets[i] * 6.0, lod);
			if (n > 0 && n != id && owner_color(n).rgb != owner_color(id).rgb) {
				band = 1.0;
			}
		}
		col = mix(col, owner_color(id).rgb, band * clamp(ground * 1.8, 0.0, 0.85));
	}
	col = mix(col, vec3(0.0), province_edge * (0.25 + 0.2 * ground));
	col = mix(col, vec3(0.0), owner_edge * (0.5 + 0.5 * ground));
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
					if (id_at(UV + o, lod) == SEA && zone_at(UV + o) != zone) {
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
