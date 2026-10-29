class_name Icons
extends RefCounted
## Small icons for the interface, drawn from SVG text so the game needs no image files: `Icons.get_icon("coin")`
## is a texture sized for a line of text. Names: coin, tax, factory, people, soldier, wheat, coal, iron, wood,
## star, flame, scroll, shield, anchor, hammer, flag, scales, chart, cannon; and the battle plan tools: play, pause,
## chevron1-3, frontline, offensive, spearhead, fallback, garrison, invasion, naval_support, paradrop, unassign, edit,
## delete, plus.

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
	"play": '<path d="M7 4.500v15l12.500-7.500z" fill="#d9c28c"/>',
	"pause": '<rect x="6" y="4.500" width="4.200" height="15" fill="#d9c28c"/><rect x="13.800" y="4.500" width="4.200" height="15" fill="#d9c28c"/>',
	"chevron1": '<path d="M9 5l7 7-7 7" fill="none" stroke="#d9c28c" stroke-width="2.800" stroke-linecap="round" stroke-linejoin="round"/>',
	"chevron2": '<path d="M5 5l7 7-7 7M12.500 5l7 7-7 7" fill="none" stroke="#d9c28c" stroke-width="2.600" stroke-linecap="round" stroke-linejoin="round"/>',
	"chevron3": '<path d="M2.500 6l6 6-6 6M9 6l6 6-6 6M15.500 6l6 6-6 6" fill="none" stroke="#d9c28c" stroke-width="2.200" stroke-linecap="round" stroke-linejoin="round"/>',
	"frontline": '<path d="M2 16c3.500-5 6.500-1 9.500-5s6-4 10.500-6" fill="none" stroke="#d9c28c" stroke-width="2.600" stroke-linecap="round"/><path d="M4.500 14.500l1.400 3.200M8.300 12.800l1 3.400M12 10.300l1.800 3M15.600 8l1.800 3M19.300 6.300l1.700 3" stroke="#d9c28c" stroke-width="1.600" stroke-linecap="round"/>',
	"offensive": '<path d="M2.500 19.500c3.500-.5 8.500-3.500 11.500-8.500l-3-1.700L21 4l-.8 10.800-2.700-1.700C14 18.500 8.500 21.500 2.500 21.500z" fill="#d9c28c"/>',
	"spearhead": '<path d="M4 20L15 9" stroke="#d9c28c" stroke-width="2.800" stroke-linecap="round"/><path d="M21 3l-10.500 2.600 7.900 7.900z" fill="#d9c28c"/>',
	"fallback": '<path d="M2.500 8h4M10 8h4M17.500 8h4" stroke="#d9c28c" stroke-width="2.600" stroke-linecap="round"/><path d="M12 11.500v8M8 16l4 4 4-4" fill="none" stroke="#d9c28c" stroke-width="2.200" stroke-linecap="round" stroke-linejoin="round"/>',
	"garrison": '<path d="M12 2.500l7.500 2.800v6c0 4.800-3.300 8.600-7.500 10.200-4.200-1.600-7.500-5.400-7.500-10.200v-6z" fill="#d9c28c"/><path d="M8.500 9h7v6h-7zM8.500 9V7.300M12 9V7.300M15.500 9V7.300" fill="#7e6b42" stroke="#7e6b42" stroke-width="1.300"/>',
	"invasion": '<circle cx="7.500" cy="5" r="1.800" fill="none" stroke="#d9c28c" stroke-width="1.700"/><path d="M7.500 6.800v12M4.500 10h6M2.500 15c.6 2.800 2.500 4.300 5 4.300s4.400-1.500 5-4.300" fill="none" stroke="#d9c28c" stroke-width="1.800" stroke-linecap="round" stroke-linejoin="round"/><path d="M13 13.500l7.500-7.500M15.500 5.500h5v5" fill="none" stroke="#d9c28c" stroke-width="2.200" stroke-linecap="round" stroke-linejoin="round"/>',
	"naval_support": '<path d="M2 15.500h20l-3.200 4.500H5.200z" fill="#d9c28c"/><path d="M7 15.500V12h6.500v3.500M10 12V9.300h2.200" fill="none" stroke="#d9c28c" stroke-width="1.700" stroke-linejoin="round"/><path d="M13.500 10.500l4.500-4.500" stroke="#d9c28c" stroke-width="1.700" stroke-linecap="round"/><circle cx="19.700" cy="4.300" r="2.200" fill="#7e6b42" stroke="#d9c28c" stroke-width="1.200"/>',
	"paradrop": '<path d="M3 11a9 7.500 0 0 1 18 0z" fill="#d9c28c"/><path d="M3.500 11l8.500 7.500L20.500 11M12 11v7.500" fill="none" stroke="#d9c28c" stroke-width="1.200"/><circle cx="12" cy="20" r="1.900" fill="#d9c28c"/>',
	"unassign": '<circle cx="9.500" cy="7.500" r="3.400" fill="#d9c28c"/><path d="M2.500 20c0-4 3-6.300 7-6.300s7 2.300 7 6.300z" fill="#d9c28c"/><path d="M16 10h6" stroke="#d9c28c" stroke-width="2.400" stroke-linecap="round"/>',
	"edit": '<path d="M4 20l1.100-4.600L15.800 4.700l3.500 3.500L8.600 18.900z" fill="#d9c28c"/><path d="M13.700 6.800l3.500 3.500M5.100 15.400l3.500 3.500" stroke="#7e6b42" stroke-width="1.300"/>',
	"delete": '<path d="M4 6.500h16M9.500 6.500V4h5v2.500" fill="none" stroke="#d9c28c" stroke-width="1.900" stroke-linecap="round" stroke-linejoin="round"/><path d="M6 8.500h12l-1.100 12.500H7.100z" fill="#d9c28c"/><path d="M10 11v7.500M14 11v7.500" stroke="#7e6b42" stroke-width="1.400" stroke-linecap="round"/>',
	"plus": '<path d="M12 4.500v15M4.500 12h15" stroke="#d9c28c" stroke-width="2.800" stroke-linecap="round"/>'
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
