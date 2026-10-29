extends FloatingWindow


## The military page of the Nation screen: mobilization and manpower at a glance, then folding sections for
## fronts, recruiting and wars. Orders to the armies themselves (merge, split, symbol, board) are the command
## panel's (C). It also keeps the selection: clicking a province selects the player's armies standing there
## (dragging a box selects every army inside it); a right click on another province sends them there. A front is a
## line of provinces drawn on the map with armies assigned to it: they spread along the line and hold it.
## Toggle with M. The fleets, shipyard and sea state are the Navy page (Y).

var _slider_label := Label.new()
var _mob_note := Label.new()
var _rows: Dictionary = {}
var _type_picker := OptionButton.new()
var _count := SpinBox.new()
var _raise := Button.new()
var _raise_label := Label.new()
var _scroll := ScrollContainer.new()
var _box := VBoxContainer.new()
var _fronts_box := VBoxContainer.new()
var _recruit_box := VBoxContainer.new()
## The page stacks three folding sections: fronts, recruiting and wars. Each has a header
## button and the section's content box, keyed by name.
var _sections: Dictionary = {}
var _section_heads: Dictionary = {}
var _wars_box := VBoxContainer.new()
var _wars_list := ItemList.new()
var _war_summary := Label.new()
var _peace_button := Button.new()
var _war_table := GridContainer.new()
var _war_cells: Array = []
var _war_filter := OptionButton.new()
var _war_log := ItemList.new()
var _war_battles := ItemList.new()
var _war_battle_ids: Array[int] = []
var _war_battles_key := ""
var _wars_listed: Array[int] = []
var _war_selected := 0
var _war_log_key := ""
var _fronts_list := ItemList.new()
var _front_detail := Label.new()
var _face_button := Button.new()
var _draw_button := Button.new()
var _garrison_button := Button.new()
## What the provinces being picked on the map are for: "line" (a front, joined), "garrison" (one by one), "push" (a
## plan's target line), "phase" (a further line for the plan) or "spearhead" (one province).
var _draft_mode := "line"
## The selected army's plan of attack: its state, the buttons and the aggressiveness.
var _plan_label := Label.new()
var _plan_push := Button.new()
var _plan_spear := Button.new()
var _plan_phase := Button.new()
var _plan_launch := Button.new()
var _plan_cancel := Button.new()
var _plan_aggr := OptionButton.new()
const GARRISON_HINT := "Click the provinces to guard; click one again to drop it. Enter or Finish when done."
const PLAN_HINTS := {
	"push": "Click the enemy provinces of the line to reach; click one again to drop it. Enter or Finish when done.",
	"spearhead": "Click the province to strike at.",
	"phase": "Click the provinces of the next line; click one again to drop it. Enter or Finish when done.",
}
const AGGRESSIVENESS := [["careful", "Careful"], ["balanced", "Balanced"], ["aggressive", "Aggressive"]]
var _draw_hint := Label.new()
var _face_row := VBoxContainer.new()
var _assign_button := Button.new()
var _release_button := Button.new()
var _delete_button := Button.new()
## How the chosen front is held (SetFrontPolicy "cohesion"), and the army group to put on it whole.
var _cohesion := OptionButton.new()
var _group_pick := OptionButton.new()
var _group_ids: Array[int] = []
const COHESIONS := [["rigid", "Rigid"], ["balanced", "Balanced"], ["flexible", "Flexible"]]
var _draw_row := VBoxContainer.new()
var _front_name := LineEdit.new()

## Ids of the selected armies; the list mirrors it.
var _selected: Array[int] = []
var _province := 0
var _updating := false
## Fronts: ids in list order, the chosen one, and the line being drawn (if any).
var _front_ids: Array[int] = []
var _front_selected := 0
var _drawing := false
## True while waiting for a click on the nation a new front should face.
var _picking_nation := false
var _draft: Array[int] = []
## Whether the front being drawn or picked should take the selected armies once it exists.
var _assign_new := false


