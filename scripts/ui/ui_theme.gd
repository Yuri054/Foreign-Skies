class_name UiTheme
extends RefCounted
## The look shared by every menu: dark slate panels with gold edges and corner studs, cream serif
## text, brown buttons with a gold rim, tight padding and short gaps so more fits in a window.
## Built in code and put on the root window (see UiSettings), so any control, however it was
## made, picks it up. The frame texture is drawn here too, so the game needs no image files.

const FONT_SIZE := 14
const SLATE := Color(0.105, 0.13, 0.165)
const SLATE_DEEP := Color(0.075, 0.095, 0.125)
const GOLD := Color(0.82, 0.66, 0.34)
const GOLD_DIM := Color(0.55, 0.44, 0.25)
const CREAM := Color(0.93, 0.89, 0.77)
const CREAM_DIM := Color(0.74, 0.7, 0.6)
const INK := Color(0.13, 0.1, 0.07)
const PARCHMENT := Color(0.74, 0.66, 0.49)
## Section headings and highlighted figures.
const ACCENT := Color(0.9, 0.76, 0.46)

const FRAME_SIZE := 48
const FRAME_CORNER := 14

static var _frame_texture: ImageTexture
static var _font: SystemFont


## The serif face of the interface: the first of these the system has.
static func font() -> SystemFont:
	if _font == null:
		_font = SystemFont.new()
		_font.font_names = PackedStringArray(["Georgia", "Palatino Linotype", "Book Antiqua", "Cambria", "Times New Roman", "serif"])
		_font.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	return _font


## The nine-patch picture of a frame: a slate field, a thick gold rule inside a dark one, a thin
## gold rule inside that, and a gold stud in each corner. Drawn once, on first use.
static func frame_texture() -> ImageTexture:
	if _frame_texture != null:
		return _frame_texture
	var n := FRAME_SIZE
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var outline := Color(0.03, 0.03, 0.04)
	for y in n:
		for x in n:
			var d := mini(mini(x, y), mini(n - 1 - x, n - 1 - y))
			var shade := lerpf(1.0, 0.8, float(y) / n)
			var c := SLATE * shade
			c.a = 1.0
			if d == 0:
				c = outline
			elif d <= 2:
				c = GOLD
			elif d == 3:
				c = outline
			elif d == 5:
				c = GOLD_DIM
			img.set_pixel(x, y, c)
	# A diamond stud in each corner, with a dark pip in its middle.
	for corner: Vector2i in [Vector2i(8, 8), Vector2i(n - 9, 8), Vector2i(8, n - 9), Vector2i(n - 9, n - 9)]:
		for dy in range(-5, 6):
			for dx in range(-5, 6):
				var m := absi(dx) + absi(dy)
				var c2 := Color(0, 0, 0, 0)
				if m == 5:
					c2 = outline
				elif m >= 3:
					c2 = GOLD
				elif m == 2:
					c2 = outline
				elif m <= 1:
					c2 = GOLD
				if c2.a > 0.0:
					img.set_pixel(corner.x + dx, corner.y + dy, c2)
	_frame_texture = ImageTexture.create_from_image(img)
	return _frame_texture


## An ornate frame for windows and large panels. `padding` is the space between the frame and
## what it holds.
static func ornate(padding := 14.0) -> StyleBoxTexture:
	var box := StyleBoxTexture.new()
	box.texture = frame_texture()
	box.texture_margin_left = FRAME_CORNER
	box.texture_margin_right = FRAME_CORNER
	box.texture_margin_top = FRAME_CORNER
	box.texture_margin_bottom = FRAME_CORNER
	box.set_content_margin_all(padding)
	return box


## A dark, ornate panel for text that sits over the map.
static func map_panel() -> StyleBox:
	return ornate(14.0)


