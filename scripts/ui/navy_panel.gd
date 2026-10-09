extends VBoxContainer
## Navy overview of the player's nation: the fleets with orders (mission, merge, split, back to
## port), the shipyard of the selected province (build squadrons), and the state of the sea:
## upkeep, strength against enemies, who holds which zone and who is blockaded. Clicking a fleet
## banner selects its fleets (dragging a box selects every fleet inside it); a right click on
## water sends the selected fleets there, and a right click on a port brings them in.
## It is a tab of the Military window; N opens it.

const TABS := ["Fleets", "Shipyard", "Sea"]

var _tabs := TabContainer.new()
var _fleet_scroll := ScrollContainer.new()
var _fleet_box := VBoxContainer.new()
var _list := ItemList.new()
var _detail := Label.new()
var _mission := OptionButton.new()
var _merge := Button.new()
var _split_type := OptionButton.new()
var _split_count := SpinBox.new()
var _split := Button.new()
var _home := Button.new()
var _show := Button.new()
var _deselect := Button.new()

var _yard_scroll := ScrollContainer.new()
var _yard_box := VBoxContainer.new()
var _yard_title := Label.new()
var _yard_info := Label.new()
var _type_picker := OptionButton.new()
var _count := SpinBox.new()
var _build := Button.new()
var _build_label := Label.new()
var _yard_list := ItemList.new()
var _yards: Array[int] = []
var _queue_label := Label.new()

var _sea_scroll := ScrollContainer.new()
var _sea_box := VBoxContainer.new()
var _sea_summary := Label.new()
var _sea_list := ItemList.new()
var _sea_zones_listed: Array[int] = []

## Ids of the selected fleets; the list mirrors it.
var _selected: Array[int] = []
var _listed: Array[int] = []
var _province := 0
var _updating := false
var _split_sig := "?"


func _ready() -> void:
	add_to_group("navy_panel")
	name = "Navy"
	_build_fleets_tab()
	_build_yard_tab()
	_build_sea_tab()
	_fleet_scroll.name = TABS[0]
	_yard_scroll.name = TABS[1]
	_sea_scroll.name = TABS[2]
	for sc: ScrollContainer in [_fleet_scroll, _yard_scroll, _sea_scroll]:
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		sc.custom_minimum_size = Vector2(340, 100)
		_tabs.add_child(sc)
	_tabs.focus_mode = Control.FOCUS_NONE
	_tabs.tab_changed.connect(func(_i: int) -> void:
		_refresh()
		_fit_height.call_deferred())
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_tabs)
	GameState.fleets_changed.connect(_refresh)
	GameState.economy_updated.connect(_refresh)
	GameState.player_changed.connect(func(_t: String) -> void:
		_selected.clear()
		_sync_selection()
		_refresh())
	Clock.day_ticked.connect(_refresh)
	_refresh()


# ------------------------------------------------------------------ building the tabs