func _ready() -> void:
	add_to_group("military_panel")
	visible = false

	# The content scrolls when it is taller than the space above the map mode bar.
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.custom_minimum_size = Vector2(320, 100)
	for b: VBoxContainer in [_fronts_box, _recruit_box, _wars_box]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_constant_override("separation", 4)
	add_child(_scroll)
	setup_window("Military", true, Vector2(500, 0), 1)
	_box.add_theme_constant_override("separation", 4)
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var page := VBoxContainer.new()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", 4)
	_scroll.add_child(page)
	page.add_child(_box)
	_add_section(page, "Fronts", _fronts_box, false)
	_add_section(page, "Recruit", _recruit_box, false)
	_add_section(page, "Wars", _wars_box, false)
	get_viewport().size_changed.connect(_fit_height)
	var box := _box
	var fronts_box := _fronts_box
	var recruit_box := _recruit_box

	var row := HBoxContainer.new()
	var name_label := Label.new()
	name_label.text = "Mobilization"
	name_label.custom_minimum_size = Vector2(100, 0)
	_slider_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_slider_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slider_label.tooltip_text = "Set the mobilization level under Economy, People (E)."
	for c in [name_label, _slider_label]:
		row.add_child(c)
	box.add_child(row)
	_mob_note.modulate = Fmt.WARN
	_mob_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_mob_note)

	var figures := GridContainer.new()
	figures.columns = 4
	figures.add_theme_constant_override("h_separation", 8)
	figures.add_theme_constant_override("v_separation", 1)
	figures.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for key in ["reserve", "armed", "pool", "army", "output", "support"]:
		var l := Label.new()
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.modulate = Fmt.DIM
		l.clip_text = true
		var v := Label.new()
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		figures.add_child(l)
		figures.add_child(v)
		_rows[key] = [l, v]
	box.add_child(figures)
	box.add_child(HSeparator.new())

	var fronts_title := Label.new()
	fronts_title.text = "A front is a line of provinces to hold; armies assigned to it spread along it."
	fronts_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fronts_title.custom_minimum_size = Vector2(300, 0)
	fronts_title.modulate = Fmt.DIM
	fronts_box.add_child(fronts_title)
	_fronts_list.custom_minimum_size = Vector2(0, 70)
	_fronts_list.focus_mode = Control.FOCUS_NONE
	_fronts_list.item_selected.connect(func(i: int) -> void:
		_front_selected = _front_ids[i]
		get_tree().call_group("army_layer", "set_selected_front", _front_selected)
		_refresh_fronts()
	)
	_fronts_list.item_activated.connect(func(i: int) -> void:
		var f: Front = GameState.fronts.get(_front_ids[i])
		if f and not f.provinces.is_empty():
			get_tree().call_group("camera_focus", "focus_on", MapData.provinces[f.provinces[f.provinces.size() / 2]].center)
	)
	fronts_box.add_child(_fronts_list)
	_front_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_front_detail.custom_minimum_size = Vector2(320, 0)
	_front_detail.modulate = Fmt.DIM
	fronts_box.add_child(_front_detail)
	var front_buttons := HBoxContainer.new()
	_face_button.text = "Front vs nation"
	_face_button.tooltip_text = "Click a province of a neighbouring nation: your front is every province of yours that borders it, and it follows the war."
	_face_button.pressed.connect(_begin_picking_nation)
	_draw_button.text = "Draw line"
	_draw_button.tooltip_text = "Click provinces on the map, one after another, to lay out a line by hand."
	_draw_button.pressed.connect(_begin_drawing)
	_garrison_button.text = "Garrison"
	_garrison_button.tooltip_text = "Click provinces of yours to guard (ports, cities, the capital): an army put on the garrison keeps a share of its divisions in each. A line drawn in your own ground, away from the enemy, is a fallback line: armies on it dig in deeper and faster."
	_garrison_button.pressed.connect(func() -> void: _begin_picking("garrison", GARRISON_HINT))
	_assign_button.text = "Assign"
	_assign_button.tooltip_text = "Put the selected armies on the chosen front; they spread along it and hold it."
	_assign_button.pressed.connect(_on_assign)
	_release_button.text = "Release"
	_release_button.tooltip_text = "Take the selected armies off their front."
	_release_button.pressed.connect(_on_release)
	_delete_button.text = "Delete"
	_delete_button.pressed.connect(_on_delete_front)
	for b in [_face_button, _draw_button, _garrison_button, _assign_button, _release_button, _delete_button]:
		b.focus_mode = Control.FOCUS_NONE
		front_buttons.add_child(b)
	fronts_box.add_child(front_buttons)
	var policy_row := HBoxContainer.new()
	var cohesion_label := Label.new()
	cohesion_label.text = "Cohesion"
	policy_row.add_child(cohesion_label)
	_cohesion.focus_mode = Control.FOCUS_NONE
	_cohesion.tooltip_text = "How far along the line a division may be sent to fill a gap. Rigid: two provinces, each holds its own stretch. Balanced: six. Flexible: anywhere along the front."
	for c in COHESIONS:
		_cohesion.add_item(c[1])
	_cohesion.item_selected.connect(func(i: int) -> void:
		GameState.issue(SetFrontPolicy.new(GameState.player_tag, _front_selected, "cohesion", COHESIONS[i][0]))
	)
	policy_row.add_child(_cohesion)
	_group_pick.focus_mode = Control.FOCUS_NONE
	_group_pick.tooltip_text = "Put a whole army group on the chosen front: each of its armies takes a stretch of the line of its own, side by side, in the order they stand."
	_group_pick.item_selected.connect(_on_group_picked)
	policy_row.add_child(_group_pick)
	fronts_box.add_child(policy_row)
	# The selected army's plan of attack.
	var plan_title := Label.new()
	plan_title.text = "Attack plan (selected army)"
	plan_title.modulate = Fmt.DIM
	fronts_box.add_child(plan_title)
	_plan_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_plan_label.custom_minimum_size = Vector2(320, 0)
	fronts_box.add_child(_plan_label)
	var plan_row := HBoxContainer.new()
	_plan_push.text = "Push to line"
	_plan_push.tooltip_text = "Click the enemy provinces to reach: every division of the army on its front pushes toward them from where it stands, once it has planned."
	_plan_push.pressed.connect(func() -> void: _begin_picking("push", PLAN_HINTS.push))
	_plan_spear.text = "Spearhead"
	_plan_spear.tooltip_text = "Click one province: the army gathers and strikes toward it with its whole weight, one province at a time."
	_plan_spear.pressed.connect(func() -> void: _begin_picking("spearhead", PLAN_HINTS.spearhead))
	_plan_phase.text = "Add phase"
	_plan_phase.tooltip_text = "Click a further line to reach once the present one is taken: the army digs in on the line it reached, plans again, and pushes on."
	_plan_phase.pressed.connect(func() -> void: _begin_picking("phase", PLAN_HINTS.phase))
	_plan_launch.tooltip_text = "Launch the attack (it goes once the divisions have planned, at once if aggressive), or halt it and go on planning."
	_plan_launch.pressed.connect(_on_launch)
	_plan_cancel.text = "Cancel"
	_plan_cancel.tooltip_text = "Drop the plan."
	_plan_cancel.pressed.connect(func() -> void:
		var o := _plan()
		if o != null:
			GameState.issue(SetOffensive.new(GameState.player_tag, o.id, "cancel"))
	)
	for b in [_plan_push, _plan_spear, _plan_phase, _plan_launch, _plan_cancel]:
		b.focus_mode = Control.FOCUS_NONE
		plan_row.add_child(b)
	fronts_box.add_child(plan_row)
	var aggr_row := HBoxContainer.new()
	var aggr_label := Label.new()
	aggr_label.text = "Aggressiveness"
	aggr_row.add_child(aggr_label)
	_plan_aggr.focus_mode = Control.FOCUS_NONE
	_plan_aggr.tooltip_text = "Careful attacks only at odds of two to one and stops when morale is low; Balanced attacks at fair odds; Aggressive attacks at even odds and does not stop for morale or losses."
	for a in AGGRESSIVENESS:
		_plan_aggr.add_item(a[1])
	_plan_aggr.select(1)
	_plan_aggr.item_selected.connect(func(i: int) -> void:
		var o := _plan()
		if o != null:
			GameState.issue(SetOffensive.new(GameState.player_tag, o.id, "aggressiveness", AGGRESSIVENESS[i][0]))
	)
	aggr_row.add_child(_plan_aggr)
	fronts_box.add_child(aggr_row)
	var face_hint := Label.new()
	face_hint.text = "Click a province of the nation to face. Esc cancels."
	face_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	face_hint.custom_minimum_size = Vector2(320, 0)
	face_hint.modulate = Fmt.WARN
	_face_row.add_child(face_hint)
	_face_row.visible = false
	fronts_box.add_child(_face_row)
	var draw_hint := _draw_hint
	draw_hint.text = "Click provinces along the line. Click the last one again to remove it."
	draw_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	draw_hint.custom_minimum_size = Vector2(320, 0)
	draw_hint.modulate = Fmt.WARN
	_draw_row.add_child(draw_hint)
	var draw_buttons := HBoxContainer.new()
	_front_name.placeholder_text = "Front name"
	_front_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var finish := Button.new()
	finish.text = "Finish"
	finish.focus_mode = Control.FOCUS_NONE
	finish.pressed.connect(_finish_drawing)
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.focus_mode = Control.FOCUS_NONE
	cancel.pressed.connect(_end_drawing)
	for c in [_front_name, finish, cancel]:
		draw_buttons.add_child(c)
	_draw_row.add_child(draw_buttons)
	_draw_row.visible = false
	fronts_box.add_child(_draw_row)

	var recruit_title := Label.new()
	recruit_title.text = "Recruit in the selected province"
	recruit_box.add_child(recruit_title)
	var recruit := HBoxContainer.new()
	_type_picker.focus_mode = Control.FOCUS_NONE
	for type in Military.unit_type_ids():
		_type_picker.add_item(Military.cfg.unit_types[type].name)
		_type_picker.set_item_metadata(_type_picker.item_count - 1, type)
	_type_picker.item_selected.connect(func(_i: int) -> void: _refresh_recruit())
	_count.min_value = 1
	_count.max_value = 10
	_count.value = 1
	_count.value_changed.connect(func(_v: float) -> void: _refresh_recruit())
	_raise.text = "Raise"
	_raise.focus_mode = Control.FOCUS_NONE
	_raise.pressed.connect(_on_raise)
	for c in [_type_picker, _count, _raise]:
		recruit.add_child(c)
	recruit_box.add_child(recruit)
	_raise_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_raise_label.custom_minimum_size = Vector2(320, 0)
	_raise_label.modulate = Fmt.DIM
	recruit_box.add_child(_raise_label)
	recruit_box.add_child(HSeparator.new())

	_build_wars_tab()
	GameState.economy_updated.connect(_refresh)
	GameState.armies_changed.connect(_refresh)
	GameState.fronts_changed.connect(_refresh)
	GameState.player_changed.connect(func(_t: String) -> void:
		_end_drawing()
		_front_selected = 0
		_selected.clear()
		_sync_selection()
		_refresh()
	)
	_refresh()