## A flat dark block with a gold rim, for the small blocks along the bottom of the screen (the
## command panel and the map mode palette).
static func frame() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(SLATE_DEEP, 0.95)
	box.border_color = GOLD_DIM
	box.set_border_width_all(1)
	box.set_corner_radius_all(2)
	box.content_margin_left = 4
	box.content_margin_right = 4
	box.content_margin_top = 2
	box.content_margin_bottom = 3
	return box


## The usual theme with smaller text, tight buttons and short gaps, for the strip at the bottom of
## the screen.
static func compact() -> Theme:
	var t := build()
	t.default_font_size = 12
	for state in ["normal", "hover", "pressed", "disabled"]:
		var box := t.get_stylebox(state, "Button").duplicate() as StyleBoxFlat
		box.content_margin_left = 5
		box.content_margin_right = 5
		box.content_margin_top = 0
		box.content_margin_bottom = 0
		t.set_stylebox(state, "Button", box)
		t.set_stylebox(state, "MenuButton", box)
	t.set_constant("separation", "HBoxContainer", 3)
	t.set_constant("separation", "VBoxContainer", 2)
	return t


## Turns the buttons of a theme into parchment-coloured ones with dark lettering, as on the map
## mode palette.
static func parchment(t: Theme) -> Theme:
	var fills := {"normal": PARCHMENT, "hover": PARCHMENT.lightened(0.14), "pressed": PARCHMENT.darkened(0.3),
			"disabled": PARCHMENT.darkened(0.45)}
	for state: String in fills:
		var box := t.get_stylebox(state, "Button").duplicate() as StyleBoxFlat
		box.bg_color = fills[state]
		box.border_color = INK if state != "pressed" else GOLD
		box.set_border_width_all(1)
		t.set_stylebox(state, "Button", box)
	t.set_stylebox("hover_pressed", "Button", t.get_stylebox("pressed", "Button"))
	t.set_color("font_color", "Button", INK)
	t.set_color("font_hover_color", "Button", INK)
	t.set_color("font_focus_color", "Button", INK)
	t.set_color("font_pressed_color", "Button", CREAM)
	t.set_color("font_hover_pressed_color", "Button", CREAM)
	t.set_color("font_disabled_color", "Button", INK.lightened(0.4))
	return t


