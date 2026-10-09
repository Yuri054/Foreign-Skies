extends FloatingWindow
## Economy of the player's nation in three tabs, all figures per month:
##   Overview:  problems, tax rate, income and spending, national programs.
##   Resources: food, coal, iron and timber: made, used, balance, stockpile.
##   Buildings: every building type with what you have, what it earns, and a Build button for
##              the province selected on the map; mass building is folded away at the bottom.
## Toggle with E. Hover over a label for the detail behind it.

var _tabs := TabContainer.new()
var _alerts := VBoxContainer.new()
var _tax_slider := HSlider.new()
var _tax_label := Label.new()
var _budget := HBoxContainer.new()
var _output := Label.new()
var _program_boxes: Dictionary = {}
var _resources := VBoxContainer.new()
var _buildings := VBoxContainer.new()
var _province := 0

var _mass_toggle := Button.new()
var _mass_box := VBoxContainer.new()
var _mass_type := OptionButton.new()
var _mass_count := SpinBox.new()
var _mass_spend := SpinBox.new()
var _mass_preview := Label.new()
var _mass_button := Button.new()


func _ready() -> void:
	add_to_group("economy_panel")
	visible = false
	_tabs.focus_mode = Control.FOCUS_NONE
	add_child(_tabs)
	_tabs.add_child(_scroll(_build_overview(), "Overview"))
	_tabs.add_child(_scroll(_resources, "Resources"))
	_tabs.add_child(_scroll(_build_buildings(), "Buildings"))
	_tabs.tab_changed.connect(func(_i: int) -> void:
		_refresh()
		_fit_tab.call_deferred()
	)
	setup_window("Economy", true, Vector2(520, 0), 0)
	_fit_tab()

	GameState.economy_updated.connect(_refresh)
	GameState.player_changed.connect(func(_t: String) -> void: _refresh())
	_refresh()


func toggle() -> void:
	visible = not visible
	if visible:
		_refresh()
		_fit_tab.call_deferred()


## Sizes the window to the tab showing, unless the player has sized it.
func _fit_tab() -> void:
	var tab := _tabs.get_current_tab_control()
	if tab != null and tab.get_child_count() > 0:
		fit_window(minf(tab.get_child(0).get_combined_minimum_size().y + 34.0, 520.0))


## Called by the map when the selected province changes (0 = none).
func set_province(id: int) -> void:
	_province = id
	_refresh()


# ---------------------------------------------------------------- construction

func _scroll(content: Control, tab_name: String) -> ScrollContainer:
	var sc := ScrollContainer.new()
	sc.name = tab_name
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.custom_minimum_size = Vector2(340, 140)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(content)
	return sc


func _build_overview() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)

	_alerts.add_theme_constant_override("separation", 1)
	box.add_child(_alerts)

	var tax_row := HBoxContainer.new()
	var tax_name := Label.new()
	tax_name.text = "Tax rate"
	tax_name.custom_minimum_size = Vector2(80, 0)
	_tax_slider.min_value = Economy.cfg.min_tax_rate
	_tax_slider.max_value = Economy.cfg.max_tax_rate
	_tax_slider.step = 0.01
	_tax_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tax_slider.focus_mode = Control.FOCUS_NONE
	_tax_slider.tooltip_text = "Share of output taken as tax. Above %d%% it starts to choke the economy." % roundi(Economy.cfg.default_tax_rate * 100.0)
	_tax_slider.value_changed.connect(func(v: float) -> void:
		GameState.issue(SetEconomyPolicy.new(GameState.player_tag, "tax_rate", v))
	)
	_tax_label.custom_minimum_size = Vector2(44, 0)
	_tax_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	for c in [tax_name, _tax_slider, _tax_label]:
		tax_row.add_child(c)
	box.add_child(tax_row)

	_budget.add_theme_constant_override("separation", 14)
	box.add_child(_budget)
	_output.modulate = Fmt.DIM
	box.add_child(_output)
	box.add_child(HSeparator.new())

	box.add_child(_heading("National programs"))
	var programs := GridContainer.new()
	programs.columns = 2
	programs.add_theme_constant_override("h_separation", 14)
	programs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(programs)
	for id in Economy.program_ids():
		var check := CheckBox.new()
		check.focus_mode = Control.FOCUS_NONE
		check.toggled.connect(func(on: bool) -> void:
			GameState.issue(SetProgram.new(GameState.player_tag, id, on))
		)
		check.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		programs.add_child(check)
		_program_boxes[id] = check
	return box


