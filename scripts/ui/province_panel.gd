extends PanelContainer
## The small card at the top left that says what the selected province (or sea zone) is: the
## owner's flag and the name, a line for who and what, and the three figures that matter at a
## glance. The rest (economy, deposits, what stands, who is there) is behind a Details button, so
## the card stays out of the way until you ask. Nothing is shown until something is selected.

const WIDTH := 236.0

var _box := VBoxContainer.new()
## The rows under the Details button; shown only while it is on.
var _detail := VBoxContainer.new()
var _toggle := Button.new()
var _last_province := 0
var _last_zone := 0


func _ready() -> void:
	add_to_group("province_panel")
	position = Vector2(12, 52)
	custom_minimum_size = Vector2(WIDTH, 0)
	size = Vector2(WIDTH, 0)
	theme = UiTheme.compact()
	var style := UiTheme.frame()
	style.bg_color = Color(UiTheme.SLATE_DEEP, 0.9)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 5
	style.content_margin_bottom = 6
	add_theme_stylebox_override("panel", style)
	_box.add_theme_constant_override("separation", 2)
	add_child(_box)
	_detail.add_theme_constant_override("separation", 2)
	_toggle.focus_mode = Control.FOCUS_NONE
	_toggle.flat = false
	_toggle.pressed.connect(func() -> void:
		UiSettings.set_province_details(not UiSettings.province_details)
		_rebuild())
	show_province(0)


## Builds the card again for what it last showed (after the Details button).
func _rebuild() -> void:
	if _last_zone > 0:
		show_zone(_last_zone)
	else:
		show_province(_last_province)


## The text of every label in the panel, one line each, for tests and tooltips. The rows under
## Details count even while they are folded away.
func plain_text() -> String:
	var lines: PackedStringArray = []
	_collect(_box, lines)
	return "\n".join(lines)


func _collect(node: Node, lines: PackedStringArray) -> void:
	if node is Label:
		lines.append(node.text)
	for c in node.get_children():
		_collect(c, lines)


func _clear() -> void:
	# The detail box is kept and emptied, so it can be put back under the card.
	if _detail.get_parent() == _box:
		_box.remove_child(_detail)
	for c in _box.get_children():
		_box.remove_child(c)
		c.queue_free()
	for c in _detail.get_children():
		_detail.remove_child(c)
		c.queue_free()


## The first line: the flag, the name and the Details button.
func _title(text: String, tag := "") -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	if tag != "":
		var flag := FlagIcon.new(tag)
		flag.custom_minimum_size = Vector2(26, 17)
		row.add_child(flag)
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 15)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.clip_text = true
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	_toggle.text = "Less" if UiSettings.province_details else "More"
	_toggle.tooltip_text = "Show or fold away the rest of what is known about this place."
	if _toggle.get_parent() != null:
		_toggle.get_parent().remove_child(_toggle)
	row.add_child(_toggle)
	_box.add_child(row)


func _note(text: String, color := Fmt.DIM, into: Control = null) -> void:
	var label := Label.new()
	label.text = text
	label.modulate = color
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	(into if into != null else _box).add_child(label)


func _section(text: String) -> void:
	_detail.add_child(HSeparator.new())
	var label := Label.new()
	label.text = text.to_upper()
	label.add_theme_font_size_override("font_size", 10)
	label.modulate = Fmt.DIM
	_detail.add_child(label)


## A table of [name, value] pairs, in the card or (by default) under Details.
func _table(rows: Array, into: Control = null) -> void:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 0)
	for r: Array in rows:
		var name := Label.new()
		name.text = r[0]
		name.modulate = Fmt.DIM
		grid.add_child(name)
		var value := Label.new()
		value.text = r[1]
		value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if r.size() > 2:
			value.modulate = r[2]
		grid.add_child(value)
	(into if into != null else _detail).add_child(grid)


## Puts the folded rows under the card: in the tree only while Details is on (their labels stay
## in the card either way, for plain_text).
func _finish() -> void:
	_box.add_child(_detail)
	_detail.visible = UiSettings.province_details
	_fit()


## The panel keeps the height it had, so after a rebuild it is shrunk or grown to fit once the
## new rows are in (clearing it first left it at the height of its margins).
func _fit() -> void:
	reset_size.call_deferred()