func _row(label: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(90, 0)
	row.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	return row


func _build_fleets_tab() -> void:
	_fleet_box.add_theme_constant_override("separation", 4)
	_fleet_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fleet_scroll.add_child(_fleet_box)
	_list.select_mode = ItemList.SELECT_MULTI
	_list.custom_minimum_size = Vector2(0, 120)
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.multi_selected.connect(func(_i: int, _s: bool) -> void: _read_selection())
	_list.item_selected.connect(func(_i: int) -> void: _read_selection())
	_fleet_box.add_child(_list)
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.custom_minimum_size = Vector2(300, 0)
	_fleet_box.add_child(_detail)

	for key in Navy.cfg.missions:
		_mission.add_item(Navy.cfg.missions[key])
		_mission.set_item_metadata(_mission.item_count - 1, key)
	_mission.tooltip_text = "Standing orders: stationed, on patrol, blockading, escorting or raiding. They guide the AI's fleets and mark yours on the map."
	_mission.item_selected.connect(_on_mission)
	_fleet_box.add_child(_row("Orders", _mission))

	var buttons := HBoxContainer.new()
	_merge.text = "Merge"
	_merge.tooltip_text = "Combine the selected fleets that lie together."
	_merge.pressed.connect(_on_merge)
	_home.text = "To port"
	_home.tooltip_text = "Send the selected fleets to the nearest port you may use."
	_home.pressed.connect(_on_home)
	_show.text = "Show"
	_show.tooltip_text = "Centre the map on the selected fleet."
	_show.pressed.connect(_on_show)
	_deselect.text = "Deselect"
	_deselect.pressed.connect(clear_selection)
	for b: Button in [_merge, _home, _show, _deselect]:
		b.focus_mode = Control.FOCUS_NONE
		buttons.add_child(b)
	_fleet_box.add_child(buttons)

	var split_row := HBoxContainer.new()
	_split_type.focus_mode = Control.FOCUS_NONE
	_split_count.min_value = 1
	_split_count.max_value = 1
	_split_count.value = 1
	_split.text = "Split off"
	_split.tooltip_text = "Detach that many squadrons of the type into a new fleet."
	_split.focus_mode = Control.FOCUS_NONE
	_split.pressed.connect(_on_split)
	split_row.add_child(_split_type)
	split_row.add_child(_split_count)
	split_row.add_child(_split)
	_fleet_box.add_child(split_row)


func _build_yard_tab() -> void:
	_yard_box.add_theme_constant_override("separation", 4)
	_yard_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_yard_scroll.add_child(_yard_box)
	_yard_title.add_theme_font_size_override("font_size", 15)
	_yard_box.add_child(_yard_title)
	_yard_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_yard_info.custom_minimum_size = Vector2(300, 0)
	_yard_box.add_child(_yard_info)
	for type in Navy.type_ids():
		var def: Dictionary = Navy.cfg.types[type]
		_type_picker.add_item(def.name)
		_type_picker.set_item_metadata(_type_picker.item_count - 1, type)
	_type_picker.focus_mode = Control.FOCUS_NONE
	_type_picker.item_selected.connect(func(_i: int) -> void: _refresh_yard())
	_yard_box.add_child(_row("Build", _type_picker))
	_count.min_value = 1
	_count.max_value = 8
	_count.value = 1
	_count.value_changed.connect(func(_v: float) -> void: _refresh_yard())
	_yard_box.add_child(_row("Squadrons", _count))
	_build.text = "Build"
	_build.focus_mode = Control.FOCUS_NONE
	_build.pressed.connect(_on_build)
	_yard_box.add_child(_build)
	_build_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_build_label.custom_minimum_size = Vector2(300, 0)
	_yard_box.add_child(_build_label)
	_queue_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_queue_label.custom_minimum_size = Vector2(300, 0)
	_yard_box.add_child(_queue_label)
	var yards_title := Label.new()
	yards_title.text = "Your ports"
	yards_title.modulate = Fmt.DIM
	_yard_box.add_child(yards_title)
	_yard_list.custom_minimum_size = Vector2(0, 110)
	_yard_list.item_selected.connect(func(i: int) -> void:
		if i >= 0 and i < _yards.size():
			get_tree().call_group("map_view", "select", _yards[i])
			get_tree().call_group("camera_focus", "focus_on", MapData.provinces[_yards[i]].center))
	_yard_box.add_child(_yard_list)


func _build_sea_tab() -> void:
	_sea_box.add_theme_constant_override("separation", 4)
	_sea_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sea_scroll.add_child(_sea_box)
	_sea_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sea_summary.custom_minimum_size = Vector2(300, 0)
	_sea_box.add_child(_sea_summary)
	var title := Label.new()
	title.text = "Who holds the sea"
	title.modulate = Fmt.DIM
	_sea_box.add_child(title)
	_sea_list.custom_minimum_size = Vector2(0, 150)
	_sea_list.item_selected.connect(func(i: int) -> void:
		if i >= 0 and i < _sea_zones_listed.size():
			get_tree().call_group("map_view", "select_zone", _sea_zones_listed[i])
			get_tree().call_group("camera_focus", "focus_on", MapData.sea_zones[_sea_zones_listed[i]].center))
	_sea_box.add_child(_sea_list)


# ------------------------------------------------------------------ selection and orders

## Opens the Military window on this tab, or closes it if it is already showing it.
func toggle() -> void:
	var shown := is_visible_in_tree()
	get_tree().call_group("military_panel", "show_tab", name, not shown)
	if not shown:
		_refresh()


## The map's selected province changed: the shipyard tab follows it.
func set_province(id: int) -> void:
	_province = id
	if is_visible_in_tree():
		_refresh_yard()


func has_selection() -> bool:
	return not _selected.is_empty()


func clear_selection() -> void:
	_selected.clear()
	_sync_selection()
	_refresh()


## Another kind of selection (armies) took over.
func clear_selection_quiet() -> void:
	if _selected.is_empty():
		return
	_selected.clear()
	get_tree().call_group("fleet_layer", "set_selection", _selected.duplicate())
	if is_visible_in_tree():
		_refresh()


## A fleet banner was clicked: select the player's fleets in it. Shift adds them (or removes them
## if they are all selected already).
func select_fleets(ids: Array[int], additive := false) -> void:
	var mine: Array[int] = []
	for id in ids:
		var f: Fleet = GameState.fleets.get(id)
		if f != null and f.tag == GameState.player_tag:
			mine.append(id)
	if mine.is_empty():
		return
	get_tree().call_group("military_panel", "clear_selection")
	if additive:
		if mine.all(func(x: int) -> bool: return _selected.has(x)):
			for id in mine:
				_selected.erase(id)
		else:
			for id in mine:
				if not _selected.has(id):
					_selected.append(id)
	elif _selected.size() == mine.size() and mine.all(func(x: int) -> bool: return _selected.has(x)):
		_selected.clear()
	else:
		_selected = mine
	_sync_selection()
	_refresh()


## A box was dragged on the map: select the player's fleets inside it (if there are any; a box
## with none leaves the selection to the army panel).
func select_in_rect(rect: Rect2, additive := false) -> void:
	var ids := FleetLayer.fleets_in_rect(rect, GameState.player_tag)
	if ids.is_empty():
		if not additive:
			clear_selection_quiet()
		return
	get_tree().call_group("military_panel", "clear_selection")
	var all: Array[int] = []
	if additive:
		all.append_array(_selected)
	for id in ids:
		if not all.has(id):
			all.append(id)
	_selected = all
	_sync_selection()
	_refresh()


## Right click on water: send the selected fleets to the zone.
func order_zone(zone: int) -> void:
	if _selected.is_empty():
		return
	var failed := 0
	for id in _selected.duplicate():
		if not GameState.issue(MoveFleet.new(GameState.player_tag, id, zone)):
			failed += 1
	if failed > 0:
		get_tree().call_group("event_feed", "say", "%d of %d fleets cannot reach the %s." % [failed, _selected.size(), MapData.sea_zones[zone].name], Fmt.WARN)
	_refresh()


## Right click on a province with fleets selected: bring them into its port. Returns whether the
## click was used (it is not if no selected fleet could use that port).
func order_port(province: int) -> bool:
	if _selected.is_empty():
		return false
	if MapData.zones_of_port(province).is_empty():
		return false
	var done := 0
	for id in _selected.duplicate():
		if GameState.issue(MoveFleet.new(GameState.player_tag, id, 0, province)):
			done += 1
	if done == 0:
		get_tree().call_group("event_feed", "say", "The fleet cannot enter %s." % MapData.provinces[province].name, Fmt.WARN)
	_refresh()
	return true


func _read_selection() -> void:
	if _updating:
		return
	_selected.clear()
	for i in _list.get_selected_items():
		_selected.append(_listed[i])
	if not _selected.is_empty():
		get_tree().call_group("military_panel", "clear_selection")
	_sync_selection()
	_refresh_detail()


func _sync_selection() -> void:
	get_tree().call_group("fleet_layer", "set_selection", _selected.duplicate())
	_updating = true
	for i in _listed.size():
		if _selected.has(_listed[i]):
			_list.select(i, false)
		else:
			_list.deselect(i)
	_updating = false


func _selected_fleets() -> Array[Fleet]:
	var out: Array[Fleet] = []
	for id in _selected:
		if GameState.fleets.has(id):
			out.append(GameState.fleets[id])
	return out


func _on_mission(index: int) -> void:
	if _updating:
		return
	for f in _selected_fleets():
		GameState.issue(SetFleetMission.new(GameState.player_tag, f.id, _mission.get_item_metadata(index)))
	_refresh()


func _on_merge() -> void:
	var ids: Array[int] = _selected.duplicate()
	if GameState.issue(MergeFleets.new(GameState.player_tag, ids)):
		_selected = [ids[0]]
		_sync_selection()
		_refresh()


func _on_split() -> void:
	var fleets := _selected_fleets()
	if fleets.size() != 1:
		return
	var type: String = _split_type.get_item_metadata(_split_type.selected)
	var picked := SplitFleet.indices_of_type(fleets[0], type, int(_split_count.value))
	var cmd := SplitFleet.new(GameState.player_tag, fleets[0].id, picked)
	if GameState.issue(cmd):
		_selected = [cmd.new_fleet_id]
		_sync_selection()
		_refresh()


func _on_home() -> void:
	for f in _selected_fleets():
		var p := Navy.nearest_port(GameState, f)
		if p > 0 and p != f.port:
			GameState.issue(MoveFleet.new(GameState.player_tag, f.id, 0, p))
	_refresh()


func _on_show() -> void:
	var fleets := _selected_fleets()
	if not fleets.is_empty():
		get_tree().call_group("camera_focus", "focus_on", FleetLayer.position_of(fleets[0]))


# ------------------------------------------------------------------ refreshing

func _refresh() -> void:
	if not is_visible_in_tree() or GameState.get_player() == null:
		return
	match _tabs.current_tab:
		0:
			_refresh_list()
			_refresh_detail()
		1:
			_refresh_yard()
		2:
			_refresh_sea()
	_fit_height.call_deferred()


func _fit_height() -> void:
	get_tree().call_group("military_panel", "_fit_height")


## Height of what the current tab holds, for the Military window to fit itself to.
func content_height() -> float:
	var boxes: Array[Control] = [_fleet_box, _yard_box, _sea_box]
	return boxes[clampi(_tabs.current_tab, 0, boxes.size() - 1)].get_combined_minimum_size().y + 34.0


static func _where(f: Fleet) -> String:
	if f.port > 0:
		return MapData.provinces[f.port].name
	return "the " + MapData.sea_zones[f.zone].name


func _refresh_list() -> void:
	var mine := Navy.fleets_of(GameState, GameState.player_tag)
	var ids: Array[int] = []
	for f in mine:
		ids.append(f.id)
	_selected = _selected.filter(func(id: int) -> bool: return ids.has(id))
	var rebuild := ids != _listed
	if rebuild:
		_list.clear()
		_listed = ids
	for i in mine.size():
		var f := mine[i]
		var text := "%s · %s · %d sq." % [f.display_name, _where(f), f.ships.size()]
		if f.fighting:
			text += " · FIGHTING"
		elif f.retreating:
			text += " · retreating"
		elif f.is_moving():
			text += " · sailing"
		if rebuild:
			_list.add_item(text)
		else:
			_list.set_item_text(i, text)
		_list.set_item_custom_fg_color(i, Fmt.BAD if f.fighting else Color.WHITE)
	if rebuild:
		_sync_selection()


func _refresh_detail() -> void:
	var fleets := _selected_fleets()
	_mission.disabled = fleets.is_empty()
	_deselect.disabled = fleets.is_empty()
	_home.disabled = fleets.is_empty()
	_show.disabled = fleets.is_empty()
	var same_place := fleets.size() >= 2 and fleets.all(func(x: Fleet) -> bool: return x.port == fleets[0].port and x.zone == fleets[0].zone)
	_merge.disabled = not same_place
	_refresh_split_picker(fleets[0] if fleets.size() == 1 else null)
	if fleets.is_empty():
		_detail.text = "No fleet selected. Click a fleet on the map, or in the list."
		return
	_updating = true
	for i in _mission.item_count:
		if _mission.get_item_metadata(i) == fleets[0].mission:
			_mission.select(i)
	_updating = false
	if fleets.size() > 1:
		var ships := 0
		var power := 0.0
		for f in fleets:
			ships += f.ships.size()
			power += f.power()
		_detail.text = "%d fleets, %d squadrons, fighting power %.0f." % [fleets.size(), ships, power]
		return
	var f := fleets[0]
	var counts: PackedStringArray = []
	for type in f.composition():
		counts.append("%d %s" % [f.composition()[type], Navy.cfg.types[type].name.to_lower()])
	var strength := 0.0
	for s in f.ships:
		strength += s.strength
	var lines: PackedStringArray = [
		f.display_name,
		", ".join(counts),
		"Strength %d%% · morale %d%% · fighting power %.0f · speed %d km/day" % [
				roundi(strength / maxf(f.ships.size(), 1) * 100.0), roundi(f.morale() * 100.0), f.power(), roundi(f.speed())],
	]
	if f.is_in_port():
		lines.append("In %s (level %d yard)." % [MapData.provinces[f.port].name, Navy.port_level(GameState, f.port)])
	else:
		lines.append("At sea in the %s, %d days out of port%s." % [MapData.sea_zones[f.zone].name, f.days_out,
				"" if f.days_out <= 0 or f.days_out <= _shortest_range(f) else " — beyond its range, wearing down"])
	if f.is_moving():
		var target := ""
		if f.dest_port > 0:
			target = MapData.provinces[f.dest_port].name
		elif not f.path.is_empty():
			target = "the " + MapData.sea_zones[f.path.back()].name
		lines.append("Sailing%s." % ((" to " + target) if target != "" else ""))
	if f.landing > 0:
		lines.append("Landing at %s." % MapData.provinces[f.landing].name)
	var aboard := Navy.armies_aboard(GameState, f)
	if f.capacity() > 0:
		lines.append("Carries %s of %s men." % [Fmt.people(Navy.men_aboard(GameState, f)), Fmt.people(f.capacity())])
	for a in aboard:
		lines.append("  aboard: %s (%s)" % [a.display_name, Fmt.people(a.men())])
	_detail.text = "\n".join(lines)


static func _shortest_range(f: Fleet) -> int:
	var shortest := 9999
	for s in f.ships:
		shortest = mini(shortest, s.def().range_days)
	return shortest


func _refresh_split_picker(f: Fleet) -> void:
	var sig := "none"
	if f != null:
		sig = "%d:%s" % [f.id, str(f.composition())]
	if sig == _split_sig:
		_split.disabled = f == null or f.ships.size() < 2
		return
	_split_sig = sig
	_split_type.clear()
	if f != null:
		for type in f.composition():
			_split_type.add_item("%s (%d)" % [Navy.cfg.types[type].name, f.composition()[type]])
			_split_type.set_item_metadata(_split_type.item_count - 1, type)
		_split_type.select(0)
		_split_count.max_value = maxi(f.ships.size() - 1, 1)
		_split_count.value = 1
	_split.disabled = f == null or f.ships.size() < 2
	_split_type.disabled = f == null


func _refresh_yard() -> void:
	var tag := GameState.player_tag
	var n := GameState.get_player()
	if n == null:
		return
	var type: String = _type_picker.get_item_metadata(_type_picker.selected)
	var count := int(_count.value)
	var ok_province := _province > 0 and GameState.province_owner[_province] == tag and not MapData.zones_of_port(_province).is_empty()
	if ok_province:
		var level := Navy.port_level(GameState, _province)
		_yard_title.text = "%s — level %d yard" % [MapData.provinces[_province].name, level]
		var zones: PackedStringArray = []
		for z in MapData.zones_of_port(_province):
			zones.append(MapData.sea_zones[z].name)
		var docked := Navy.fleets_in_port(GameState, _province)
		var ships := 0
		for f in docked:
			if f.tag == tag:
				ships += f.ships.size()
		_yard_info.text = "Opens on the %s.\nOn the slips: %d of %d. In port: %d squadrons." % [
				" and ".join(zones), Navy.building_in(GameState, tag, _province), Navy.yard_slots(GameState, _province), ships]
	else:
		_yard_title.text = "Shipyard"
		_yard_info.text = "Select one of your coastal provinces on the map to build ships there."
	var problem := Navy.build_problem(GameState, tag, _province, type, count) if ok_province else "Select a coastal province of yours."
	var def: Dictionary = Navy.cfg.types[type]
	var mats: PackedStringArray = []
	for r in def.materials:
		mats.append("%s %s" % [Fmt.kt(def.materials[r] * count), Economy.cfg.resources[r].name.to_lower()])
	var cost := "£%.1fM, %d days, needs a level %d port, %s" % [def.cost * count, def.build_days, def.min_port, ", ".join(mats)]
	if ok_province and problem.is_empty() or (ok_province and problem.begins_with("Not enough money")):
		cost = "£%.1fM with materials, %d days" % [Navy.ship_plan(GameState, tag, type, count).total, def.build_days]
	_build.disabled = not problem.is_empty()
	_build_label.text = cost if problem.is_empty() else "%s (%s)" % [problem, cost]
	_build_label.modulate = Color.WHITE if problem.is_empty() else Fmt.WARN
	var queue: Array = n.shipbuilding.duplicate()
	queue.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.days_left < b.days_left)
	var lines: PackedStringArray = []
	for job in queue:
		lines.append("%s at %s: %d days" % [Navy.cfg.types[job.type].name, MapData.provinces[job.province].name, job.days_left])
	_queue_label.text = "Under construction:\n" + "\n".join(lines) if not lines.is_empty() else "Nothing under construction."
	# The nation's ports with a yard.
	var yards: Array[int] = []
	for id in n.provinces:
		if Navy.port_level(GameState, id) > 0 and not MapData.zones_of_port(id).is_empty():
			yards.append(id)
	yards.sort_custom(func(a: int, b: int) -> bool: return Navy.port_level(GameState, a) > Navy.port_level(GameState, b) or (Navy.port_level(GameState, a) == Navy.port_level(GameState, b) and a < b))
	if yards != _yards:
		_yards = yards
		_yard_list.clear()
		for id in yards:
			_yard_list.add_item("%s · level %d" % [MapData.provinces[id].name, Navy.port_level(GameState, id)])