func toggle() -> void:
	toggle_window()
	if visible:
		_refresh()


## A folding section of the page: a header button that shows or hides `content`.
func _add_section(parent: Control, title: String, content: Control, open: bool) -> void:
	var head := Button.new()
	head.alignment = HORIZONTAL_ALIGNMENT_LEFT
	head.focus_mode = Control.FOCUS_NONE
	head.flat = true
	head.pressed.connect(func() -> void: set_section(title, not content.visible))
	parent.add_child(head)
	parent.add_child(content)
	_sections[title] = content
	_section_heads[title] = head
	set_section(title, open)


## Opens or folds one section of the page.
func set_section(title: String, open: bool) -> void:
	var content: Control = _sections[title]
	content.visible = open
	_section_heads[title].text = "%s %s" % ["▾" if open else "▸", title]
	_fit_height.call_deferred()


## Opens the page, with one of its sections ("Fronts", "Recruit", "Wars") unfolded; or closes it, with `open` false.
func show_tab(section: String, open := true) -> void:
	if not open:
		close_window()
		return
	if _sections.has(section):
		set_section(section, true)
	visible = true
	move_to_front()
	_refresh()


## The map's selected province changed: select the player's armies standing there, or, while
## a front is being drawn, add the province to the line.
func set_province(id: int) -> void:
	if _picking_nation:
		_pick_nation(id)
		return
	if _drawing:
		_add_to_draft(id)
		return
	_province = id
	var here: Array[int] = []
	for a in Military.armies_at(GameState, id):
		if a.tag == GameState.player_tag:
			here.append(a.id)
	# Clicking ground with none of your armies, or clicking the selected armies again,
	# deselects.
	var same := not here.is_empty() and here.size() == _selected.size() and here.all(func(x: int) -> bool: return _selected.has(x))
	if here.is_empty() or same:
		_selected.clear()
	else:
		_selected = here
	_sync_selection()
	_refresh()


## Whether a right click would give an order: armies are selected, or a front is being set up.
func has_selection() -> bool:
	return not _selected.is_empty() or _drawing or _picking_nation


## The armies selected, as ids.
func selected_ids() -> Array[int]:
	return _selected.duplicate()


## Selects exactly these armies (the action bar's merge and split use it).
func select_ids(ids: Array[int]) -> void:
	_selected = ids.filter(func(id: int) -> bool: return GameState.armies.has(id))
	_sync_selection()
	_refresh()


func clear_selection() -> void:
	_selected.clear()
	_sync_selection()
	_refresh()


## Right click on the map: send the selected armies there. An embarked army lands there if its
## fleet is off that coast; an army that cannot walk there sails if a fleet with transports lies
## in its port.
func order_move(province: int) -> void:
	if _selected.is_empty() or _drawing or _picking_nation:
		return
	var failed: Array[int] = []
	for id in _selected.duplicate():
		var a: Army = GameState.armies.get(id)
		if a != null and a.embarked():
			if not GameState.issue(DisembarkArmy.new(GameState.player_tag, id, province)):
				failed.append(id)
		elif not GameState.issue(MoveArmy.new(GameState.player_tag, id, province)):
			failed.append(id)
	if not failed.is_empty():
		failed = _send_overseas(failed, province)
	if not failed.is_empty():
		get_tree().call_group("event_feed", "say", "%d of %d armies cannot reach %s. %s" % [failed.size(), _selected.size(), MapData.provinces[province].name, _why_not(failed, province)], Fmt.WARN)
	_refresh()


## The reason armies cannot get to a province, in a sentence.
func _why_not(ids: Array[int], province: int) -> String:
	var me := GameState.player_tag
	if not Military.can_enter(GameState, me, province):
		var holder: String = GameState.province_owner[province]
		return "The border is closed: you are not at war with %s and have no passage." % GameState.nations[holder].display_name
	var a: Army = GameState.armies.get(ids[0])
	if a == null:
		return ""
	if a.embarked():
		return "The fleet must be off that coast."
	if MapData.zones_of_port(province).is_empty():
		return "There is no land route."
	var carriers := false
	for f in Navy.fleets_in_port(GameState, a.province):
		carriers = carriers or (f.tag == me and f.capacity() > 0)
	if not carriers:
		return "There is no land route, and no transports lie in %s: bring a fleet with transport squadrons there." % MapData.provinces[a.province].name
	return "There is no land route, and the transports in port cannot take them (room, or no sea route)."


