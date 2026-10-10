extends Control
## Full-screen overlay for choosing which nation to play.

signal nation_chosen(tag: String)

var _list := ItemList.new()
var _tags: Array[String] = []


func _ready() -> void:
	add_to_group("nation_picker")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(460, 0)
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	var title := Label.new()
	title.text = GameState.scenario.name
	title.add_theme_font_size_override("font_size", 24)
	box.add_child(title)

	var blurb := Label.new()
	blurb.text = GameState.scenario.get("description", "")
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(blurb)

	_list.custom_minimum_size = Vector2(0, 280)
	_list.item_activated.connect(func(_i: int) -> void: _start())
	box.add_child(_list)

	var start := Button.new()
	start.text = "Play"
	start.pressed.connect(_start)
	box.add_child(start)

	var sorted: Array = GameState.nations.values()
	sorted.sort_custom(func(a: Nation, b: Nation) -> bool: return a.population > b.population)
	for n: Nation in sorted:
		_tags.append(n.tag)
		var i := _list.add_item("%s  (%.1fM people, %d provinces)" % [n.display_name, n.population / 1_000_000.0, n.provinces.size()])
		_list.set_item_custom_fg_color(i, n.color.lightened(0.3))
		if n.tag == GameState.player_tag:
			_list.select(i)


func _start() -> void:
	var sel := _list.get_selected_items()
	if sel.is_empty():
		return
	nation_chosen.emit(_tags[sel[0]])
