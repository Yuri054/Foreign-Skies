class_name FlagIcon
extends Control
## A nation's flag: the picture in assets/flags (see tools/build_flags.gd), cropped to fit the
## box. A nation without a picture gets the flag drawn from simple shapes (bands, crosses, a disc
## or a crescent) when there is a design for it here, else a plain swatch of its map colour. Set
## `tag` to choose it.

const FLAG_DIR := "res://assets/flags/"
static var _textures := {}


## The picture of a nation's flag, or null if there is none.
static func texture_of(flag_tag: String) -> Texture2D:
	if not _textures.has(flag_tag):
		var path := FLAG_DIR + flag_tag + ".png"
		_textures[flag_tag] = load(path) if ResourceLoader.exists(path) else null
	return _textures[flag_tag]


## How each 1914 flag is built. Keys: h / v (bands, with optional weights), field plus one of
## cross, nordic, crescent, disc, or the special designs union and greek.
const DESIGNS := {
	"FRA": {"v": ["#0055a4", "#ffffff", "#ef4135"]},
	"GER": {"h": ["#000000", "#ffffff", "#dd0000"]},
	"BEL": {"v": ["#000000", "#fae042", "#ed2939"]},
	"NED": {"h": ["#ae1c28", "#ffffff", "#21468b"]},
	"LUX": {"h": ["#ed2939", "#ffffff", "#00a1de"]},
	"SUI": {"field": "#da291c", "cross": "#ffffff"},
	"ITA": {"v": ["#009246", "#ffffff", "#ce2b37"]},
	"ESP": {"h": ["#aa151b", "#f1bf00", "#aa151b"], "weights": [1, 2, 1]},
	"POR": {"v": ["#046a38", "#da291c"], "weights": [2, 3]},
	"DEN": {"field": "#c8102e", "nordic": "#ffffff"},
	"AUH": {"h": ["#c8102e", "#ffffff", "#c8102e"]},
	"SRB": {"h": ["#c6363c", "#0c4076", "#ffffff"]},
	"MNE": {"h": ["#c40308", "#1d3c85", "#ffffff"]},
	"ALB": {"field": "#e41e20", "disc": "#111111"},
	"BUL": {"h": ["#ffffff", "#00966e", "#d62612"]},
	"ROM": {"v": ["#002b7f", "#fcd116", "#ce1126"]},
	"OTT": {"field": "#e30a17", "crescent": "#ffffff"},
	"RUS": {"h": ["#ffffff", "#0039a6", "#d52b1e"]},
	"GBR": {"union": true},
	"GRE": {"greek": true},
}

var tag := "":
	set(value):
		tag = value
		queue_redraw()


func _init(p_tag := "") -> void:
	custom_minimum_size = Vector2(60, 40)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	tag = p_tag


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var picture := texture_of(tag)
	if picture != null:
		# Fill the box and crop what spills over, so a flag never looks squashed.
		var full := picture.get_size()
		var scale := maxf(r.size.x / full.x, r.size.y / full.y)
		var shown := r.size / scale
		draw_texture_rect_region(picture, r, Rect2((full - shown) / 2.0, shown))
		return
	var design: Dictionary = DESIGNS.get(tag, {})
	if design.is_empty():
		var n: Nation = GameState.nations.get(tag)
		draw_rect(r, n.color if n != null else Color(0.5, 0.5, 0.5))
	elif design.has("h") or design.has("v"):
		_draw_bands(r, design)
	elif design.has("union"):
		_draw_union(r)
	elif design.has("greek"):
		_draw_greek(r)
	else:
		draw_rect(r, Color(design.field))
		if design.has("cross"):
			var arm := r.size.y * 0.2
			var length := r.size.y * 0.62
			var c := r.size * 0.5
			draw_rect(Rect2(c - Vector2(arm * 0.5, length * 0.5), Vector2(arm, length)), Color(design.cross))
			draw_rect(Rect2(c - Vector2(length * 0.5, arm * 0.5), Vector2(length, arm)), Color(design.cross))
		elif design.has("nordic"):
			var w := r.size.y * 0.16
			var x := r.size.x * 0.34
			draw_rect(Rect2(x - w * 0.5, 0, w, r.size.y), Color(design.nordic))
			draw_rect(Rect2(0, r.size.y * 0.5 - w * 0.5, r.size.x, w), Color(design.nordic))
		elif design.has("crescent"):
			var c := Vector2(r.size.x * 0.42, r.size.y * 0.5)
			draw_circle(c, r.size.y * 0.3, Color(design.crescent))
			draw_circle(c + Vector2(r.size.y * 0.07, 0), r.size.y * 0.25, Color(design.field))
			draw_circle(Vector2(r.size.x * 0.62, r.size.y * 0.5), r.size.y * 0.07, Color(design.crescent))
		elif design.has("disc"):
			draw_circle(r.size * 0.5, r.size.y * 0.22, Color(design.disc))
	draw_rect(r, Color(0, 0, 0, 0.55), false, 1.0)


func _draw_bands(r: Rect2, design: Dictionary) -> void:
	var colors: Array = design.get("h", design.get("v"))
	var vertical: bool = design.has("v")
	var weights: Array = design.get("weights", [])
	var total := 0.0
	for i in colors.size():
		total += float(weights[i]) if i < weights.size() else 1.0
	var at := 0.0
	for i in colors.size():
		var share: float = (float(weights[i]) if i < weights.size() else 1.0) / total
		var band := Rect2(at * r.size.x, 0, share * r.size.x, r.size.y) if vertical else Rect2(0, at * r.size.y, r.size.x, share * r.size.y)
		draw_rect(band, Color(colors[i]))
		at += share


func _draw_union(r: Rect2) -> void:
	var red := Color("#c8102e")
	var white := Color.WHITE
	draw_rect(r, Color("#012169"))
	var a := Vector2.ZERO
	var b := r.size
	var c := Vector2(r.size.x, 0)
	var d := Vector2(0, r.size.y)
	for pair: Array in [[a, b], [c, d]]:
		draw_line(pair[0], pair[1], white, r.size.y * 0.22)
		draw_line(pair[0], pair[1], red, r.size.y * 0.08)
	var mid := r.size * 0.5
	draw_rect(Rect2(0, mid.y - r.size.y * 0.17, r.size.x, r.size.y * 0.34), white)
	draw_rect(Rect2(mid.x - r.size.y * 0.17, 0, r.size.y * 0.34, r.size.y), white)
	draw_rect(Rect2(0, mid.y - r.size.y * 0.1, r.size.x, r.size.y * 0.2), red)
	draw_rect(Rect2(mid.x - r.size.y * 0.1, 0, r.size.y * 0.2, r.size.y), red)


func _draw_greek(r: Rect2) -> void:
	var blue := Color("#0d5eaf")
	var h := r.size.y / 9.0
	for i in 9:
		draw_rect(Rect2(0, i * h, r.size.x, h + 0.5), blue if i % 2 == 0 else Color.WHITE)
	var canton := Vector2(h * 5.0, h * 5.0)
	draw_rect(Rect2(Vector2.ZERO, canton), blue)
	var arm := h * 1.1
	draw_rect(Rect2(canton.x * 0.5 - arm * 0.5, 0, arm, canton.y), Color.WHITE)
	draw_rect(Rect2(0, canton.y * 0.5 - arm * 0.5, canton.x, arm), Color.WHITE)
