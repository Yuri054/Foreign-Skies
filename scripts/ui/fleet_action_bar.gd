extends PanelContainer
## The orders for the selected fleets, in a bar at the bottom of the screen like the army bar:
## standing orders, merge, detach one type, sail to the nearest port, show on the map, deselect.
## It appears when the player has fleets selected and goes when they are deselected. The Navy
## window holds the selection; everything goes through the same commands it uses.

const GAP := 8.0
const RIGHT_MARGIN := 12.0
const BOTTOM := 34.0
## Space left for the army bar when both are showing (it sits below this one).
const ARMY_BAR_ROOM := 6.0

var _ids: Array[int] = []
var _title := Label.new()
var _orders := MenuButton.new()
var _merge := Button.new()
var _detach := MenuButton.new()
var _home := Button.new()
var _show := Button.new()
var _deselect := Button.new()
var _mission_keys: Array[String] = []
var _detach_types: Array[String] = []


func _ready() -> void:
	add_to_group("fleet_action_bar")
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	anchor_left = 0.0
	anchor_right = 0.0
	anchor_top = 1.0
	anchor_bottom = 1.0
	grow_horizontal = Control.GROW_DIRECTION_END
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	offset_top = -BOTTOM
	offset_bottom = -BOTTOM
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.1, 0.14, 0.95)
	style.border_color = Color(0.4, 0.46, 0.58)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 5
	style.content_margin_bottom = 6
	add_theme_stylebox_override("panel", style)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.modulate = Fmt.DIM
	box.add_child(_title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(row)
	add_child(box)

	_orders.text = "Orders"
	_orders.tooltip_text = "Standing orders: stationed, on patrol, blockading, escorting or raiding."
	_orders.get_popup().about_to_popup.connect(_fill_orders)
	_orders.get_popup().id_pressed.connect(_on_orders)
	_merge.text = "Merge"
	_merge.tooltip_text = "Combine the selected fleets that lie together."
	_merge.pressed.connect(_on_merge)
	_detach.text = "Detach"
	_detach.tooltip_text = "Detach one squadron of a type into a new fleet."
	_detach.get_popup().about_to_popup.connect(_fill_detach)
	_detach.get_popup().id_pressed.connect(_on_detach)
	_home.text = "To port"
	_home.tooltip_text = "Send the selected fleets to the nearest port you may use."
	_home.pressed.connect(_on_home)
	_show.text = "Show"
	_show.tooltip_text = "Centre the map on the selection."
	_show.pressed.connect(_on_show)
	_deselect.text = "Deselect"
	_deselect.tooltip_text = "Clear the selection (Esc, or click empty water)."
	_deselect.pressed.connect(func() -> void: get_tree().call_group("navy_panel", "clear_selection"))
	for c: Control in [_orders, _merge, _detach, _home, _show, _deselect]:
		c.focus_mode = Control.FOCUS_NONE
		row.add_child(c)

	GameState.fleets_changed.connect(_refresh)
	GameState.armies_changed.connect(_place)
	get_viewport().size_changed.connect(_place)
	resized.connect(_place)


## The Navy window changed the selection.
func set_selection(ids: Array[int]) -> void:
	_ids = ids
	_refresh()


func _fleets() -> Array[Fleet]:
	var out: Array[Fleet] = []
	for id in _ids:
		var f: Fleet = GameState.fleets.get(id)
		if f != null and f.tag == GameState.player_tag:
			out.append(f)
	return out


func _where(f: Fleet) -> String:
	if f.is_in_port():
		return MapData.provinces[f.port].name
	if f.zone > 0:
		return MapData.sea_zones[f.zone].name
	return ""


func _refresh() -> void:
	var fleets := _fleets()
	visible = not fleets.is_empty()
	if not visible:
		return
	var ships := 0
	var morale := 0.0
	var weight := 0.0
	var places := {}
	for f in fleets:
		ships += f.ships.size()
		morale += f.morale() * f.ships.size()
		weight += f.ships.size()
		places[_where(f)] = true
	if fleets.size() == 1:
		_title.text = "%s · %d ships · morale %d%% · %s" % [fleets[0].display_name, ships, roundi(fleets[0].morale() * 100.0), _where(fleets[0])]
	else:
		_title.text = "%d fleets · %d ships · morale %d%%" % [fleets.size(), ships, roundi(morale / maxf(weight, 1.0) * 100.0)]
	var one_place := places.size() == 1
	_merge.disabled = not (fleets.size() >= 2 and one_place)
	_detach.disabled = not (fleets.size() == 1 and fleets[0].ships.size() >= 2 and not fleets[0].fighting)
	_home.disabled = fleets.all(func(f: Fleet) -> bool: return f.is_in_port() and not f.is_moving())
	_place.call_deferred()


## The army bar changed size or visibility.
func place_deferred() -> void:
	_place.call_deferred()


## Bottom centre of the screen, clear of the map mode palette, and above the army bar when
## that one is showing too.
func _place() -> void:
	if not visible or not is_inside_tree():
		return
	var view := get_viewport_rect().size
	var wide := get_combined_minimum_size().x
	var left := 0.0
	var palette := get_tree().get_first_node_in_group("map_modes") as Control
	if palette != null:
		left = palette.get_global_rect().end.x + GAP
	var x := clampf((view.x - wide) * 0.5, left, maxf(left, view.x - wide - RIGHT_MARGIN))
	offset_left = x
	offset_right = x + wide
	var lift := 0.0
	var army_bar := get_tree().get_first_node_in_group("army_action_bar") as Control
	if army_bar != null and army_bar.visible:
		lift = army_bar.size.y + ARMY_BAR_ROOM
	offset_top = -BOTTOM - lift
	offset_bottom = -BOTTOM - lift


# ------------------------------------------------------------------ orders

func _fill_orders() -> void:
	var popup := _orders.get_popup()
	popup.clear()
	_mission_keys.clear()
	for key: String in Navy.cfg.missions:
		_mission_keys.append(key)
		popup.add_item(Navy.cfg.missions[key], _mission_keys.size() - 1)


func _on_orders(index: int) -> void:
	if index < 0 or index >= _mission_keys.size():
		return
	for f in _fleets():
		GameState.issue(SetFleetMission.new(GameState.player_tag, f.id, _mission_keys[index]))


func _on_merge() -> void:
	var ids: Array[int] = []
	for f in _fleets():
		ids.append(f.id)
	if GameState.issue(MergeFleets.new(GameState.player_tag, ids)):
		get_tree().call_group("navy_panel", "select_ids", [ids[0]] as Array[int])


func _fill_detach() -> void:
	var popup := _detach.get_popup()
	popup.clear()
	_detach_types.clear()
	var fleets := _fleets()
	if fleets.size() != 1:
		return
	var comp := fleets[0].composition()
	for type: String in comp:
		_detach_types.append(type)
		popup.add_item("%s (%d)" % [Navy.cfg.types[type].name, comp[type]], _detach_types.size() - 1)


func _on_detach(index: int) -> void:
	var fleets := _fleets()
	if fleets.size() != 1 or index < 0 or index >= _detach_types.size():
		return
	var cmd := SplitFleet.new(GameState.player_tag, fleets[0].id, SplitFleet.indices_of_type(fleets[0], _detach_types[index], 1))
	if GameState.issue(cmd):
		get_tree().call_group("navy_panel", "select_ids", [cmd.new_fleet_id] as Array[int])


func _on_home() -> void:
	for f in _fleets():
		var p := Navy.nearest_port(GameState, f)
		if p > 0 and p != f.port:
			GameState.issue(MoveFleet.new(GameState.player_tag, f.id, 0, p))


func _on_show() -> void:
	var fleets := _fleets()
	if not fleets.is_empty():
		get_tree().call_group("camera_focus", "focus_on", FleetLayer.position_of(fleets[0]))