## Sends armies that could not walk to a coast by sea, one fleet per port. Returns those that
## could not go.
func _send_overseas(ids: Array[int], province: int) -> Array[int]:
	var left: Array[int] = []
	var by_port := {}
	for id in ids:
		var a: Army = GameState.armies.get(id)
		if a == null or a.embarked():
			left.append(id)
			continue
		if not by_port.has(a.province):
			by_port[a.province] = []
		by_port[a.province].append(id)
	for port: int in by_port:
		var group: Array[int] = []
		group.assign(by_port[port])
		var sent := false
		for f in Navy.fleets_in_port(GameState, port):
			if f.tag == GameState.player_tag and SendOverseas.problem(GameState, GameState.player_tag, f.id, group, province) == "":
				sent = GameState.issue(SendOverseas.new(GameState.player_tag, f.id, group, province))
				break
		if not sent:
			left.append_array(group)
	return left


## Puts the selected armies aboard a fleet with room in their port.
func _on_board() -> void:
	var mine := GameState.player_tag
	for id in _selected.duplicate():
		var a: Army = GameState.armies.get(id)
		if a == null or a.embarked():
			continue
		for f in Navy.fleets_in_port(GameState, a.province):
			if f.tag == mine and GameState.issue(EmbarkArmy.new(mine, id, f.id)):
				break
	_refresh()


## Puts the selected embarked armies ashore, in the port their fleet is in.
func _on_land() -> void:
	for id in _selected.duplicate():
		var a: Army = GameState.armies.get(id)
		if a != null and a.embarked():
			var f: Fleet = GameState.fleets.get(a.fleet_id)
			if f != null and f.is_in_port():
				GameState.issue(DisembarkArmy.new(GameState.player_tag, id, f.port))
	_refresh()


## One army was clicked among those fanned out on the selected province. Shift adds it to
## (or removes it from) the selection; a plain click selects just it, or deselects it if it
## is already the only one selected.
func select_army(id: int, additive := false) -> void:
	if _drawing or _picking_nation:
		return
	var a: Army = GameState.armies.get(id)
	if a == null or a.tag != GameState.player_tag:
		return
	if additive:
		if _selected.has(id):
			_selected.erase(id)
		else:
			_selected.append(id)
	elif _selected.size() == 1 and _selected[0] == id:
		_selected.clear()
	else:
		_selected = [id]
	_sync_selection()
	_refresh()


## A box was dragged on the map: select the player's armies whose province lies inside it.
func select_in_rect(rect: Rect2, additive := false) -> void:
	if _drawing or _picking_nation:
		return
	var ids: Array[int] = []
	if additive:
		ids.append_array(_selected)
	for a in Military.armies_of(GameState, GameState.player_tag):
		if rect.has_point(MapData.provinces[a.province].center) and not ids.has(a.id):
			ids.append(a.id)
	_selected = ids
	_sync_selection(true)
	_refresh()


## Tells the map and the command panel which armies are selected.
func _sync_selection(keep_fleets := false) -> void:
	get_tree().call_group("army_layer", "set_selection", _selected.duplicate())
	get_tree().call_group("command_panel", "set_selection", _selected.duplicate())
	if not _selected.is_empty() and not keep_fleets:
		get_tree().call_group("navy_panel", "clear_selection_quiet")


func _refresh() -> void:
	var n := GameState.get_player()
	if n == null or n.budget.is_empty():
		return
	var b := n.budget
	var cap := Economy.mobilization_cap(GameState, n)
	var least := Economy.mobilization_range(GameState, n).x
	_slider_label.text = "%d%%  (set under Economy)" % roundi(n.mobilization * 100.0)
	var floor_level: float = Diplomacy.cfg.crisis.war_floor
	var fighting := not GameState.wars_of(n.tag).is_empty()
	var notes: PackedStringArray = []
	if fighting and n.mobilization < floor_level + 0.001:
		notes.append("At war: a nation is held at a war footing of at least %d%% mobilization." % roundi(floor_level * 100.0))
	if cap < 0.999:
		notes.append("In peace a nation may mobilize only up to %d%%; at war it may go to the full." % roundi(cap * 100.0))
	if n.mobilization < least - 0.001:
		notes.append("At least %d%% is called up now; mobilization is rising to it." % roundi(least * 100.0))
	_mob_note.visible = not notes.is_empty()
	_mob_note.text = "
".join(notes)
	_set_row("reserve", "Recruit reserve", "%s / %s" % [_k(n.manpower), _k(maxf(0.0, b.manpower_max - n.men_in_units))])
	_set_row("armed", "Under arms", _k(n.men_in_units))
	_set_row("pool", "Manpower pool", _k(b.manpower_pool))
	_set_row("army", "Army upkeep", "£%.2fM/mo" % (b.army / 12.0))
	_set_row("support", "War support", "%d" % roundi(n.war_support))
	var tip := WarSupport.effects_text(GameState, n.tag) + "\nThis month so far:\n" + WarSupport.drivers_text(GameState, n.tag)
	for part in _rows["support"]:
		part.tooltip_text = tip
		part.mouse_filter = Control.MOUSE_FILTER_PASS
	_set_row("output", "Output lost", "%d%%, factories %d%%" % [roundi(Economy.cfg.mobilization_output_penalty * n.mobilization * 100.0), roundi((1.0 - Economy.worker_share(n)) * 100.0)])
	_selected = _selected.filter(func(id: int) -> bool: return GameState.armies.has(id))
	if visible:
		_refresh_fronts()
		_refresh_recruit()
		_refresh_wars()
		_fit_height.call_deferred()


## Sizes the scroll area to its content, but never past the space above the map mode bar.
func _fit_height() -> void:
	if not is_inside_tree():
		return
	fit_window(minf(_scroll.get_child(0).get_combined_minimum_size().y, 460.0) + 34.0)


func _on_merge() -> void:
	var ids: Array[int] = _selected.duplicate()
	if GameState.issue(MergeArmies.new(GameState.player_tag, ids)):
		_selected = [ids[0]]
		_sync_selection()


func _on_split() -> void:
	if _selected.size() != 1:
		return
	var a: Army = GameState.armies.get(_selected[0])
	if a == null:
		return
	var idx: Array[int] = []
	for i in range(1, a.units.size(), 2):
		idx.append(i)
	var cmd := SplitArmy.new(GameState.player_tag, a.id, idx)
	if GameState.issue(cmd):
		_selected = [a.id, cmd.new_army_id]
		_sync_selection()