func _build_buildings() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_buildings.add_theme_constant_override("separation", 6)
	box.add_child(_buildings)
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
	box.add_child(_mass_box)
	_build_mass_controls()
	return box


func _build_mass_controls() -> void:
	_mass_box.add_theme_constant_override("separation", 4)
	_mass_box.add_child(_note("Builds one level in many provinces at once, best provinces first."))

	for id in Economy.building_ids():
		_mass_type.add_item(Economy.cfg.buildings[id].name)
	_mass_type.focus_mode = Control.FOCUS_NONE
	_mass_type.item_selected.connect(func(_i: int) -> void: _refresh_mass())
	_mass_box.add_child(_mass_type)

	_mass_box.add_child(_mass_row("Up to provinces", _mass_count, 1.0, 999.0, 10.0))
	_mass_box.add_child(_mass_row("Spend at most £M (0 = any)", _mass_spend, 0.0, 9999.0, 0.0))

	_mass_preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mass_preview.custom_minimum_size = Vector2(380, 0)
	_mass_box.add_child(_mass_preview)

	_mass_button.focus_mode = Control.FOCUS_NONE
	_mass_button.pressed.connect(func() -> void: GameState.issue(_mass_command()))
	_mass_box.add_child(_mass_button)


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


# ---------------------------------------------------------------- small widgets

func _heading(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Color(0.75, 0.82, 0.95))
	return l


func _clear(box: Control) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()


func _grid(columns: int) -> GridContainer:
	var g := GridContainer.new()
	g.columns = columns
	g.add_theme_constant_override("h_separation", 10)
	g.add_theme_constant_override("v_separation", 3)
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return g


## A grid cell. The first column stretches; the others are right-aligned.
func _cell(g: GridContainer, text: String, column := -1, color := Color.WHITE, tip := "") -> Label:
	var l := Label.new()
	l.text = text
	l.modulate = color
	if tip != "":
		l.tooltip_text = tip
		l.mouse_filter = Control.MOUSE_FILTER_PASS
	if column == 0 or (column == -1 and g.get_child_count() % g.columns == 0):
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	g.add_child(l)
	return l


