class_name UiTheme
extends RefCounted
## The look shared by every menu: a slightly smaller font, tight padding and short gaps so
## more fits in a window. Built in code and put on the root window (see UiSettings), so any
## control, however it was made, picks it up.

const FONT_SIZE := 14
const ACCENT := Color(0.75, 0.82, 0.95)


static func build() -> Theme:
	var t := Theme.new()
	t.default_font_size = FONT_SIZE

	# Buttons (OptionButton, MenuButton and CheckButton share these).
	var states := {
		"normal": Color(0.18, 0.21, 0.28),
		"hover": Color(0.25, 0.29, 0.38),
		"pressed": Color(0.27, 0.4, 0.62),
		"disabled": Color(0.14, 0.16, 0.2),
		"focus": Color(0.0, 0.0, 0.0, 0.0),
	}
	for type in ["Button", "OptionButton"]:
		for state: String in states:
			var box := StyleBoxFlat.new()
			box.bg_color = states[state]
			box.set_corner_radius_all(3)
			box.content_margin_left = 8
			box.content_margin_right = 8
			box.content_margin_top = 2
			box.content_margin_bottom = 2
			if state == "focus":
				box.draw_center = false
				box.set_border_width_all(1)
				box.border_color = Color(0.5, 0.6, 0.8, 0.8)
			t.set_stylebox(state, type, box)
	var lit := t.get_stylebox("pressed", "Button").duplicate() as StyleBoxFlat
	lit.bg_color = Color(0.33, 0.47, 0.72)
	t.set_stylebox("hover_pressed", "Button", lit)

	# Tabs.
	for state in ["tab_selected", "tab_unselected", "tab_hovered", "tab_disabled"]:
		var tab := StyleBoxFlat.new()
		tab.bg_color = Color(0.22, 0.26, 0.34) if state == "tab_selected" else Color(0.13, 0.15, 0.2)
		tab.set_corner_radius_all(3)
		tab.corner_radius_bottom_left = 0
		tab.corner_radius_bottom_right = 0
		tab.content_margin_left = 9
		tab.content_margin_right = 9
		tab.content_margin_top = 3
		tab.content_margin_bottom = 3
		t.set_stylebox(state, "TabContainer", tab)
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
		row.bg_color = Color(0.26, 0.32, 0.45) if state.begins_with("selected") else Color(0, 0, 0, 0)
		row.set_corner_radius_all(2)
		row.content_margin_left = 4
		row.content_margin_right = 4
		row.content_margin_top = 1
		row.content_margin_bottom = 1
		if state.begins_with("cursor"):
			row.draw_center = false
		t.set_stylebox(state, "ItemList", row)

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
