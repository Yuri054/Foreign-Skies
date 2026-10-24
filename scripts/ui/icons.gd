class_name Icons
extends RefCounted
## Small icons for the interface, drawn from SVG text so the game needs no image files: `Icons.get_icon("coin")`
## is a texture sized for a line of text. Names: coin, tax, factory, people, soldier, wheat, coal, iron, wood,
## star, flame, scroll, shield, anchor, hammer, flag, scales, chart, cannon.

const SIZE := 18

const _SHAPES := {
	"coin": '<circle cx="12" cy="12" r="10" fill="#e0b43c" stroke="#8a6a12" stroke-width="2"/><path d="M12 6v12M9 9.5c0-1.5 1.5-2 3-2s3 .6 3 2-1.5 2-3 2.5-3 1-3 2.5 1.5 2 3 2 3-.5 3-2" fill="none" stroke="#7a5a10" stroke-width="1.800"/>',
	"tax": '<rect x="4" y="3" width="16" height="18" rx="2" fill="#d8d0b8" stroke="#6b6450" stroke-width="1.600"/><path d="M8 8h8M8 12h8M8 16h5" stroke="#6b6450" stroke-width="1.600"/><circle cx="17" cy="17" r="4.500" fill="#e0b43c" stroke="#8a6a12" stroke-width="1.400"/>',
	"factory": '<path d="M2 21V11l6 4v-4l6 4v-4l4 3V4h4v17z" fill="#9aa4b0" stroke="#3c4652" stroke-width="1.600" stroke-linejoin="round"/><path d="M5 17h2M10 17h2M15 17h2" stroke="#3c4652" stroke-width="1.600"/>',
	"people": '<circle cx="8.500" cy="8" r="3.500" fill="#c9b79c" stroke="#5e4f3a" stroke-width="1.400"/><circle cx="16.500" cy="9" r="3" fill="#b8a688" stroke="#5e4f3a" stroke-width="1.400"/><path d="M2 20c0-4 3-6 6.500-6s6.500 2 6.500 6zM14 20c.3-3 2-4.700 4.500-4.700 2.5 0 3.500 1.700 3.500 4.700z" fill="#7d8fa6" stroke="#3a4656" stroke-width="1.400" stroke-linejoin="round"/>',
	"soldier": '<path d="M6 11a6 6 0 0 1 12 0z" fill="#6f7d5c" stroke="#38412c" stroke-width="1.600"/><path d="M4 11h16" stroke="#38412c" stroke-width="2"/><circle cx="12" cy="15" r="3.200" fill="#c9b79c" stroke="#5e4f3a" stroke-width="1.300"/><path d="M5 22c0-3.500 3-5 7-5s7 1.500 7 5z" fill="#6f7d5c" stroke="#38412c" stroke-width="1.400" stroke-linejoin="round"/>',
	"wheat": '<path d="M12 22V8" stroke="#8a6a12" stroke-width="1.800"/><g fill="#e0b43c" stroke="#8a6a12" stroke-width="1.100"><ellipse cx="12" cy="5" rx="2" ry="3.200"/><ellipse cx="8.200" cy="10" rx="2" ry="3.200" transform="rotate(-35 8.200 10)"/><ellipse cx="15.800" cy="10" rx="2" ry="3.200" transform="rotate(35 15.800 10)"/><ellipse cx="8.200" cy="15.500" rx="2" ry="3.200" transform="rotate(-35 8.200 15.500)"/><ellipse cx="15.800" cy="15.500" rx="2" ry="3.200" transform="rotate(35 15.800 15.500)"/></g>',
	"coal": '<path d="M4 17l2-9 6-4 7 4 2 8-6 4H9z" fill="#3a3a40" stroke="#17171a" stroke-width="1.600" stroke-linejoin="round"/><path d="M8 9l4 2 5-3M12 11v8" stroke="#7b7b86" stroke-width="1.200" fill="none"/>',
	"iron": '<path d="M3 17l3-8h12l3 8z" fill="#b87a52" stroke="#6a4128" stroke-width="1.600" stroke-linejoin="round"/><path d="M6 17l2-5h8l2 5" fill="#d89a70" stroke="#6a4128" stroke-width="1.200"/><path d="M3 17h18v3H3z" fill="#8a8f98" stroke="#454a52" stroke-width="1.400"/>',
	"wood": '<rect x="3" y="14" width="18" height="6" rx="3" fill="#a0724a" stroke="#5c3d22" stroke-width="1.500"/><rect x="5" y="6" width="14" height="6" rx="3" fill="#b88458" stroke="#5c3d22" stroke-width="1.500"/><circle cx="19" cy="9" r="1.800" fill="none" stroke="#5c3d22" stroke-width="1.100"/><circle cx="19" cy="17" r="1.800" fill="none" stroke="#5c3d22" stroke-width="1.100"/>',
	"star": '<path d="M12 2l2.900 6.300 6.800.7-5.100 4.600 1.500 6.700L12 16.800l-6.100 3.500 1.500-6.700L2.300 9l6.800-.7z" fill="#e0b43c" stroke="#8a6a12" stroke-width="1.400" stroke-linejoin="round"/>',
	"scroll": '<path d="M6 4h12v14a3 3 0 0 1-3 3H5a3 3 0 0 0 3-3z" fill="#e4dcc0" stroke="#6b6450" stroke-width="1.500" stroke-linejoin="round"/><path d="M9 8h6M9 11h6M9 14h4" stroke="#6b6450" stroke-width="1.400"/><path d="M6 4a2 2 0 0 0-2 2v1h2" fill="none" stroke="#6b6450" stroke-width="1.400"/>',
	"shield": '<path d="M12 2l8 3v6c0 5-3.500 9-8 11-4.500-2-8-6-8-11V5z" fill="#6c86b0" stroke="#2c3e5c" stroke-width="1.600" stroke-linejoin="round"/><path d="M12 2v20" stroke="#2c3e5c" stroke-width="1.200"/>',
	"anchor": '<circle cx="12" cy="5" r="2.5" fill="none" stroke="#8aa0bc" stroke-width="1.800"/><path d="M12 7.500V21M7 11h10M4 15c1 4 4 6 8 6s7-2 8-6" fill="none" stroke="#8aa0bc" stroke-width="1.900" stroke-linecap="round"/>',
	"hammer": '<path d="M13 8l8 8-3 3-8-8z" fill="#8a8f98" stroke="#454a52" stroke-width="1.400" stroke-linejoin="round"/><path d="M3 21l8-8" stroke="#8a5e32" stroke-width="3" stroke-linecap="round"/><path d="M7 4l6 0 3 3-2 2-3-3-4 0z" fill="#8a8f98" stroke="#454a52" stroke-width="1.300" stroke-linejoin="round"/>',
	"flag": '<path d="M5 22V3" stroke="#6a5a48" stroke-width="2" stroke-linecap="round"/><path d="M5 4h14l-3 4.500 3 4.500H5z" fill="#c05a4c" stroke="#6a2c24" stroke-width="1.400" stroke-linejoin="round"/>',
	"scales": '<path d="M12 3v17M7 21h10M4 7h16" stroke="#c8c0a0" stroke-width="1.800" stroke-linecap="round"/><path d="M4 7l-2.5 6a3.500 3 0 0 0 5 0zM20 7l-2.5 6a3.500 3 0 0 0 5 0z" fill="#c8c0a0" stroke="#6b6450" stroke-width="1.100" stroke-linejoin="round"/>',
	"chart": '<path d="M3 21h18M3 3v18" stroke="#8aa0bc" stroke-width="1.800"/><rect x="6" y="12" width="3.500" height="8" fill="#6c86b0"/><rect x="11" y="7" width="3.500" height="13" fill="#7ba06c"/><rect x="16" y="10" width="3.500" height="10" fill="#c8a45a"/>',
	"flame": '<path d="M12 2c1 4 6 6 6 12a6 6 0 0 1-12 0c0-3 2-4 2-7 2 1 3 3 3 4 1-3 1-6 1-9z" fill="#e07a30" stroke="#8a3a10" stroke-width="1.500" stroke-linejoin="round"/><path d="M12 22a3 3 0 0 1-3-3c0-2 3-3 3-6 2 2 3 4 3 6a3 3 0 0 1-3 3z" fill="#f2c24a"/>',
	"cannon": '<path d="M3 11l11-3 3 5-11 3z" fill="#5c6068" stroke="#26292e" stroke-width="1.500" stroke-linejoin="round"/><circle cx="8" cy="18" r="3.500" fill="#8a5e32" stroke="#4a3018" stroke-width="1.400"/><path d="M19 7l2-1M19.500 11l2 .5M18 4l1 -1.500" stroke="#e0b43c" stroke-width="1.500" stroke-linecap="round"/>',
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
