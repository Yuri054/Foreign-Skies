class_name Icons
extends RefCounted
## Small icons for the interface, drawn from SVG text so the game needs no image files: `Icons.get_icon("coin")`
## is a texture sized for a line of text. Names: coin, tax, factory, people, soldier, wheat, coal, iron, wood,
## star, flame, scroll, shield, anchor, hammer, flag, scales, chart, cannon.

const SIZE := 18

const _SHAPES := {
	"coin": '<circle cx="12" cy="12" r="9.2" fill="none" stroke="#d9c28c" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/><circle cx="12" cy="12" r="5.6" fill="none" stroke="#d9c28c" stroke-width="1.2" stroke-linecap="round" stroke-linejoin="round"/><path d="M12 8.6v6.8M9.8 10.4h3.4a1.3 1.3 0 0 1 0 2.600h-2.600a1.300 1.300 0 0 0 0 2.600h3.600" fill="none" stroke="#d9c28c" stroke-width="1.2" stroke-linecap="round" stroke-linejoin="round"/>',
	"tax": '<path d="M6 3h9l4 4v14H6z" fill="none" stroke="#d9c28c" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/><path d="M15 3v4h4M9 11h7M9 14.500h7M9 18h4" fill="none" stroke="#d9c28c" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round"/>',
	"factory": '<path d="M3 21V11l5 3v-3l5 3v-3l5 3V5h3v16z" fill="#d9c28c"/><path d="M7 18h2M12 18h2M17 18h2" stroke="#7e6b42" stroke-width="1.600" stroke-linecap="round"/>',
	"people": '<circle cx="9" cy="8" r="3.300" fill="#d9c28c"/><path d="M2.500 20c0-3.800 2.800-6 6.500-6s6.500 2.200 6.500 6z" fill="#d9c28c"/><circle cx="17" cy="9" r="2.700" fill="#7e6b42"/><path d="M15.500 14.300c3-.5 6 1 6 5.700h-4.300c0-2.300-.6-4.100-1.700-5.700z" fill="#7e6b42"/>',
	"soldier": '<path d="M5 20L17 6.500M19 20L7 6.500" fill="none" stroke="#d9c28c" stroke-width="2.200" stroke-linecap="round"/><path d="M17 6.500l1.800-3.800.9 4.800zM7 6.500L5.200 2.700l-.9 4.800z" fill="#d9c28c"/><path d="M3.500 20.500l3-2M20.500 20.500l-3-2" stroke="#d9c28c" stroke-width="3" stroke-linecap="round"/>',
	"wheat": '<path d="M12 22V9" fill="none" stroke="#d9c28c" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/><g fill="#d9c28c"><ellipse cx="12" cy="5" rx="1.900" ry="3.100"/><ellipse cx="8.300" cy="10" rx="1.800" ry="3" transform="rotate(-38 8.300 10)"/><ellipse cx="15.700" cy="10" rx="1.800" ry="3" transform="rotate(38 15.700 10)"/><ellipse cx="8.300" cy="15.500" rx="1.800" ry="3" transform="rotate(-38 8.300 15.500)"/><ellipse cx="15.700" cy="15.500" rx="1.800" ry="3" transform="rotate(38 15.700 15.500)"/></g>',
	"coal": '<path d="M3.500 16.500l2.500-8.500 6-4.500 6.500 4 2.500 8-6 4.500H8.500z" fill="#d9c28c"/><path d="M6 8l5.500 3 6.500-3.500M11.500 11v9" stroke="#7e6b42" stroke-width="1.400" fill="none" stroke-linejoin="round"/>',
	"iron": '<path d="M6 11l2-4h8l2 4z" fill="#d9c28c"/><path d="M2.500 19l2.500-6h14l2.500 6z" fill="#d9c28c"/><path d="M5 16h14" stroke="#7e6b42" stroke-width="1.300"/>',
	"wood": '<g fill="#d9c28c"><circle cx="7" cy="16.500" r="4.600"/><circle cx="17" cy="16.500" r="4.600"/><circle cx="12" cy="7.500" r="4.600"/></g><g fill="none" stroke="#7e6b42" stroke-width="1.200"><circle cx="7" cy="16.500" r="2.200"/><circle cx="17" cy="16.500" r="2.200"/><circle cx="12" cy="7.500" r="2.200"/></g>',
	"star": '<path d="M12 2.500l2.800 6.200 6.700.7-5 4.500 1.400 6.600-5.900-3.400-5.900 3.400 1.400-6.600-5-4.500 6.700-.7z" fill="#d9c28c"/>',
	"flame": '<path d="M12 2c.8 4.500 6.200 6.500 6.200 12.200a6.200 6.200 0 0 1-12.400 0c0-3 1.800-4.600 2.600-7.200 1.700 1.200 2.600 2.800 3 4.200.9-3 .9-6 .6-9.200z" fill="#d9c28c"/><path d="M12 21.500a3 3 0 0 1-3-3c0-1.900 2.200-3 3-5.500 1.900 1.800 3 3.700 3 5.500a3 3 0 0 1-3 3z" fill="#7e6b42"/>',
	"scroll": '<path d="M7 4h11v13a3 3 0 0 1-3 3H6a3 3 0 0 0 3-3V6a2 2 0 0 0-2-2z" fill="none" stroke="#d9c28c" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/><path d="M12 9h4M12 12.500h4" fill="none" stroke="#d9c28c" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round"/><path d="M7 4a2 2 0 0 0-2 2v1.500h2" fill="none" stroke="#d9c28c" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round"/>',
	"shield": '<path d="M12 2.500l7.500 2.800v6c0 4.800-3.300 8.600-7.500 10.200-4.200-1.600-7.500-5.400-7.500-10.200v-6z" fill="#d9c28c"/><path d="M12 2.500v19" stroke="#7e6b42" stroke-width="1.400"/>',
	"anchor": '<circle cx="12" cy="5" r="2.400" fill="none" stroke="#d9c28c" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/><path d="M12 7.400V21M7.500 11h9M4 14.500c.8 4 4 6.500 8 6.500s7.200-2.500 8-6.500" fill="none" stroke="#d9c28c" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"/>',
	"hammer": '<path d="M4 6.500l3-3 4 .8 3 3-1.500 1.500L10 7 8 9l9.500 9.500a1.800 1.800 0 0 1-2.500 2.500L5.500 11.500 7.500 9.500z" fill="#d9c28c"/>',
	"flag": '<path d="M5 22V3" fill="none" stroke="#d9c28c" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/><path d="M5 4.500h14.500L16 9l3.500 4.500H5z" fill="#d9c28c"/>',
	"scales": '<path d="M12 3.500V20M7 21h10M4 7h16" fill="none" stroke="#d9c28c" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/><path d="M4 7l-2.500 6.500a3.500 2.800 0 0 0 5 0zM20 7l-2.500 6.500a3.500 2.800 0 0 0 5 0z" fill="#d9c28c"/>',
	"chart": '<path d="M3 3v18h18" fill="none" stroke="#d9c28c" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/><rect x="6.500" y="12" width="3.200" height="6.500" fill="#d9c28c"/><rect x="11.300" y="7" width="3.200" height="11.500" fill="#d9c28c"/><rect x="16.100" y="10" width="3.200" height="8.500" fill="#d9c28c"/>',
	"cannon": '<path d="M3 11.500l11.500-3.600 2.800 5.600-11.800 3.400z" fill="#d9c28c"/><circle cx="8.500" cy="17.500" r="3.600" fill="none" stroke="#d9c28c" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/><path d="M19 7.500l2-1.200M19.800 11l2.300.4" fill="none" stroke="#d9c28c" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/>',
}

static var _cache := {}


## The icon as a texture about `size` pixels square (at the UI's current scale), or null for an unknown name.
static func get_icon(icon_name: String, size := SIZE) -> Texture2D:
	var key := "%s@%d" % [icon_name, size]
	if _cache.has(key):
		return _cache[key]
	var shape: String = _SHAPES.get(icon_name, "")
	if shape.is_empty():
		return null
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24">%s</svg>' % shape
	var img := Image.new()
	if img.load_svg_from_string(svg, float(size) / 24.0) != OK:
		return null
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


## A TextureRect of the icon, for putting beside a label. `tip` becomes its tooltip.
static func rect(icon_name: String, tip := "", size := SIZE) -> TextureRect:
	var r := TextureRect.new()
	r.texture = get_icon(icon_name, size)
	r.custom_minimum_size = Vector2(size, size)
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.mouse_filter = Control.MOUSE_FILTER_PASS if not tip.is_empty() else Control.MOUSE_FILTER_IGNORE
	r.tooltip_text = tip
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return r


static func names() -> Array:
	return _SHAPES.keys()
