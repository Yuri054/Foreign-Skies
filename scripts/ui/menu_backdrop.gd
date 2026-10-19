extends TextureRect
## The picture behind the main menu: the political map of the scenario's start, drawn small from
## the province bitmap and the map file's owners, darkened, and drifting slowly across the
## screen. Built once and kept, so going back to the menu is instant.

## One sample every STRIDE bitmap pixels.
const STRIDE := 14
const SEA := Color(0.05, 0.08, 0.13)
const WASTE := Color(0.13, 0.14, 0.16)
## How far the picture may drift, as a share of its size, and how long one way takes.
const DRIFT := 0.06
const DRIFT_SECONDS := 70.0

static var _cached: ImageTexture


static func build_texture() -> ImageTexture:
	if _cached != null:
		return _cached
	var size: Vector2i = MapData.map_size / STRIDE
	var img := Image.create(size.x, size.y, false, Image.FORMAT_RGB8)
	for y in size.y:
		for x in size.x:
			var id: int = MapData.province_at_pixel(Vector2i(x, y) * STRIDE + Vector2i(STRIDE / 2, STRIDE / 2))
			var c := SEA
			if id > 0:
				var n: Dictionary = MapData.nations.get(MapData.provinces[id].owner, {})
				c = Color(n.get("color", WASTE)).darkened(0.1)
			elif id < 0:
				c = WASTE
			img.set_pixel(x, y, c)
	_cached = ImageTexture.create_from_image(img)
	return _cached


func _ready() -> void:
	texture = build_texture()
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_SCALE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Bigger than the screen, so the drift never shows an edge; the picture keeps the map's shape.
	var view := get_viewport_rect().size
	var aspect := float(MapData.map_size.x) / MapData.map_size.y
	var width := maxf(view.x * (1.0 + 2.0 * DRIFT), view.y * (1.0 + 2.0 * DRIFT) * aspect)
	size = Vector2(width, width / aspect)
	var slack := size - view
	position = -slack * 0.05
	var tween := create_tween().set_loops()
	tween.tween_property(self, "position", -slack * 0.6, DRIFT_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(self, "position", -slack * 0.05, DRIFT_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