# ------------------------------------------------------------------ fronts

func _refresh_fronts() -> void:
	var mine: Array[Front] = []
	for f: Front in GameState.fronts.values():
		if f.tag == GameState.player_tag:
			mine.append(f)
	mine.sort_custom(func(x: Front, y: Front) -> bool: return x.id < y.id)
	var ids: Array[int] = []
	for f in mine:
		ids.append(f.id)
	if ids != _front_ids:
		_fronts_list.clear()
		_front_ids = ids
		for f in mine:
			_fronts_list.add_item(f.display_name)
	for i in mine.size():
		var men := 0.0
		for id in mine[i].army_ids:
			if GameState.armies.has(id):
				# With its detachments along the line.
				for st: Army in FrontSolver.stacks_of(GameState, GameState.armies[id]):
					men += st.men()
		var kind := " (garrison)" if mine[i].kind == "garrison" else (" (fallback line)" if mine[i].is_fallback(GameState) else "")
		var count: int = mine[i].army_ids.size()
		_fronts_list.set_item_text(i, "%s%s · %d %s · %s" % [mine[i].display_name, kind, count, "army" if count == 1 else "armies", Fmt.people(men)])
		if mine[i].id == _front_selected:
			_fronts_list.select(i)
	if not ids.has(_front_selected):
		_front_selected = 0
		get_tree().call_group("army_layer", "set_selected_front", 0)
	var chosen: Front = GameState.fronts.get(_front_selected)
	_cohesion.disabled = chosen == null or not chosen.spread
	if chosen != null:
		_cohesion.select(maxi(0, COHESIONS.map(func(c: Array) -> String: return c[0]).find(chosen.cohesion)))
	_refresh_group_pick(chosen)
	_refresh_plan()
	_delete_button.disabled = chosen == null
	_assign_button.disabled = chosen == null or _selected.is_empty()
	_release_button.disabled = _selected.is_empty()
	if chosen == null:
		_front_detail.text = "No front chosen. Draw one, then assign armies to it."
		return
	if chosen.provinces.is_empty():
		_front_detail.text = "%s: no common border at the moment." % chosen.display_name
		return
	var held := {}
	for p in chosen.provinces:
		held[p] = 0.0
	for id in chosen.army_ids:
		var root: Army = GameState.armies.get(id)
		if root == null:
			continue
		for a: Army in FrontSolver.stacks_of(GameState, root):
			if held.has(a.province):
				held[a.province] += a.men()
	var weakest: int = chosen.provinces[0]
	for p in chosen.provinces:
		if held[p] < held[weakest]:
			weakest = p
	var line_names: PackedStringArray = []
	for p in chosen.provinces:
		line_names.append(MapData.provinces[p].name)
	_front_detail.text = "%s: %s.\nWeakest point: %s (%s men).%s" % [
		chosen.display_name,
		"%d border provinces" % chosen.provinces.size() if not chosen.against.is_empty() else " → ".join(line_names),
		MapData.provinces[weakest].name, Fmt.people(held[weakest]), _sectors_text(chosen)]


## Each army's stretch of a broad front, in order along the line: "1st Army: Posen to Thorn, 5 provinces, 12 divisions".
func _sectors_text(f: Front) -> String:
	if not f.spread or f.sectors.size() < 1 or f.order.is_empty():
		return ""
	var rows: Array = []
	for id in f.sectors:
		var root: Army = GameState.armies.get(id)
		if root == null:
			continue
		var span: Vector2i = f.sectors[id]
		var divisions := 0
		for s: Army in FrontSolver.stacks_of(GameState, root):
			divisions += s.units.size()
		var a_name: String = MapData.provinces[f.order[span.x]].name
		var b_name: String = MapData.provinces[f.order[mini(span.y, f.order.size()) - 1]].name
		rows.append([span.x, "%s: %s%s, %d provinces, %d divisions" % [root.display_name, a_name, (" to " + b_name) if b_name != a_name else "", span.y - span.x, divisions]])
	rows.sort()
	return "\n" + "\n".join(PackedStringArray(rows.map(func(r: Array) -> String: return r[1])))


## The army groups that could be put on the chosen front whole.
func _refresh_group_pick(chosen: Front) -> void:
	var ids: Array[int] = []
	for g: ArmyGroup in GameState.army_groups.values():
		if g.tag == GameState.player_tag and not g.army_ids.is_empty():
			ids.append(g.id)
	ids.sort()
	if ids != _group_ids or _group_pick.item_count != ids.size() + 1:
		_group_ids = ids
		_group_pick.clear()
		_group_pick.add_item("Assign army group…")
		for id in ids:
			_group_pick.add_item(GameState.army_groups[id].display_name)
	_group_pick.select(0)
	_group_pick.disabled = chosen == null or ids.is_empty()


func _on_group_picked(i: int) -> void:
	if i <= 0 or i > _group_ids.size():
		return
	var g: ArmyGroup = GameState.army_groups.get(_group_ids[i - 1])
	if g != null:
		GameState.issue(AssignToFront.new(GameState.player_tag, _front_selected, g.army_ids.duplicate()))
	_group_pick.select(0)


## Starts a new front from the action bar: "draw" (click the provinces) or "face" (click a nation).
## The selected armies are put on it once it exists.
func begin_front(mode: String) -> void:
	show_tab("Fronts")
	if mode == "draw":
		_begin_drawing()
	elif mode == "garrison":
		_begin_picking("garrison", GARRISON_HINT)
	else:
		_begin_picking_nation()
	_assign_new = true


## Starts picking the provinces of a plan of attack from the action bar: "push", "spearhead" or "phase".
func begin_plan(mode: String) -> void:
	show_tab("Fronts")
	_begin_picking(mode, PLAN_HINTS[mode])


## Puts the selected armies on a front that has just been made, if the order came from the bar.
func _assign_to_new(front_id: int) -> void:
	if _assign_new and not _selected.is_empty():
		var ids: Array[int] = []
		for id in _selected:
			if GameState.armies.has(id) and not GameState.armies[id].embarked():
				ids.append(id)
		if not ids.is_empty():
			GameState.issue(AssignToFront.new(GameState.player_tag, front_id, ids))


func _begin_picking_nation() -> void:
	_end_drawing()
	_picking_nation = true
	_face_row.visible = true
	_fit_height.call_deferred()