func show_zone(zone: int) -> void:
	_last_zone = zone
	_clear()
	if zone <= 0:
		visible = false
		return
	visible = true
	var z: Dictionary = MapData.sea_zones[zone]
	var next: PackedStringArray = []
	for n in MapData.sea_adjacency[zone]:
		next.append(MapData.sea_zones[n].name)
	_title(z.name)
	_table([["Sea zone", "%d ports open on it" % MapData.ports_in_zone(zone).size()]], _box)
	_section("Waters")
	_table([["Borders", ", ".join(next)]])
	_finish()


func show_province(id: int) -> void:
	_last_province = id
	_last_zone = 0
	_clear()
	var p := MapData.get_province(id)
	if p.is_empty():
		visible = false
		return
	visible = true
	var owner_tag: String = GameState.province_owner[id]
	var owner_nation: Nation = GameState.nations[owner_tag]
	var population: int = GameState.province_population[id]
	var terrain: String = Military.terrain_of(id).name
	_title(p.name, owner_tag)
	var kind := terrain + (", coast" if p.coastal else "")
	_note("%s  ·  %s" % [owner_nation.display_name, kind])
	if GameState.province_controller[id] != owner_tag:
		_note("Occupied by %s" % GameState.nations[GameState.province_controller[id]].display_name, Fmt.BAD)

	var used := Economy.slots_used(GameState, id)
	var slots := Economy.slots_of(GameState, id)
	# What matters at a glance stays on the card.
	_table([
		["People", Fmt.thousands(population)],
		["Output", "£%.1fM a month" % Fmt.monthly(GameState.province_gdp[id])],
		["Slots", "%d of %d used" % [used, slots], Fmt.WARN if used >= slots else Color.WHITE],
	], _box)
	# The rest is under Details.
	_section("Economy")
	_table([
		["Area", "~%s km²" % Fmt.thousands(int(p.area * MapData.KM2_PER_PX))],
		["Feeds", Fmt.people(GameState.province_food[id])],
		["Recruits", Fmt.people(GameState.province_pool[id])],
		["Infrastructure", "%.1f" % Economy.infrastructure(GameState, id)],
	])

	var made := Economy.province_output(population, p.area * MapData.KM2_PER_PX, owner_nation,
			GameState.province_buildings[id], GameState.province_deposit[id], GameState.province_civ_base[id])
	var deposits: Array = []
	for r in Economy.resource_ids():
		if GameState.province_deposit[id].get(r, 0.0) >= Economy.cfg.min_deposit:
			deposits.append([Economy.cfg.resources[r].name, "%s a month" % Fmt.kt(Fmt.monthly(made[r]))])
	if not deposits.is_empty():
		_section("Deposits")
		_table(deposits)

	var built: Array = []
	for type in Economy.building_ids():
		if GameState.province_buildings[id].has(type):
			built.append([Economy.cfg.buildings[type].name, "level %d" % GameState.province_buildings[id][type]])
	var yard := Navy.port_level(GameState, id)
	if yard > 0 and not MapData.zones_of_port(id).is_empty():
		var zones: PackedStringArray = []
		for z in MapData.zones_of_port(id):
			zones.append(MapData.sea_zones[z].name)
		built.append(["Port", "level %d on the %s" % [yard, " and ".join(zones)]])
	if not built.is_empty():
		_section("Built")
		_table(built)

	var here := Military.armies_at(GameState, id).filter(func(a: Army) -> bool: return Intel.level(GameState, a) != Intel.HIDDEN)
	var docked := Navy.fleets_in_port(GameState, id)
	if not here.is_empty() or not docked.is_empty():
		_section("Forces")
		var rows: Array = []
		var guessed := {}
		for a in here:
			match Intel.level(GameState, a):
				Intel.EXACT:
					rows.append(["%s army" % a.tag, "%s (%s)" % [a.display_name, Fmt.people(a.men())]])
				Intel.ESTIMATE:
					guessed[a.tag] = guessed.get(a.tag, 0.0) + Intel.estimate(a.men(), a.id)
		var tags: Array = guessed.keys()
		tags.sort()
		for tag: String in tags:
			rows.append(["%s forces" % tag, "%s men (estimate)" % Intel.estimate_text(guessed[tag])])
		for fl in docked:
			rows.append(["%s fleet" % fl.tag, "%s (%d squadrons)" % [fl.display_name, fl.ships.size()]])
		_table(rows)
	_finish()
