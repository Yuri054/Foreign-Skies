extends FloatingWindow
## Construction (B, or the Construction button on the top bar): a panel on the left with the
## kinds of building. Picking one switches the map to Construction mode for it: green provinces
## are where you can build it, blue where it stands and no more can, teal where it stands and
## more can follow, grey where it cannot be built (hover for why), dark where the land is not
## yours. A click on a green province queues the building at once (it is paid for then); with
## Ctrl a click on a province retools one of its other factories into the factory picked.
## Mass building (many provinces at once, best first) is folded away at the bottom. Closing the
## panel puts the map back as it was.

const MapView := preload("res://scripts/map/map_view.gd")

var map_view: Sprite2D
## The kind of building picked ("" before the first pick).
var _type := ""
var _rows: Dictionary = {}
var _detail := Label.new()
var _status := Label.new()
var _hint := Label.new()
var _list := VBoxContainer.new()
var _pool := Label.new()
var _queue := VBoxContainer.new()
var _mass_toggle := Button.new()
var _mass_box := VBoxContainer.new()
var _mass_count := SpinBox.new()
var _mass_spend := SpinBox.new()
var _mass_preview := Label.new()
var _mass_button := Button.new()
var _group := ButtonGroup.new()


func _ready() -> void:
	add_to_group("construction_panel")
	visible = false
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	add_child(box)

	_list.add_theme_constant_override("separation", 3)
	box.add_child(_list)
	for type in Economy.building_ids():
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = _group
		b.focus_mode = Control.FOCUS_NONE
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(func() -> void: select_type(type))
		_list.add_child(b)
		_rows[type] = b

	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size = Vector2(330, 0)
	_hint.modulate = Fmt.DIM
	box.add_child(_hint)
	box.add_child(HSeparator.new())
	_pool.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_pool.custom_minimum_size = Vector2(330, 0)
	box.add_child(_pool)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 90)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_queue.add_theme_constant_override("separation", 2)
	_queue.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_queue)
	box.add_child(scroll)
	box.add_child(HSeparator.new())
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.custom_minimum_size = Vector2(330, 0)
	box.add_child(_detail)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(330, 0)
	box.add_child(_status)
	box.add_child(HSeparator.new())

	_mass_toggle.toggle_mode = true
	_mass_toggle.focus_mode = Control.FOCUS_NONE
	_mass_toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_mass_toggle.toggled.connect(func(on: bool) -> void:
		_mass_box.visible = on
		_refresh()
	)
	box.add_child(_mass_toggle)
	_mass_box.visible = false
	_mass_box.add_theme_constant_override("separation", 4)
	box.add_child(_mass_box)
	_mass_box.add_child(_mass_row("Up to provinces", _mass_count, 1.0, 999.0, 10.0))
	_mass_box.add_child(_mass_row("Spend at most £M (0 = any)", _mass_spend, 0.0, 9999.0, 0.0))
	_mass_preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mass_preview.custom_minimum_size = Vector2(330, 0)
	_mass_box.add_child(_mass_preview)
	_mass_button.focus_mode = Control.FOCUS_NONE
	_mass_button.pressed.connect(func() -> void: GameState.issue(_mass_command()))
	_mass_box.add_child(_mass_button)

	setup_window("Construction", true, Vector2(370, 0), 0)
	fit_window(box.get_combined_minimum_size().y + 4.0)

	visibility_changed.connect(_on_visibility_changed)
	GameState.economy_updated.connect(_refresh)
	Clock.day_ticked.connect(_refresh_queue)
	GameState.player_changed.connect(func(_t: String) -> void: _refresh())
	_refresh()


## Called by the map scene once map_view is set.
func connect_map() -> void:
	map_view.province_selected.connect(_on_province_clicked)
	map_view.province_hovered.connect(_on_province_hovered)
	map_view.mode_changed.connect(func(_m: int, _s: String) -> void: _sync_rows())


func toggle() -> void:
	visible = not visible


func _on_visibility_changed() -> void:
	if visible:
		select_type(_type if _type != "" else Economy.building_ids()[0])
	elif map_view != null:
		map_view.pop_mode(MapView.Mode.CONSTRUCTION)
	_refresh()


## Picks a kind of building and shows where it can be built.
func select_type(type: String) -> void:
	if not Economy.cfg.buildings.has(type):
		return
	_type = type
	if map_view != null:
		map_view.push_mode(MapView.Mode.CONSTRUCTION)
		map_view.set_mode(MapView.Mode.CONSTRUCTION, type)
	_sync_rows()
	_refresh()


## The kind picked, or "" if the map is showing something else.
func picked() -> String:
	return _type if map_view != null and map_view.mode == MapView.Mode.CONSTRUCTION else ""