func _note(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.modulate = Fmt.DIM
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(300, 0)
	return l


# ---------------------------------------------------------------- refresh

func _refresh() -> void:
	var n := GameState.get_player()
	if n == null or n.budget.is_empty() or not visible:
		return
	_refresh_overview(n)
	match _tabs.current_tab:
		1:
			_refresh_resources(n)
		2:
			_refresh_buildings(n)


func _refresh_overview(n: Nation) -> void:
	var b := n.budget
	_tax_slider.set_value_no_signal(n.tax_rate)
	_tax_label.text = "%d%%" % roundi(n.tax_rate * 100.0)

	# Problems first, so they cannot be missed.
	_clear(_alerts)
	var problems: PackedStringArray = []
	if n.blockade > 0.0:
		problems.append("Blockaded: imports and exports are cut by %d%%." % roundi(n.blockade * 100.0))
	if n.treasury < 0.0:
		problems.append("The treasury is in debt.")
	elif b.net < 0.0:
		problems.append("Running a deficit of £%.1fM a month." % (-Fmt.monthly(b.net)))
	if b.food_shortage > 0.0:
		problems.append("Starvation: %d%% of food needs unmet." % roundi(b.food_shortage * 100.0))
	for r in Economy.resource_ids():
		if b.resources[r].shortage > 0.0:
			problems.append("%s shortage: %d%% of demand unmet, hurting industry." % [Economy.cfg.resources[r].name, roundi(b.resources[r].shortage * 100.0)])
	if problems.is_empty():
		_alerts.add_child(_status("No problems.", Fmt.GOOD))
	for p in problems:
		_alerts.add_child(_status(p, Fmt.BAD))

	# Income and spending, grouped; detail in the tooltips.
	_clear(_budget)
	var g := _grid(2)
	var spend := _grid(2)
	_budget.add_child(g)
	_budget.add_child(VSeparator.new())
	_budget.add_child(spend)
	var taxes: float = Fmt.monthly(b.revenue - b.trade - b.resource_exports)
	var trade: float = Fmt.monthly(b.trade + b.resource_exports)
	_head_row(g, "Income")
	_cell(g, "Taxes", 0, Color.WHITE, "Output of £%.1fM a month taxed at %d%%." % [Fmt.monthly(b.gdp), roundi(n.tax_rate * 100.0)])
	_cell(g, Fmt.money(taxes, true), 1)
	if trade > 0.04:
		_cell(g, "Trade", 0, Color.WHITE, "Ports and trading houses £%.1fM, resource exports £%.1fM." % [Fmt.monthly(b.trade), Fmt.monthly(b.resource_exports)])
		_cell(g, Fmt.money(trade, true), 1)
	_total_row(g, "Total income", Fmt.monthly(b.revenue), Color.WHITE)

	_head_row(spend, "Spending")
	_cell(spend, "Civil", 0, Color.WHITE, "Running the state: a fixed share of output.")
	_cell(spend, Fmt.money(-Fmt.monthly(b.civil), true), 1)
	_cell(spend, "Military", 0, Color.WHITE, "Army upkeep £%.1fM, navy £%.1fM." % [Fmt.monthly(b.army), Fmt.monthly(b.naval)])
	_cell(spend, Fmt.money(-Fmt.monthly(b.army + b.naval), true), 1)
	var imports: float = Fmt.monthly(b.food_imports + b.resource_imports)
	if imports > 0.04:
		_cell(spend, "Imports", 0, Color.WHITE, "Food £%.1fM, raw resources £%.1fM." % [Fmt.monthly(b.food_imports), Fmt.monthly(b.resource_imports)])
		_cell(spend, Fmt.money(-imports, true), 1)
	if b.programs > 0.0:
		_cell(spend, "Programs", 0)
		_cell(spend, Fmt.money(-Fmt.monthly(b.programs), true), 1)
	_total_row(spend, "Total spending", -Fmt.monthly(b.expenses), Color.WHITE)
	_total_row(g, "Net per month", Fmt.monthly(b.net), Fmt.GOOD if b.net >= 0.0 else Fmt.BAD)

	_output.text = "Output £%.0fM a month, industry £%.0fM." % [Fmt.monthly(b.gdp), Fmt.monthly(b.industry)]

	for id in _program_boxes:
		var def: Dictionary = Economy.cfg.programs[id]
		var check: CheckBox = _program_boxes[id]
		check.set_pressed_no_signal(n.programs.has(id))
		check.text = "%s  (%s a month)" % [def.name, Fmt.money(-def.cost_gdp_share * Fmt.monthly(b.gdp), true)]
		check.tooltip_text = "Effect: " + _effects_text(def.effects)


func _status(text: String, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.modulate = color
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(300, 0)
	return l


func _head_row(g: GridContainer, text: String) -> void:
	var l := _cell(g, text, 0)
	l.add_theme_color_override("font_color", Color(0.75, 0.82, 0.95))
	_cell(g, "", 1)


func _total_row(g: GridContainer, text: String, value: float, color: Color) -> void:
	var l := _cell(g, text, 0, color)
	l.add_theme_font_size_override("font_size", 15)
	var v := _cell(g, Fmt.money(value, true), 1, color)
	v.add_theme_font_size_override("font_size", 15)


func _refresh_resources(n: Nation) -> void:
	_clear(_resources)
	var b := n.budget
	var g := _grid(5)
	_resources.add_child(g)
	for h in ["Per month", "Made", "Used", "Balance", "Stock"]:
		_cell(g, h, -1, Fmt.DIM)

	# Food: counted in people fed rather than tonnes.
	var short: bool = b.food_shortage > 0.0
	_cell(g, "Food", 0, Color.WHITE, "People the land can feed, against the population. Shortfalls are imported unless blockaded.")
	_cell(g, Fmt.people(b.food_production), 1)
	_cell(g, Fmt.people(b.food_need), 1)
	var food_balance: float = b.food_production - b.food_need
	_cell(g, "SHORT" if short else (("+" if food_balance >= 0.0 else "-") + Fmt.people(absf(food_balance))), 1,
			Fmt.BAD if short else (Fmt.GOOD if food_balance >= 0.0 else Fmt.WARN))
	_cell(g, "", 1)

	for r in Economy.resource_ids():
		var def: Dictionary = Economy.cfg.resources[r]
		var info: Dictionary = b.resources[r]
		_cell(g, def.name, 0, Color(def.color).lerp(Color.WHITE, 0.5),
				"Mined at the base rate plus mine levels; used by industry, households and your buildings.")
		_cell(g, Fmt.kt(Fmt.monthly(info.production)), 1)
		_cell(g, Fmt.kt(Fmt.monthly(info.demand)), 1)
		var balance_text := Fmt.kt(Fmt.monthly(info.balance), true)
		var color := Fmt.GOOD if info.balance >= 0.0 else Fmt.WARN
		var tip := "Exported" if info.balance >= 0.0 else "Imported"
		if info.shortage > 0.0:
			balance_text = "SHORT"
			color = Fmt.BAD
			tip = "%d%% of demand cannot be met." % roundi(info.shortage * 100.0)
		_cell(g, balance_text, 1, color, tip)
		_cell(g, Fmt.kt(info.stock), 1, Color.WHITE, "Stockpile, of a possible %s. It buffers a blockade and supplies construction." % Fmt.kt(info.cap))

	_resources.add_child(_note("Green balances are exported, orange ones imported (the state takes %d%% of the trade value). A blockade stops both, the stockpile runs down, and shortages cut industry and output." % roundi(Economy.cfg.trade_state_share * 100.0)))


func _refresh_buildings(n: Nation) -> void:
	_clear(_buildings)
	var stats := Economy.building_stats(GameState, n.tag)
	var here := _province > 0 and GameState.province_owner[_province] == n.tag
	if here:
		_buildings.add_child(_heading("Building in " + MapData.provinces[_province].name))
	else:
		_buildings.add_child(_note("Select one of your provinces on the map to build there."))

	var g := _grid(5)
	_buildings.add_child(g)
	for h in ["Building", "Here", "All", "£/mo", ""]:
		_cell(g, h, -1, Fmt.DIM)
	var total_levels := 0
	var total_income := 0.0
	for type in Economy.building_ids():
		var def: Dictionary = Economy.cfg.buildings[type]
		var st: Dictionary = stats[type]
		total_levels += st.levels
		total_income += st.income
		_cell(g, def.name, 0, Color.WHITE, _building_tip(def))
		var level: int = GameState.province_buildings[_province].get(type, 0) if here else 0
		_cell(g, ("%d/%d" % [level, def.max_level]) if here else "", 1)
		_cell(g, str(st.levels) if st.levels > 0 else "-", 1, Color.WHITE if st.levels > 0 else Fmt.DIM, _stats_tip(st))
		_cell(g, Fmt.money(Fmt.monthly(st.income), true) if st.levels > 0 else "-", 1, Color.WHITE if st.levels > 0 else Fmt.DIM, _stats_tip(st))
		g.add_child(_build_button(n, type, def, here, level))

	var share := 100.0 * total_income / maxf(n.budget.revenue, 0.001)
	_buildings.add_child(_note("%d building levels earn £%.1fM a month (%d%% of your income). Hover over a name for what it does." % [total_levels, Fmt.monthly(total_income), roundi(share)]))

	_mass_toggle.text = ("v " if _mass_toggle.button_pressed else "> ") + "Mass build"
	if _mass_toggle.button_pressed:
		_refresh_mass()


func _build_button(n: Nation, type: String, def: Dictionary, here: bool, level: int) -> Button:
	var button := Button.new()
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(84, 0)
	if not here:
		button.text = "Build"
		button.disabled = true
		button.tooltip_text = "Select one of your provinces first."
		return button
	var problem := Economy.build_problem(GameState, n.tag, _province, type)
	var plan := Economy.build_plan(GameState, _province, type)
	if level >= def.max_level:
		button.text = "Max"
	elif problem.begins_with("No ") or problem.begins_with("Needs a"):
		button.text = "n/a"
	elif problem == "Already under construction":
		button.text = "Building"
	else:
		button.text = "£%.1fM" % plan.total
	button.disabled = not problem.is_empty()
	button.tooltip_text = problem if not problem.is_empty() else _plan_text(plan, def)
	var province := _province
	button.pressed.connect(func() -> void: GameState.issue(ConstructBuilding.new(n.tag, province, type)))
	return button


## What a building type does, for the tooltip on its name.
func _building_tip(def: Dictionary) -> String:
	var lines: PackedStringArray = ["Per level: " + _effects_text(def.effects)]
	if not def.get("materials", {}).is_empty():
		lines.append("Needs: " + _amounts_text(def.materials) + " (level 1)")
	if not def.get("consumes", {}).is_empty():
		lines.append("Uses per level: " + _amounts_text(def.consumes) + " a year")
	var requires: String = def.get("requires", "")
	if requires == "coastal":
		lines.append("Coastal provinces only.")
	elif requires.begins_with("deposit:"):
		lines.append("Needs a %s deposit." % Economy.cfg.resources[requires.trim_prefix("deposit:")].name.to_lower())
	lines.append("Takes %d days." % def.build_days)
	return "\n".join(lines)


## What your buildings of a type produce, for the tooltips on their totals.
func _stats_tip(st: Dictionary) -> String:
	if st.levels == 0:
		return "None built."
	var parts: PackedStringArray = ["%d levels in %d provinces" % [st.levels, st.provinces]]
	if st.gdp > 0.0005:
		parts.append("output +£%.1fM/mo" % Fmt.monthly(st.gdp))
	if st.industry > 0.0005:
		parts.append("industry +£%.1fM/mo" % Fmt.monthly(st.industry))
	if st.trade > 0.0005:
		parts.append("trade +£%.1fM/mo" % Fmt.monthly(st.trade))
	if st.food > 0.5:
		parts.append("feeds +%s people" % Fmt.people(st.food))
	for r in Economy.resource_ids():
		if st[r] > 0.5:
			parts.append("%s +%s/mo" % [Economy.cfg.resources[r].name.to_lower(), Fmt.kt(Fmt.monthly(st[r]))])
	for r in st.uses:
		parts.append("uses %s %s/mo" % [Fmt.kt(Fmt.monthly(st.uses[r])), Economy.cfg.resources[r].name.to_lower()])
	return "\n".join(parts)


func _amounts_text(amounts: Dictionary) -> String:
	var parts: PackedStringArray = []
	for r in amounts:
		parts.append("%s %s" % [Fmt.kt(amounts[r]), Economy.cfg.resources[r].name.to_lower()])
	return ", ".join(parts)


func _plan_text(plan: Dictionary, def: Dictionary) -> String:
	var lines: PackedStringArray = ["%d days. Gold £%.1fM." % [def.build_days, plan.gold]]
	for r in plan.materials:
		var res_name: String = Economy.cfg.resources[r].name.to_lower()
		var line := "%s %s: %s from stock" % [Fmt.kt(plan.materials[r]), res_name, Fmt.kt(plan.from_stock[r])]
		if plan.buy[r] > 0.0:
			line += ", %s bought" % Fmt.kt(plan.buy[r])
		lines.append(line)
	if plan.purchase > 0.0:
		lines.append("Imports cost £%.2fM extra." % plan.purchase)
	return "\n".join(lines)


func _effects_text(effects: Dictionary) -> String:
	var names := {"gdp": "output", "industry": "industry", "food": "food", "trade": "trade income", "growth": "growth/yr",
			"yield_coal": "coal output", "yield_iron": "iron output", "yield_wood": "timber output"}
	var parts: PackedStringArray = []
	for k in effects:
		parts.append("+%d%% %s" % [roundi(effects[k] * 100.0), names[k]])
	return ", ".join(parts)


# ---------------------------------------------------------------- mass build

func _mass_command() -> MassConstructBuilding:
	var type: String = Economy.building_ids()[_mass_type.selected]
	return MassConstructBuilding.new(GameState.player_tag, type, int(_mass_count.value), _mass_spend.value)


## Updates the eligible counts, the preview and the button for the current settings.
func _refresh_mass() -> void:
	var n := GameState.get_player()
	if n == null:
		return
	var ids := Economy.building_ids()
	for i in ids.size():
		_mass_type.set_item_text(i, "%s  (%d eligible)" % [Economy.cfg.buildings[ids[i]].name, Economy.mass_candidates(GameState, n.tag, ids[i]).size()])
	var preview := _mass_command().preview(GameState)
	var limits := {"all": "every eligible province", "count": "your province limit",
			"spend": "your spending limit", "money": "your treasury"}
	if preview.count == 0:
		_mass_preview.text = "No eligible province for this building." if preview.stopped_by == "all" \
				else "Nothing can be built: the first one costs more than %s allows." % limits[preview.stopped_by]
		_mass_button.text = "Build"
		_mass_button.disabled = true
	else:
		_mass_preview.text = "%d buildings for £%.1fM, materials included. Limited by %s." % [preview.count, preview.spent, limits[preview.stopped_by]]
		_mass_button.text = "Build %d for £%.1fM" % [preview.count, preview.spent]
		_mass_button.disabled = false


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_E:
		toggle()