## The player clicked a province while choosing which nation to face.
func _pick_nation(id: int) -> void:
	if id < 1:
		return
	var tag: String = GameState.province_owner[id]
	if tag == GameState.player_tag:
		tag = GameState.province_controller[id]  # own land held by an enemy: face the occupier
	var cmd := DesignateFront.new(GameState.player_tag, "", [], tag)
	if GameState.issue(cmd):
		_assign_to_new(cmd.front_id)
		_front_selected = cmd.front_id
		get_tree().call_group("army_layer", "set_selected_front", _front_selected)
		_end_drawing()
		_refresh_fronts()
	else:
		get_tree().call_group("event_feed", "say", DesignateFront.problem(GameState, GameState.player_tag, [], tag), Fmt.WARN)


func _begin_drawing() -> void:
	_end_drawing()
	_drawing = true
	_draft_mode = "line"
	_draw_hint.text = "Click provinces along the line. Click the last one again to remove it."


## Starts picking provinces on the map for a garrison, a plan's target line or phase, or a spearhead's target.
func _begin_picking(mode: String, hint: String) -> void:
	_begin_drawing()
	_draft_mode = mode
	_draw_hint.text = hint
	_draft.clear()
	_draw_row.visible = true
	_front_name.text = ""
	get_tree().call_group("army_layer", "set_draft", _draft.duplicate())
	_fit_height.call_deferred()


func _end_drawing() -> void:
	_assign_new = false
	_picking_nation = false
	_face_row.visible = false
	_drawing = false
	_draft.clear()
	_draw_row.visible = false
	get_tree().call_group("army_layer", "set_draft", _draft.duplicate())
	_fit_height.call_deferred()


## Adds a province to the line being drawn, filling any gap with the shortest route.
func _add_to_draft(id: int) -> void:
	if id < 1:
		return
	if _draft_mode == "spearhead":
		_draft = [id]
		_finish_drawing()
		return
	if _draft_mode != "line":
		if _draft.has(id):
			_draft.erase(id)
		elif _draft_mode != "garrison" or GameState.province_controller[id] == GameState.player_tag:
			_draft.append(id)
		get_tree().call_group("army_layer", "set_draft", _draft.duplicate())
		return
	if _draft.is_empty():
		_draft.append(id)
	elif id == _draft.back():
		_draft.pop_back()
	elif Military.neighbors(_draft.back()).has(id):
		if not _draft.has(id):
			_draft.append(id)
	else:
		var route := Military.find_path(GameState, GameState.player_tag, 15.0, _draft.back(), id)
		if route.is_empty():
			get_tree().call_group("event_feed", "say", "Your armies cannot reach %s from the end of the line." % MapData.provinces[id].name, Fmt.WARN)
			return
		for p in route:
			if not _draft.has(p):
				_draft.append(p)
	get_tree().call_group("army_layer", "set_draft", _draft.duplicate())


func _finish_drawing() -> void:
	if _draft_mode in ["push", "spearhead", "phase"]:
		_finish_plan()
		return
	var kind := "garrison" if _draft_mode == "garrison" else "line"
	var cmd := DesignateFront.new(GameState.player_tag, _front_name.text.strip_edges(), _draft.duplicate(), "", kind)
	if GameState.issue(cmd):
		_assign_to_new(cmd.front_id)
		_front_selected = cmd.front_id
		get_tree().call_group("army_layer", "set_selected_front", _front_selected)
		_end_drawing()
		_refresh_fronts()
	else:
		get_tree().call_group("event_feed", "say", DesignateFront.problem(GameState, GameState.player_tag, _draft, "", kind), Fmt.WARN)


## The army the plan buttons act on: the first selected stack's army.
func _plan_army() -> Army:
	if _selected.is_empty() or not GameState.armies.has(_selected[0]):
		return null
	return FrontSolver.root_of(GameState, GameState.armies[_selected[0]])


func _plan() -> Offensive:
	var root := _plan_army()
	return Offensives.of_army(GameState, root) if root != null else null


func _finish_plan() -> void:
	var root := _plan_army()
	var draft := _draft.duplicate()
	var mode := _draft_mode
	_end_drawing()
	if root == null or draft.is_empty():
		return
	var aggr: String = AGGRESSIVENESS[maxi(0, _plan_aggr.selected)][0]
	var ok := false
	if mode == "phase":
		var o := _plan()
		ok = o != null and GameState.issue(SetOffensive.new(GameState.player_tag, o.id, "phase", draft))
	else:
		ok = GameState.issue(PlanOffensive.new(GameState.player_tag, root.id, "spearhead" if mode == "spearhead" else "broad", draft, aggr))
	if not ok:
		get_tree().call_group("event_feed", "say", PlanOffensive.problem(GameState, GameState.player_tag, root.id, "spearhead" if mode == "spearhead" else "broad", draft, aggr) if mode != "phase" else "Make a plan first.", Fmt.WARN)
	_refresh_fronts()


func _on_launch() -> void:
	var o := _plan()
	if o != null:
		GameState.issue(SetOffensive.new(GameState.player_tag, o.id, "launch", not o.active))


## The selected army's plan: what it is, how far it has got, and the buttons that fit.
func _refresh_plan() -> void:
	var root := _plan_army()
	var o := _plan()
	for b in [_plan_push, _plan_spear]:
		b.disabled = root == null
	_plan_phase.disabled = o == null
	_plan_launch.disabled = o == null
	_plan_cancel.disabled = o == null
	_plan_aggr.disabled = o == null
	_plan_launch.text = "Halt" if o != null and o.active else "Launch"
	if root == null:
		_plan_label.text = "Select an army to plan its attack."
		return
	if o == null:
		_plan_label.text = "%s has no plan of attack." % root.display_name
		return
	_plan_aggr.select(maxi(0, AGGRESSIVENESS.map(func(a: Array) -> String: return a[0]).find(o.aggressiveness)))
	var what := "a push to a line of %d provinces" % o.targets().size()
	if o.kind == "spearhead" and not o.targets().is_empty():
		what = "a spearhead at %s" % MapData.provinces[o.targets()[0]].name
	elif o.kind == "invasion" and not o.targets().is_empty():
		what = "a landing at %s from %s" % [MapData.provinces[o.targets()[0]].name, MapData.provinces[o.port].name]
	var state := "attacking" if o.active and o.launched else ("launched, planning first" if o.active else "planned, not launched")
	_plan_label.text = "%s: %s, phase %d of %d, %s; planning %d%%." % [root.display_name, what, o.phase + 1, o.phases.size(), state, roundi(Offensives.planning_of(GameState, root) * 100.0)]


func _on_assign() -> void:
	var ids: Array[int] = _selected.duplicate()
	GameState.issue(AssignToFront.new(GameState.player_tag, _front_selected, ids))


