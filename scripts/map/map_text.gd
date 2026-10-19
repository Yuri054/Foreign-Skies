class_name MapText
extends RefCounted
## Text on the map. The layers measure in map units, which a camera zoom scales, so a size worked
## out as screen pixels times 1/zoom came out as a few pixels at a high zoom and was stretched
## back up, and the text went blurry. Here the font size stays in screen pixels and a transform
## scales the line to the map instead, so glyphs are made at the size they are shown at.


## Width and height of a text, in map units, for a font size in screen pixels.
static func size_of(font: Font, text: String, size_px: int, px: float) -> Vector2:
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px) * px


## Draws a text with its baseline starting at `pos` (map units). `width` is the room it is aligned
## in (map units, -1 for none); `size_px` is the font size on the screen; `px` is map units per
## screen pixel (1 / zoom).
static func draw(item: CanvasItem, font: Font, pos: Vector2, text: String, align: HorizontalAlignment, width: float,
		size_px: int, color: Color, px: float, outline := Color(0, 0, 0, 0)) -> void:
	item.draw_set_transform(pos, 0.0, Vector2(px, px))
	var room := -1.0 if width < 0.0 else width / px
	if outline.a > 0.0:
		item.draw_string_outline(font, Vector2.ZERO, text, align, room, size_px, maxi(2, size_px / 5), outline)
	item.draw_string(font, Vector2.ZERO, text, align, room, size_px, color)
	item.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