func _on_build() -> void:
	var type: String = _type_picker.get_item_metadata(_type_picker.selected)
	GameState.issue(RaiseShips.new(GameState.player_tag, _province, type, int(_count.value)))
	_refresh()


func _refresh_sea() -> void:
	var tag := GameState.player_tag
	var n := GameState.get_player()
	var lines: PackedStringArray = []
	var mine := 0
	var power := 0.0
	for f in Navy.fleets_of(GameState, tag):
		mine += f.ships.size()
		power += f.power()
	lines.append("%d squadrons afloat, fighting power %.0f. Navy costs £%.1fM a month (£%.1fM of it ships)." % [
			mine, power, Fmt.monthly(n.naval_budget), Fmt.monthly(Navy.ship_upkeep(GameState, tag))])
	var theirs := 0.0
	var their_ships := 0
	for other in GameState.nations:
		if other != tag and GameState.at_war(tag, other):
			for f in Navy.fleets_of(GameState, other):
				theirs += f.power()
				their_ships += f.ships.size()
	if their_ships > 0:
		lines.append("The navies of your enemies: %d squadrons, fighting power %.0f." % [their_ships, theirs])
	if n.blockade > 0.005:
		var by: PackedStringArray = []
		for t in n.blockade_by:
			by.append(GameState.nations[t].display_name)
		lines.append("YOU ARE BLOCKADED: %d%% of your trade is cut%s." % [roundi(n.blockade * 100.0), (" by " + ", ".join(by)) if not by.is_empty() else ""])
	for other_tag in GameState.nations:
		var o: Nation = GameState.nations[other_tag]
		if other_tag != tag and o.blockade > 0.05 and o.blockade_by.has(tag):
			lines.append("You blockade %s: %d%%." % [o.display_name, roundi(o.blockade * 100.0)])
	_sea_summary.text = "\n".join(lines)
	var zones: Array[int] = []
	for z: int in GameState.sea_control:
		zones.append(z)
	zones.sort()
	_sea_zones_listed = zones
	_sea_list.clear()
	for z in zones:
		var c: Dictionary = GameState.sea_control[z]
		var who := "contested" if c.contested else ", ".join(c.holders.map(func(t: String) -> String: return GameState.nations[t].display_name))
		_sea_list.add_item("%s · %s" % [MapData.sea_zones[z].name, who])
		_sea_list.set_item_custom_fg_color(_sea_list.item_count - 1, Fmt.BAD if c.contested else (Fmt.GOOD if c.holders.has(tag) else Color.WHITE))
	if zones.is_empty():
		_sea_list.add_item("No fleet holds any zone.")


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_N and not event.ctrl_pressed and not event.alt_pressed:
			toggle()
		elif event.keycode == KEY_ESCAPE and not _selected.is_empty():
			clear_selection()