func _sync_rows() -> void:
	var showing := picked()
	for type in _rows:
		_rows[type].set_pressed_no_signal(type == showing)
	_refresh()


# --- Acting on the map ----------------------------------------------------------------------

func _on_province_clicked(id: int) -> void:
	if visible and picked() != "":
		act_on(id, Input.is_key_pressed(KEY_CTRL))


## A click on a province with a building picked: queue it, or with `retool` turn one of its
## other factories into this kind. Returns whether it was done, and says why not.
func act_on(id: int, retool := false) -> bool:
	var type := picked()
	var tag: String = GameState.player_tag
	if type == "" or id < 1:
		return false
	if retool:
		if not Economy.cfg.buildings[type].get("slot", false):
			_say("Only factories can be retooled.", Fmt.WARN)
			return false
		var cmd := ConvertFactory.new(tag, id, type)
		if GameState.issue(cmd):
			_say("Retooling a factory in %s: %s IC, %d days." % [MapData.provinces[id].name, Fmt.thousands(int(ConvertFactory.cost_of(type))), Economy.cfg.factories.convert_days], Fmt.GOOD)
			return true
		_say(cmd.reason, Fmt.WARN)
		return false
	var problem := Economy.build_problem(GameState, tag, id, type)
	if not problem.is_empty():
		_say("%s: %s" % [MapData.provinces[id].name, problem], Fmt.WARN)
		return false
	var plan := Economy.build_plan(GameState, id, type)
	if GameState.issue(ConstructBuilding.new(tag, id, type)):
		_say("%s in %s: %s IC, at least %d days." % [Economy.cfg.buildings[type].name, MapData.provinces[id].name, Fmt.thousands(int(plan.ic)), plan.days], Fmt.GOOD)
		return true
	return false


func _on_province_hovered(id: int) -> void:
	if not visible or picked() == "" or id < 1:
		return
	_say(status_of(id), Fmt.DIM)


## What a province shows for the building picked: whether and what it would cost, or why not.
func status_of(id: int) -> String:
	var type := picked()
	var tag: String = GameState.player_tag
	var pname: String = MapData.provinces[id].name
	if type == "" or GameState.province_owner[id] != tag:
		return "%s: not your land." % pname
	var here: int = GameState.province_buildings[id].get(type, 0)
	var held := "%d here" % here if here > 0 else "none here"
	var problem := Economy.build_problem(GameState, tag, id, type)
	if problem.is_empty():
		var plan := Economy.build_plan(GameState, id, type)
		return "%s (%s): click to build for %s IC, at least %d days." % [pname, held, Fmt.thousands(int(plan.ic)), plan.days]
	return "%s (%s): %s." % [pname, held, problem]


func _say(text: String, color: Color) -> void:
	_status.text = text
	_status.modulate = color


# --- Content ---------------------------------------------------------------------------------

func _refresh() -> void:
	var n := GameState.get_player()
	if n == null or not visible:
		return
	for type in _rows:
		var built := 0
		var can := 0
		for id in n.provinces:
			built += GameState.province_buildings[id].get(type, 0)
			if Economy.build_problem(GameState, n.tag, id, type, false).is_empty():
				can += 1
		_rows[type].text = "%s: %d built, %d provinces can build" % [Economy.cfg.buildings[type].name, built, can]
	var type := picked()
	if type == "":
		_hint.text = "Pick a building to see on the map where it stands and where it can be built."
		_detail.text = ""
	else:
		_hint.text = "Click a green province to build. Ctrl+click retools a factory there." if Economy.cfg.buildings[type].get("slot", false) \
				else "Click a green province to build."
		_detail.text = _detail_text(type)
	_mass_toggle.text = ("v " if _mass_toggle.button_pressed else "> ") + "Mass build"
	if _mass_toggle.button_pressed:
		_refresh_mass()
	_refresh_queue()


## The day's construction points and the projects they are going to, first served first.
func _refresh_queue() -> void:
	var n := GameState.get_player()
	if n == null or not visible:
		return
	var points: float = n.budget.get("construction_points", 0.0)
	_pool.text = "Construction: %.0f points a day from %d civilian factories, %.0f in use." % [points, int(n.budget.get("factories", 0)), n.construction_used]
	for c in _queue.get_children():
		_queue.remove_child(c)
		c.queue_free()
	if n.construction.is_empty():
		var none := Label.new()
		none.text = "Nothing is being built."
		none.modulate = Fmt.DIM
		_queue.add_child(none)
		return
	for i in n.construction.size():
		_queue.add_child(_queue_row(n, n.construction[i], i))