func _on_release() -> void:
	var ids: Array[int] = _selected.duplicate()
	GameState.issue(AssignToFront.new(GameState.player_tag, 0, ids))


func _on_delete_front() -> void:
	GameState.issue(DeleteFront.new(GameState.player_tag, _front_selected))


# ------------------------------------------------------------------ wars tab

const WAR_ROWS := ["Battles won", "Battles lost", "Lost in battle", "Lost to attrition", "Cut off or lost",
		"Provinces taken", "People taken", "Enemy land held now"]
const FILTERS := ["All events", "Battles", "Occupations and losses"]


func _build_wars_tab() -> void:
	_wars_box.add_theme_constant_override("separation", 4)
	_wars_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_wars_list.custom_minimum_size = Vector2(0, 56)
	_wars_list.focus_mode = Control.FOCUS_NONE
	_wars_list.item_selected.connect(func(i: int) -> void:
		_war_selected = _wars_listed[i]
		_war_log_key = ""
		_refresh_wars()
	)
	_wars_box.add_child(_wars_list)
	_war_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_war_summary.custom_minimum_size = Vector2(320, 0)
	_wars_box.add_child(_war_summary)
	_peace_button.text = "Peace talks…"
	_peace_button.focus_mode = Control.FOCUS_NONE
	_peace_button.pressed.connect(func() -> void:
		get_tree().call_group("peace_screen", "open_war", _war_selected)
	)
	_wars_box.add_child(_peace_button)
	_war_table.columns = 3
	_war_table.add_theme_constant_override("h_separation", 12)
	for r in WAR_ROWS.size() + 1:
		var cells := []
		for c in 3:
			var l := Label.new()
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if c == 0 else HORIZONTAL_ALIGNMENT_RIGHT
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			l.clip_text = true
			if c == 0:
				l.custom_minimum_size = Vector2(110, 0)
				l.modulate = Fmt.DIM
			else:
				l.custom_minimum_size = Vector2(90, 0)
			_war_table.add_child(l)
			cells.append(l)
		_war_cells.append(cells)
	_wars_box.add_child(_war_table)
	_wars_box.add_child(HSeparator.new())
	var battles_title := Label.new()
	battles_title.text = "Battles"
	_wars_box.add_child(battles_title)
	_war_battles.custom_minimum_size = Vector2(0, 100)
	_war_battles.focus_mode = Control.FOCUS_NONE
	_war_battles.item_activated.connect(func(i: int) -> void: _open_battle(_war_battle_ids[i]))
	_wars_box.add_child(_war_battles)
	var open_battle := Button.new()
	open_battle.text = "Open battle screen"
	open_battle.tooltip_text = "The full account of the selected battle (double-click a battle does the same)."
	open_battle.focus_mode = Control.FOCUS_NONE
	open_battle.pressed.connect(func() -> void:
		var picked := _war_battles.get_selected_items()
		if not picked.is_empty():
			_open_battle(_war_battle_ids[picked[0]])
	)
	_wars_box.add_child(open_battle)
	_wars_box.add_child(HSeparator.new())
	var log_row := HBoxContainer.new()
	var log_title := Label.new()
	log_title.text = "What happened"
	log_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_row.add_child(log_title)
	_war_filter.focus_mode = Control.FOCUS_NONE
	for f in FILTERS:
		_war_filter.add_item(f)
	_war_filter.item_selected.connect(func(_i: int) -> void:
		_war_log_key = ""
		_refresh_wars()
	)
	log_row.add_child(_war_filter)
	_wars_box.add_child(log_row)
	_war_log.custom_minimum_size = Vector2(0, 230)
	_war_log.focus_mode = Control.FOCUS_NONE
	_war_log.max_text_lines = 4
	_war_log.fixed_column_width = 300
	_war_log.item_activated.connect(func(i: int) -> void:
		var entry: Dictionary = _war_log.get_item_metadata(i)
		if entry.battle > 0:
			_open_battle(entry.battle)
		elif entry.province > 0:
			get_tree().call_group("camera_focus", "focus_on", MapData.provinces[entry.province].center)
	)
	_wars_box.add_child(_war_log)
	var hint := Label.new()
	hint.text = "Double-click a battle to open its full account, or any other entry to see where it happened."
	hint.modulate = Color(1, 1, 1, 0.65)
	_wars_box.add_child(hint)
	_refresh_wars()


func _war_title(w: War) -> String:
	var status := "%d days" % w.days_lasted(Clock.days_elapsed)
	status = "ongoing, " + status if w.active() else "ended %s, lasted %s" % [w.end_date, status]
	return "%s vs %s · %s" % [GameState.nations[w.a].display_name, GameState.nations[w.b].display_name, status]


func _refresh_wars() -> void:
	var ordered: Array[War] = []
	var others: Array[War] = []
	for w in GameState.all_wars():
		if w.involves(GameState.player_tag):
			ordered.append(w)
		else:
			others.append(w)
	ordered.append_array(others)
	var ids: Array[int] = []
	for w in ordered:
		ids.append(w.id)
	var rebuild := ids != _wars_listed
	if rebuild:
		_wars_list.clear()
		_wars_listed = ids
	if not ids.has(_war_selected):
		_war_selected = ids[0] if not ids.is_empty() else 0
		_war_log_key = ""
	var chosen: War = null
	for i in ordered.size():
		var w := ordered[i]
		if rebuild:
			_wars_list.add_item(_war_title(w))
		else:
			_wars_list.set_item_text(i, _war_title(w))
		_wars_list.set_item_custom_fg_color(i, (Fmt.BAD if w.involves(GameState.player_tag) else Fmt.WARN) if w.active() else Fmt.DIM)
		if w.id == _war_selected:
			_wars_list.select(i)
			chosen = w
	_show_war(chosen)


func _show_war(w: War) -> void:
	_war_table.visible = w != null
	_peace_button.visible = w != null and w.active() and w.involves(GameState.player_tag)
	_war_log.visible = w != null
	_war_battles.visible = w != null
	if w == null:
		_war_battles.clear()
		_war_battle_ids.clear()
		_war_battles_key = ""
		_war_summary.text = "No wars yet. Declare one from the Diplomacy panel (F)."
		_war_log.clear()
		return
	var name_a: String = GameState.nations[w.a].display_name
	var name_b: String = GameState.nations[w.b].display_name
	var drew := w.battle_count(w.a, "draw")
	_war_summary.text = "%s attacked %s on %s.
