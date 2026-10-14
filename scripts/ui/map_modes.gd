extends VBoxContainer
## The map mode palette, in the style of the Paradox games: a row of buttons for the kinds of
## map (Political, Diplomacy, Economy, Population, Military, Terrain) in the bottom left corner.
## Above it, a strip for the kind you are looking at lists its variants as chips (Economy:
## tax income, coal, iron ore, timber, buildings), and a colour legend shows what the shading
## means. Keys 1 to 6 pick a kind; pressing the key again steps through its variants. Each kind
## remembers the variant you last used. Opening a window can change the mode too (the
## Diplomacy window switches to the Diplomacy map), so the palette follows the map view.

const MapView := preload("res://scripts/map/map_view.gd")

## A map mode with its variants, as the palette shows it. `items` are {label, mode, sub, tip}.
## The key is the number that picks the group.
var _groups: Array[Dictionary] = []
var map_view: Sprite2D

var _buttons: Array[Button] = []
var _chips: Dictionary = {}
var _last: Dictionary = {}
var _active := 0
var _panel_style := StyleBoxFlat.new()

var _legend_panel := PanelContainer.new()
var _legend_title := Label.new()
var _legend_low := Label.new()
var _legend_high := Label.new()
var _legend_bar := TextureRect.new()
var _legend_bar_box := CenterContainer.new()
var _legend_swatches := HBoxContainer.new()
var _gradient := Gradient.new()

var _strip_panel := PanelContainer.new()
var _strip_title := Label.new()
var _strip := HBoxContainer.new()
var _sub_picker := OptionButton.new()
var _view_label := Label.new()
var _view_back := Button.new()


func _ready() -> void:
	add_to_group("map_modes")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_groups()
	# Bottom left corner; grows upward.
	anchor_left = 0.0
	anchor_right = 0.0
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = 10.0
	offset_right = 10.0
	offset_top = -8.0
	offset_bottom = -8.0
	grow_horizontal = Control.GROW_DIRECTION_END
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_theme_constant_override("separation", 4)

	_panel_style.bg_color = Color(0.08, 0.1, 0.14, 0.93)
	_panel_style.border_color = Color(0.25, 0.29, 0.36)
	_panel_style.set_border_width_all(1)
	_panel_style.set_corner_radius_all(4)
	_panel_style.content_margin_left = 8
	_panel_style.content_margin_right = 8
	_panel_style.content_margin_top = 4
	_panel_style.content_margin_bottom = 4

	_build_legend()
	_build_strip()
	_build_palette()

	map_view.mode_changed.connect(func(_m: int, _s: String) -> void: _sync())
	map_view.viewpoint_changed.connect(func(_t: String) -> void: _sync_view())
	GameState.economy_updated.connect(_sync_legend)
	GameState.player_changed.connect(func(_t: String) -> void: _sync_legend())
	_sync()