static func build() -> Theme:
	var t := Theme.new()
	t.default_font = font()
	t.default_font_size = FONT_SIZE

	# Buttons (OptionButton, MenuButton and CheckButton share these).
	var states := {
		"normal": Color(0.17, 0.155, 0.14),
		"hover": Color(0.27, 0.22, 0.15),
		"pressed": Color(0.38, 0.29, 0.15),
		"disabled": Color(0.115, 0.115, 0.12),
		"focus": Color(0.0, 0.0, 0.0, 0.0),
	}
	for type in ["Button", "OptionButton"]:
		for state: String in states:
			var box := StyleBoxFlat.new()
			box.bg_color = states[state]
			box.set_corner_radius_all(2)
			box.set_border_width_all(1)
			box.border_color = GOLD_DIM
			if state == "hover" or state == "pressed":
				box.border_color = GOLD
			elif state == "disabled":
				box.border_color = Color(0.3, 0.28, 0.24)
			box.content_margin_left = 8
			box.content_margin_right = 8
			box.content_margin_top = 2
			box.content_margin_bottom = 2
			if state == "focus":
				box.draw_center = false
				box.border_color = Color(GOLD, 0.8)
			t.set_stylebox(state, type, box)
	var lit := t.get_stylebox("pressed", "Button").duplicate() as StyleBoxFlat
	lit.bg_color = Color(0.45, 0.35, 0.17)
	t.set_stylebox("hover_pressed", "Button", lit)

	# Cream lettering everywhere, white when pointed at, grey when switched off.
	for type in ["Button", "OptionButton", "MenuButton", "CheckBox", "CheckButton"]:
		t.set_color("font_color", type, CREAM)
		t.set_color("font_hover_color", type, Color.WHITE)
		t.set_color("font_focus_color", type, CREAM)
		t.set_color("font_pressed_color", type, Color.WHITE)
		t.set_color("font_hover_pressed_color", type, Color.WHITE)
		t.set_color("font_disabled_color", type, Color(0.5, 0.48, 0.42))
	t.set_color("font_color", "Label", CREAM)
	t.set_color("font_color", "LineEdit", CREAM)
	t.set_color("font_color", "RichTextLabel", CREAM)
	t.set_color("default_color", "RichTextLabel", CREAM)

	# Sliders: a dark groove with a gold rim, filled gold up to the knob.
	for type in ["HSlider", "VSlider"]:
		var groove := StyleBoxFlat.new()
		groove.bg_color = Color(0.04, 0.05, 0.07)
		groove.border_color = GOLD_DIM
		groove.set_border_width_all(1)
		groove.set_corner_radius_all(2)
		groove.content_margin_top = 3
		groove.content_margin_bottom = 3
		t.set_stylebox("slider", type, groove)
		var filled := StyleBoxFlat.new()
		filled.bg_color = GOLD_DIM
		filled.set_corner_radius_all(2)
		t.set_stylebox("grabber_area", type, filled)
		var lit_fill := filled.duplicate() as StyleBoxFlat
		lit_fill.bg_color = GOLD
		t.set_stylebox("grabber_area_highlight", type, lit_fill)

	# Tabs.
	for state in ["tab_selected", "tab_unselected", "tab_hovered", "tab_disabled"]:
		var tab := StyleBoxFlat.new()
		tab.bg_color = Color(0.2, 0.17, 0.12) if state == "tab_selected" else Color(0.1, 0.11, 0.13)
		if state == "tab_hovered":
			tab.bg_color = Color(0.16, 0.14, 0.11)
		tab.set_corner_radius_all(2)
		tab.corner_radius_bottom_left = 0
		tab.corner_radius_bottom_right = 0
		tab.set_border_width_all(1)
		tab.border_width_bottom = 0
		tab.border_color = GOLD if state == "tab_selected" else GOLD_DIM
		tab.content_margin_left = 9
		tab.content_margin_right = 9
		tab.content_margin_top = 3
		tab.content_margin_bottom = 3
		t.set_stylebox(state, "TabContainer", tab)
	t.set_color("font_selected_color", "TabContainer", ACCENT)
	t.set_color("font_unselected_color", "TabContainer", CREAM_DIM)
	t.set_color("font_hovered_color", "TabContainer", Color.WHITE)
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0, 0, 0, 0)
	panel.content_margin_left = 0
	panel.content_margin_right = 0
	panel.content_margin_top = 4
	panel.content_margin_bottom = 0
	t.set_stylebox("panel", "TabContainer", panel)

	# List rows: small padding, a clear highlight.
	for state in ["selected", "selected_focus", "cursor", "cursor_unfocused"]:
		var row := StyleBoxFlat.new()
		row.bg_color = Color(0.36, 0.28, 0.14) if state.begins_with("selected") else Color(0, 0, 0, 0)
		row.set_corner_radius_all(2)
		row.content_margin_left = 4
		row.content_margin_right = 4
		row.content_margin_top = 1
		row.content_margin_bottom = 1
		if state.begins_with("cursor"):
			row.draw_center = false
		t.set_stylebox(state, "ItemList", row)
	t.set_color("font_color", "ItemList", CREAM)
	t.set_color("font_selected_color", "ItemList", Color.WHITE)

	# Lists and gaps.
	t.set_constant("v_separation", "ItemList", 1)
	t.set_constant("line_separation", "ItemList", 0)
	t.set_constant("separation", "VBoxContainer", 3)
	t.set_constant("separation", "HBoxContainer", 5)
	t.set_constant("v_separation", "GridContainer", 2)
	t.set_constant("h_separation", "GridContainer", 10)
	t.set_constant("separation", "HSeparator", 4)
	t.set_constant("line_spacing", "Label", 0)
	return t