func _queue_row(n: Nation, job: Dictionary, index: int) -> Control:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.clip_text = true
	var percent := roundi(100.0 * (1.0 - job.points_left / maxf(job.points_total, 1.0)))
	var eta := "waiting" if job.days_left >= 9999 else "%dd" % job.days_left
	label.text = "%s, %s  %d%%  %s" % [Economy.cfg.buildings[job.type].name, MapData.provinces[job.province].name, percent, eta]
	if job.days_left >= 9999:
		label.modulate = Fmt.WARN
	row.add_child(label)
	var first := Button.new()
	first.text = "^"
	first.tooltip_text = "Serve this one first"
	first.focus_mode = Control.FOCUS_NONE
	first.disabled = index == 0
	var province: int = job.province
	var type: String = job.type
	first.pressed.connect(func() -> void: GameState.issue(PrioritizeConstruction.new(n.tag, province, type)))
	row.add_child(first)
	return row


func _detail_text(type: String) -> String:
	var def: Dictionary = Economy.cfg.buildings[type]
	var lines: PackedStringArray = []
	if def.get("slot", false):
		lines.append("Takes one building slot. %s IC each, at least %d days, at most %d in a province." % [Fmt.thousands(int(def.ic)), def.min_days, def.get("max_per_province", 99)])
		lines.append("A province's slots come from its people and its infrastructure: each point of it, a railway level or half of a neighbour's, adds a slot. The numbers on the map are slots used out of slots.")
		if type == "factory":
			var me := GameState.get_player()
			lines.append("Gives construction points (one a day, less consumer goods) and pays about £%.1fM a year into the treasury, and adds about £%.0fM of industrial output to the economy." % [Economy.factory_income(me), Economy.factory_output(me)])
		else:
			lines.append("Makes equipment instead of income. Retooling a civilian factory costs its output.")
	else:
		lines.append("Level 1 costs %s IC%s. At least %d days a level, at most %d levels." % [Fmt.thousands(int(def.ic)), ", each further level more" if def.get("ic_growth", 0.0) > 0.0 else "", def.min_days, def.max_level])
		var effects := _effects_text(def.effects)
		if effects != "":
			lines.append("Per level: " + effects)
		if type == "railway":
			lines.append("Raises infrastructure: a building slot more for each level here and for half a level in the neighbouring provinces you own. The numbers on the map are levels out of the most.")
	if not def.get("materials", {}).is_empty():
		lines.append("Needs: " + _amounts_text(def.materials))
	if def.get("requires", "") == "coastal":
		lines.append("Coastal provinces only.")
	return "\n".join(lines)


func _amounts_text(amounts: Dictionary) -> String:
	var parts: PackedStringArray = []
	for r in amounts:
		parts.append("%s %s" % [Fmt.kt(amounts[r]), Economy.cfg.resources[r].name.to_lower()])
	return ", ".join(parts)


func _effects_text(effects: Dictionary) -> String:
	var names := {"gdp": "output", "industry": "industry", "food": "food", "trade": "trade income", "growth": "growth/yr"}
	var parts: PackedStringArray = []
	for k in effects:
		parts.append("+%d%% %s" % [roundi(effects[k] * 100.0), names.get(k, k)])
	return ", ".join(parts)


# --- Mass building ---------------------------------------------------------------------------

func _mass_row(label: String, spin: SpinBox, lo: float, hi: float, value: float) -> Control:
	var row := HBoxContainer.new()
	var name_label := Label.new()
	name_label.text = label
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin.min_value = lo
	spin.max_value = hi
	spin.step = 1.0
	spin.value = value
	spin.value_changed.connect(func(_v: float) -> void: _refresh_mass())
	row.add_child(name_label)
	row.add_child(spin)
	return row


func _mass_command() -> MassConstructBuilding:
	return MassConstructBuilding.new(GameState.player_tag, _type, int(_mass_count.value), _mass_spend.value)


## Updates the preview and the button for the building picked and the limits set.
func _refresh_mass() -> void:
	if _type == "" or GameState.get_player() == null:
		_mass_preview.text = "Pick a building first."
		_mass_button.disabled = true
		return
	var preview := _mass_command().preview(GameState)
	var limits := {"all": "every eligible province", "count": "your province limit",
			"spend": "your spending limit", "money": "your treasury"}
	if preview.count == 0:
		_mass_preview.text = "No eligible province for this building." if preview.stopped_by == "all" \
				else "Nothing can be built: the first one costs more than %s allows." % limits[preview.stopped_by]
		_mass_button.text = "Build"
		_mass_button.disabled = true
	else:
		_mass_preview.text = "%d buildings for £%.1fM, materials included, best provinces first. Limited by %s." % [preview.count, preview.spent, limits[preview.stopped_by]]
		_mass_button.text = "Build %d for £%.1fM" % [preview.count, preview.spent]
		_mass_button.disabled = false


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_B \
			and not event.ctrl_pressed and not event.alt_pressed:
		toggle()