func _build_groups() -> void:
	var economy: Array = [{"label": "Tax income", "mode": MapView.Mode.INCOME, "sub": "", "tip": "Tax each province yields every month."}]
	for r in Economy.resource_ids():
		economy.append({"label": Economy.cfg.resources[r].name, "mode": MapView.Mode.RESOURCES, "sub": r,
				"tip": "Where %s lies, and how much a province could yield a month." % Economy.cfg.resources[r].name.to_lower()})
	economy.append({"label": "Buildings", "mode": MapView.Mode.BUILDINGS, "sub": MapView.ALL_BUILDINGS,
			"tip": "Building levels by province. Pick one kind in the list that appears."})
	_groups = [
		{"label": "Political", "tip": "Who owns what. Occupied provinces are striped with the occupier's colour.",
				"items": [{"label": "Political", "mode": MapView.Mode.POLITICAL, "sub": "", "tip": ""}]},
		{"label": "Diplomacy", "tip": "How each nation feels about yours: red hostile, green friendly, teal allied, dark red at war. Outlines mark the blocs, hatching a nation that is guaranteed.",
				"items": [{"label": "Diplomacy", "mode": MapView.Mode.DIPLOMACY, "sub": "", "tip": ""}]},
		{"label": "Economy", "tip": "Tax income, coal, iron and timber deposits, and buildings.", "items": economy},
		{"label": "Population", "tip": "People living in each province.",
				"items": [{"label": "Population", "mode": MapView.Mode.POPULATION, "sub": "", "tip": ""}]},
		{"label": "Military", "tip": "Who holds the ground, where the fronts are, how many men stand where and how well they are equipped, and who holds the sea.",
				"items": [
					{"label": "Control", "mode": MapView.Mode.MILITARY, "sub": MapView.MIL_CONTROL, "tip": "Who holds each province: occupied provinces are painted solid in the occupier's colour."},
					{"label": "Front line", "mode": MapView.Mode.MILITARY, "sub": MapView.MIL_FRONT, "tip": "Provinces held next to an enemy at war are lit red; the rear is dimmed."},
					{"label": "Strength", "mode": MapView.Mode.MILITARY, "sub": MapView.MIL_STRENGTH, "tip": "Men stationed in each province, of every nation."},
					{"label": "Equipment", "mode": MapView.Mode.MILITARY, "sub": MapView.MIL_EQUIPMENT, "tip": "How much of the equipment they need the armies in each province hold: red none, green all."},
					{"label": "Sea control", "mode": MapView.Mode.SEA_CONTROL, "sub": "", "tip": "Sea zones tinted by the nation whose warships hold them; dark red where enemy fleets contest them."},
					{"label": "Blockade", "mode": MapView.Mode.BLOCKADE, "sub": "", "tip": "Nations shaded by how much of their trade is cut off; their ports hatched; sea zones tinted by who holds them."},
				]},
		{"label": "Terrain", "tip": "Plains, forest, hills, mountains, marsh and urban ground: they set movement, defence and sieges.",
				"items": [
					{"label": "Terrain", "mode": MapView.Mode.TERRAIN, "sub": "", "tip": ""},
					{"label": "Provinces", "mode": MapView.Mode.PROVINCES, "sub": "", "tip": "The raw province colours, for checking the map."},
				]},
	]


func _boxed(content: Control, panel: PanelContainer) -> void:
	panel.add_theme_stylebox_override("panel", _panel_style)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_child(content)
	add_child(panel)


func _build_legend() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_legend_title.modulate = Fmt.DIM
	row.add_child(_legend_title)
	row.add_child(_legend_low)
	_gradient.colors = PackedColorArray([Color.WHITE, Color.BLACK])
	var tex := GradientTexture1D.new()
	tex.gradient = _gradient
	tex.width = 120
	_legend_bar.texture = tex
	_legend_bar.custom_minimum_size = Vector2(120, 12)
	_legend_bar.stretch_mode = TextureRect.STRETCH_SCALE
	_legend_bar_box.add_child(_legend_bar)
	row.add_child(_legend_bar_box)
	row.add_child(_legend_high)
	_legend_swatches.add_theme_constant_override("separation", 12)
	row.add_child(_legend_swatches)
	_boxed(row, _legend_panel)


func _build_strip() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_strip_title.add_theme_color_override("font_color", UiTheme.ACCENT)
	row.add_child(_strip_title)
	_strip.add_theme_constant_override("separation", 3)
	row.add_child(_strip)
	_sub_picker.focus_mode = Control.FOCUS_NONE
	_sub_picker.tooltip_text = "Which kind of building to show."
	_sub_picker.item_selected.connect(func(i: int) -> void:
		map_view.set_mode(map_view.mode, _sub_picker.get_item_metadata(i))
	)
	row.add_child(_sub_picker)
	# Diplomacy seen from another nation: who, and a way back.
	_view_label.add_theme_color_override("font_color", Fmt.WARN)
	row.add_child(_view_label)
	_view_back.focus_mode = Control.FOCUS_NONE
	_view_back.pressed.connect(func() -> void: map_view.set_viewpoint(""))
	row.add_child(_view_back)
	_boxed(row, _strip_panel)


func _build_palette() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	var group := ButtonGroup.new()
	for i in _groups.size():
		var b := Button.new()
		b.text = _groups[i].label
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(80, 28)
		b.tooltip_text = "%s (%d)\n%s" % [_groups[i].label, i + 1, _groups[i].tip]
		b.pressed.connect(func() -> void: pick_group(i))
		row.add_child(b)
		_buttons.append(b)
	var panel := PanelContainer.new()
	_boxed(row, panel)


## Picks a kind of map: the variant used last in it, or its first.
func pick_group(index: int) -> void:
	index = clampi(index, 0, _groups.size() - 1)
	pick_item(index, _last.get(index, 0))


## Shows one variant of a kind.
func pick_item(group: int, item: int) -> void:
	var items: Array = _groups[group].items
	item = clampi(item, 0, items.size() - 1)
	_last[group] = item
	var it: Dictionary = items[item]
	map_view.set_mode(it.mode, it.sub)