%s
%d %s fought: %s won %d, %s won %d, %d without a clear result." % [
			name_a, name_b, w.start_date,
			"Still being fought (%d days)." % w.days_lasted(Clock.days_elapsed) if w.active() else "Ended %s after %d days." % [w.end_date, w.days_lasted(Clock.days_elapsed)],
			w.battles.size(), "battle" if w.battles.size() == 1 else "battles", name_a, w.battle_count(w.a, "won"), name_b, w.battle_count(w.b, "won"), drew]
	if w.active():
		var parts := Peace.score_parts(GameState, w, w.a)
		_war_summary.text += "\nWar score: %s %+.1f (ground %+.1f, capital %+.1f, battles %+.1f)." % [name_a, parts.total, parts.occupation, parts.capital, parts.battles]
	elif not w.peace.is_empty():
		_war_summary.text += "\nPeace: %s." % (("%s took %s" % [GameState.nations[w.peace.taker].display_name, "; ".join(w.peace.terms)]) if not w.peace.white else "white peace")
	if w.casus_belli != "" and Diplomacy.cfg.war.casus_belli.has(w.casus_belli):
		_war_summary.text += "\nCasus belli: %s." % Diplomacy.cfg.war.casus_belli[w.casus_belli].label.to_lower()
	_war_cells[0][0].text = ""
	_war_cells[0][1].text = name_a
	_war_cells[0][2].text = name_b
	for c in [1, 2]:
		_war_cells[0][c].modulate = GameState.nations[w.a if c == 1 else w.b].color.lightened(0.35)
	for r in WAR_ROWS.size():
		_war_cells[r + 1][0].text = WAR_ROWS[r]
		for c in [1, 2]:
			_war_cells[r + 1][c].text = _war_value(w, r, w.a if c == 1 else w.b)
	_refresh_war_battles(w)
	_refresh_war_log(w)


func _open_battle(id: int) -> void:
	get_tree().call_group("battle_screen", "open_battle", id)


## The war's battles: those in progress first, then finished ones, newest first.
func _refresh_war_battles(w: War) -> void:
	var ids: Array[int] = []
	var texts: PackedStringArray = []
	for battle: Dictionary in GameState.engagements.values():
		if battle.sides.has(w.a) and battle.sides.has(w.b):
			ids.append(battle.id)
			texts.append("● %s · day %d · in progress" % [battle.name, Clock.days_elapsed - battle.start_day + 1])
	for i in range(w.battles.size() - 1, -1, -1):
		var rec: Dictionary = w.battles[i]
		ids.append(rec.get("id", 0))
		texts.append("%s · %s · %d day%s · %s" % [rec.name, rec.date, rec.days, "" if rec.days == 1 else "s",
				"%s won" % GameState.nations[rec.winner].display_name if not rec.winner.is_empty() else "no clear winner"])
	var key := "%d|%s" % [w.id, "|".join(texts)]
	if key == _war_battles_key:
		return
	_war_battles_key = key
	var keep := -1
	var picked := _war_battles.get_selected_items()
	if not picked.is_empty() and picked[0] < _war_battle_ids.size():
		keep = _war_battle_ids[picked[0]]
	_war_battles.clear()
	_war_battle_ids = ids
	for i in ids.size():
		_war_battles.add_item(texts[i])
		if texts[i].begins_with("●"):
			_war_battles.set_item_custom_fg_color(i, Fmt.WARN)
		if ids[i] == keep and keep > 0:
			_war_battles.select(i)


func _war_value(w: War, row: int, tag: String) -> String:
	match row:
		0:
			return str(w.battle_count(tag, "won"))
		1:
			return str(w.battle_count(tag, "lost"))
		2:
			return Fmt.people(w.losses[tag])
		3:
			return Fmt.people(w.attrition[tag])
		4:
			return Fmt.people(w.surrendered[tag])
		5:
			return str(w.captured[tag].provinces)
		6:
			return Fmt.people(w.captured[tag].population)
		7:
			if not w.active():
				return "—"
			var held := 0
			for id in range(1, GameState.province_owner.size()):
				if GameState.province_owner[id] == w.other(tag) and GameState.province_controller[id] == tag:
					held += 1
			return str(held)
	return ""


func _refresh_war_log(w: War) -> void:
	var key := "%d:%d:%d" % [w.id, w.log.size(), _war_filter.selected]
	if key == _war_log_key:
		return
	_war_log_key = key
	_war_log.clear()
	for i in range(w.log.size() - 1, -1, -1):
		var entry: Dictionary = w.log[i]
		var kind: String = entry.kind
		if _war_filter.selected == 1 and kind != "battle":
			continue
		if _war_filter.selected == 2 and not kind in ["capture", "surrender", "collapse"]:
			continue
		_war_log.add_item("%s: %s" % [entry.date, entry.text])
		var idx := _war_log.item_count - 1
		_war_log.set_item_metadata(idx, entry)
		_war_log.set_item_custom_fg_color(idx, Fmt.DIM if kind in ["war", "peace"] else (Color.WHITE if kind == "battle" else Fmt.WARN))


# ------------------------------------------------------------------ recruiting and war

func _refresh_recruit() -> void:
	var type: String = _type_picker.get_item_metadata(_type_picker.selected)
	var def: Dictionary = Military.cfg.unit_types[type]
	var count := int(_count.value)
	var problem := RaiseUnits.problem(GameState, GameState.player_tag, _province, type, count) if _province > 0 else "Select a province first."
	_raise.disabled = not problem.is_empty()
	var cost := "£%.1fM, %s recruits, %d days" % [def.cost * count, Fmt.people(def.size * count), def.train_days]
	_raise_label.text = cost if problem.is_empty() else "%s (%s)" % [problem, cost]
	_raise_label.modulate = Fmt.DIM


func _on_raise() -> void:
	var type: String = _type_picker.get_item_metadata(_type_picker.selected)
	GameState.issue(RaiseUnits.new(GameState.player_tag, _province, type, int(_count.value)))
	_refresh()


func _set_row(key: String, label: String, value: String) -> void:
	_rows[key][0].text = label
	_rows[key][1].text = value


func _k(n: float) -> String:
	return "%.0fk" % (n / 1000.0) if n < 1_000_000.0 else "%.2fM" % (n / 1_000_000.0)


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_M:
			toggle()
		elif (event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER) and _drawing and not _draft.is_empty():
			_finish_drawing()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE:
			if _drawing or _picking_nation:
				_end_drawing()
				get_viewport().set_input_as_handled()
			elif not _selected.is_empty():
				clear_selection()
				get_viewport().set_input_as_handled()
