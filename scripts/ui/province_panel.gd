extends PanelContainer
## The panel at the top left that says what the selected province (or sea zone) is: a header
## with the owner's flag, the figures in a two-column table, then what stands and who is there,
## in short sections. Nothing is shown until something is selected.

const WIDTH := 330.0

var _box := VBoxContainer.new()


func _ready() -> void:
	add_to_group("province_panel")
	position = Vector2(16, 56)
	custom_minimum_size = Vector2(WIDTH, 0)
	size = Vector2(WIDTH, 0)
	add_theme_stylebox_override("panel", UiTheme.map_panel())
	_box.add_theme_constant_override("separation", 4)
	add_child(_box)
	show_province(0)


## The text of every label in the panel, one line each, for tests and tooltips.
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
	for c in _box.get_children():
		_box.remove_child(c)
		c.queue_free()


func _title(text: String, tag := "") -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	if tag != "":
		var flag := FlagIcon.new(tag)
		flag.custom_minimum_size = Vector2(36, 24)
		row.add_child(flag)
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 18)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	_box.add_child(row)


func _note(text: String, color := Fmt.DIM) -> void:
	var label := Label.new()
	label.text = text
	label.modulate = color
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_box.add_child(label)


func _section(text: String) -> void:
	_box.add_child(HSeparator.new())
	var label := Label.new()
	label.text = text.to_upper()
	label.add_theme_font_size_override("font_size", 11)
	label.modulate = Fmt.DIM
	_box.add_child(label)


## A table of [name, value] pairs.
func _table(rows: Array) -> void:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 1)
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
	_box.add_child(grid)


## The panel keeps the height it had, so after a rebuild it is shrunk or grown to fit once the
## new rows are in (clearing it first left it at the height of its margins).
func _fit() -> void:
	reset_size.call_deferred()


func show_zone(zone: int) -> void:
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
	_note("Sea zone")
	_section("Waters")
	_table([
		["Borders", ", ".join(next)],
		["Ports", "%d open on it" % MapData.ports_in_zone(zone).size()],
	])
	_fit()


func show_province(id: int) -> void:
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

	_section("Economy")
	var used := Economy.slots_used(GameState, id)
	var slots := Economy.slots_of(GameState, id)
	_table([
		["Population", Fmt.thousands(population)],
		["Area", "~%s km²" % Fmt.thousands(int(p.area * MapData.KM2_PER_PX))],
		["Output", "£%.1fM a month" % Fmt.monthly(GameState.province_gdp[id])],
		["Feeds", Fmt.people(GameState.province_food[id])],
		["Recruits", Fmt.people(GameState.province_pool[id])],
		["Building slots", "%d of %d used" % [used, slots], Fmt.WARN if used >= slots else Color.WHITE],
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
	_fit()