## The next variant of the kind being looked at, wrapping round.
func cycle_item() -> void:
	var items: Array = _groups[_active].items
	pick_item(_active, (_last.get(_active, 0) + 1) % items.size())


## Which kind and variant the map view is showing, as indexes (-1 if none).
func _locate() -> Vector2i:
	for g in _groups.size():
		for i in _groups[g].items.size():
			var it: Dictionary = _groups[g].items[i]
			if it.mode != map_view.mode:
				continue
			if it.mode in [MapView.Mode.RESOURCES, MapView.Mode.MILITARY] and it.sub != map_view.submode:
				continue
			return Vector2i(g, i)
	return Vector2i(-1, -1)


## Brings the palette in line with the map view.
func _sync() -> void:
	var at := _locate()
	if at.x < 0:
		_strip_title.text = "%s ›" % map_view.MODE_NAMES.get(map_view.mode, "")
		for c in _strip.get_children():
			_strip.remove_child(c)
			c.queue_free()
		_sync_legend()  # a map with no button (Construction) still has its legend
		return
	_active = at.x
	_last[at.x] = at.y
	_buttons[at.x].set_pressed_no_signal(true)
	var group: Dictionary = _groups[at.x]
	_strip_title.text = "%s ›" % group.label
	for c in _strip.get_children():
		_strip.remove_child(c)
		c.queue_free()
	_chips.clear()
	var items: Array = group.items
	_strip.visible = items.size() > 1
	if items.size() > 1:
		for i in items.size():
			var chip := Button.new()
			chip.text = items[i].label
			chip.toggle_mode = true
			chip.focus_mode = Control.FOCUS_NONE
			chip.tooltip_text = items[i].tip
			chip.set_pressed_no_signal(i == at.y)
			chip.pressed.connect(func() -> void: pick_item(at.x, i))
			_strip.add_child(chip)
			_chips[i] = chip
	# The kinds of building, when buildings are on show.
	var options: Array = map_view.submodes() if map_view.mode == MapView.Mode.BUILDINGS else []
	_sub_picker.visible = not options.is_empty()
	_sub_picker.clear()
	for i in options.size():
		_sub_picker.add_item(options[i][1])
		_sub_picker.set_item_metadata(i, options[i][0])
		if options[i][0] == map_view.submode:
			_sub_picker.select(i)
	_sync_view()


## Shows whose point of view the Diplomacy map has, when it is not the player's.
func _sync_view() -> void:
	var other: String = map_view.diplomacy_viewpoint()
	var shown: bool = map_view.mode == MapView.Mode.DIPLOMACY and other != GameState.player_tag
	_view_label.visible = shown
	_view_back.visible = shown
	if shown:
		_view_label.text = "· seen from %s" % GameState.nations[other].display_name
		_view_back.text = "Back to %s" % GameState.nations[GameState.player_tag].display_name
	_sync_legend()


func _sync_legend() -> void:
	var legend: Dictionary = map_view.legend()
	_legend_panel.visible = not legend.is_empty()
	if not legend.is_empty():
		_legend_title.text = legend.title
		var swatches: Array = legend.get("swatches", [])
		_legend_low.visible = swatches.is_empty()
		_legend_high.visible = swatches.is_empty()
		_legend_bar_box.visible = swatches.is_empty()
		_legend_swatches.visible = not swatches.is_empty()
		for c in _legend_swatches.get_children():
			_legend_swatches.remove_child(c)
			c.queue_free()
		for sw: Array in swatches:
			var chip := HBoxContainer.new()
			chip.add_theme_constant_override("separation", 4)
			var box := ColorRect.new()
			box.color = sw[0]
			box.custom_minimum_size = Vector2(14, 14)
			var holder := CenterContainer.new()
			holder.add_child(box)
			chip.add_child(holder)
			var label := Label.new()
			label.text = sw[1]
			chip.add_child(label)
			_legend_swatches.add_child(chip)
		if swatches.is_empty():
			_legend_low.text = legend.low
			_legend_high.text = legend.high
			_gradient.colors = PackedColorArray([legend.from, legend.to])


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.ctrl_pressed or event.alt_pressed or event.meta_pressed:
		return
	var index: int = event.keycode - KEY_1
	if index < 0 or index >= _groups.size():
		return
	# Pressing the key of the kind in view steps through its variants.
	if index == _active and _groups[index].items.size() > 1:
		cycle_item()
	else:
		pick_group(index)
