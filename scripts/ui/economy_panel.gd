extends FloatingWindow
## Economy of the player's nation in three tabs, all figures per month (building is in the
## Construction panel, B):
##   Overview:  problems, tax rate, income and spending, national programs.
##   Resources: food, coal, iron and timber: made, used, balance, stockpile.
##   Production: equipment in store and the production lines of the military factories.
## Toggle with E. Hover over a label for the detail behind it.

var _tabs := TabContainer.new()
var _alerts := VBoxContainer.new()
var _tax_slider := HSlider.new()
var _tax_label := Label.new()
var _tax_note := Label.new()
var _budget := HBoxContainer.new()
var _output := Label.new()
var _law := OptionButton.new()
var _law_note := Label.new()
var _law_updating := false
## Funding sliders: policy ("army_funding", "navy_funding") -> {slider, label, note}.
var _funding: Dictionary = {}
var _program_boxes: Dictionary = {}
var _resources := VBoxContainer.new()
var _production := VBoxContainer.new()
var _province := 0


func _ready() -> void:
	add_to_group("economy_panel")
	visible = false
	_tabs.focus_mode = Control.FOCUS_NONE
	add_child(_tabs)
	_tabs.add_child(_scroll(_build_overview(), "Overview"))
	_tabs.add_child(_scroll(_resources, "Resources"))
	_tabs.add_child(_scroll(_production, "Production"))
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
	_tax_slider.tooltip_text = "Share of output taken as tax. Above %d%% less of it reaches the treasury, and heavy taxes slow growth and wear down the people's support." % roundi(Economy.cfg.default_tax_rate * 100.0)
	_tax_slider.value_changed.connect(func(v: float) -> void:
		GameState.issue(SetEconomyPolicy.new(GameState.player_tag, "tax_rate", v))
	)
	_tax_label.custom_minimum_size = Vector2(44, 0)
	_tax_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	for c in [tax_name, _tax_slider, _tax_label]:
		tax_row.add_child(c)
	box.add_child(tax_row)
	_tax_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tax_note.custom_minimum_size = Vector2(400, 0)
	_tax_note.modulate = Fmt.WARN
	box.add_child(_tax_note)

	var law_row := HBoxContainer.new()
	var law_name := Label.new()
	law_name.text = "Economy law"
	law_name.custom_minimum_size = Vector2(80, 0)
	law_row.add_child(law_name)
	_law.focus_mode = Control.FOCUS_NONE
	_law.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for id in Economy.law_ids():
		_law.add_item(Economy.cfg.laws[id].name)
		_law.set_item_metadata(_law.item_count - 1, id)
	_law.item_selected.connect(func(i: int) -> void:
		if not _law_updating:
			GameState.issue(SetEconomyLaw.new(GameState.player_tag, _law.get_item_metadata(i)))
			_refresh()
	)
	law_row.add_child(_law)
	box.add_child(law_row)
	_law_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_law_note.custom_minimum_size = Vector2(400, 0)
	_law_note.modulate = Fmt.DIM
	box.add_child(_law_note)

	for policy in ["army_funding", "navy_funding"]:
		box.add_child(_funding_row(policy))

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


# ---------------------------------------------------------------- small widgets

## A slider for how well the army or the navy is funded: 1 is the usual upkeep, the economy law
## sets how high it can go, and the forces' readiness follows it slowly.
func _funding_row(policy: String) -> Control:
	var box := VBoxContainer.new()
	var row := HBoxContainer.new()
	var name_label := Label.new()
	name_label.text = "Army funding" if policy == "army_funding" else "Navy funding"
	name_label.custom_minimum_size = Vector2(110, 0)
	row.add_child(name_label)
	var slider := HSlider.new()
	slider.min_value = Economy.cfg.funding_min
	slider.max_value = 1.0
	slider.step = 0.05
	slider.focus_mode = Control.FOCUS_NONE
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(func(v: float) -> void:
		if not _law_updating:
			GameState.issue(SetEconomyPolicy.new(GameState.player_tag, policy, v))
	)
	row.add_child(slider)
	var label := Label.new()
	label.custom_minimum_size = Vector2(50, 0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(label)
	box.add_child(row)
	var note := Label.new()
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(400, 0)
	note.modulate = Fmt.DIM
	box.add_child(note)
	_funding[policy] = {"slider": slider, "label": label, "note": note, "box": box}
	return box


func _refresh_funding(n: Nation) -> void:
	var cap := Economy.funding_cap(n)
	for policy in _funding:
		var army: bool = policy == "army_funding"
		var f: float = n.army_funding if army else n.navy_funding
		var ready: float = n.army_ready if army else n.navy_ready
		var parts: Dictionary = _funding[policy]
		parts.box.visible = army or n.naval_budget > 0.0
		_law_updating = true
		parts.slider.max_value = cap
		parts.slider.set_value_no_signal(f)
		_law_updating = false
		parts.label.text = "%d%%" % roundi(f * 100.0)
		var cost: float = n.total_men() * Economy.cfg.soldier_upkeep / 1e6 if army else n.naval_budget
		parts.note.text = "Costs £%.1fM a month; %s fights at %d%% of its strength%s. %s allows up to %d%%." % [
				Fmt.monthly(cost * f), "the army" if army else "the navy", roundi(Military.readiness_power(ready) * 100.0),
				(" (readiness is moving toward %d%%)" % roundi(Military.readiness_power(f) * 100.0)) if absf(ready - f) > 0.01 else "",
				Economy.law_of(n).name, roundi(cap * 100.0)]


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
	if _tabs.current_tab == 1:
		_refresh_resources(n)
	elif _tabs.current_tab == 2:
		_refresh_production(n)


func _refresh_overview(n: Nation) -> void:
	var b := n.budget
	_tax_slider.set_value_no_signal(n.tax_rate)
	_tax_label.text = "%d%%" % roundi(n.tax_rate * 100.0)
	var strain: float = n.budget.get("tax_strain", 0.0)
	_tax_note.visible = strain > 0.005
	var cost: Dictionary = Economy.cfg.tax_strain
	_tax_note.text = "Heavy taxes: growth %.1f points a year lower, war support settles %d lower in peace, and %.1f a month is lost at war." % [
			cost.growth_penalty * strain * 100.0, roundi(cost.support_penalty * strain), cost.war_weariness * strain]

	# Problems first, so they cannot be missed.
	_clear(_alerts)
	var problems: PackedStringArray = []
	if n.blockade > 0.0:
		var by: PackedStringArray = []
		for t in n.blockade_by:
			by.append(GameState.nations[t].display_name)
		var cause := (" Enemy ships hold the sea routes (%s)." % ", ".join(by)) if not by.is_empty() else ""
		problems.append("Blockaded: imports and exports are cut by %d%%.%s" % [roundi(n.blockade * 100.0), cause])
	if n.treasury < 0.0:
		problems.append("The treasury is in debt.")
	elif b.net < 0.0:
		problems.append("Running a deficit of £%.1fM a month." % (-Fmt.monthly(b.net)))
	if b.food_shortage > 0.0:
		problems.append("Starvation: %d%% of food needs unmet." % roundi(b.food_shortage * 100.0))
	for r in Economy.resource_ids():
		if b.resources[r].shortage > 0.0:
			problems.append("%s shortage: %d%% of demand unmet, hurting industry." % [Economy.cfg.resources[r].name, roundi(b.resources[r].shortage * 100.0)])
	if not GameState.wars_of(n.tag).is_empty() and n.war_support <= 30.0:
		problems.append("War support is %d: below %d the people force a peace. %s" % [roundi(n.war_support), int(WarSupport.cfg().white_peace_below), WarSupport.effects_text(GameState, n.tag)])
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
	var taxes: float = Fmt.monthly(b.revenue - b.trade - b.resource_exports - b.factory_income)
	var trade: float = Fmt.monthly(b.trade + b.resource_exports)
	_head_row(g, "Income")
	_cell(g, "Taxes", 0, Color.WHITE, "Output of £%.1fM a month taxed at %d%%." % [Fmt.monthly(b.gdp), roundi(n.tax_rate * 100.0)])
	_cell(g, Fmt.money(taxes, true), 1)
	if trade > 0.04:
		_cell(g, "Trade", 0, Color.WHITE, "Ports £%.1fM, resource exports £%.1fM." % [Fmt.monthly(b.trade), Fmt.monthly(b.resource_exports)])
		_cell(g, Fmt.money(trade, true), 1)
	if absf(b.factory_income) > 0.04:
		_cell(g, "Factories", 0, Color.WHITE, "Civilian factories built since the start pay %s each a year into the treasury (retooled ones cost it). The factories you began with are already in the taxes." % Fmt.money(Economy.factory_income(n)))
		_cell(g, Fmt.money(Fmt.monthly(b.factory_income), true), 1)
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
	if b.equipment > 0.04:
		_cell(spend, "Equipment", 0, Color.WHITE, "What the production lines cost at full tilt: money for every item made (see the Production tab). Paid a day at a time.")
		_cell(spend, Fmt.money(-Fmt.monthly(b.equipment), true), 1)
	_total_row(spend, "Total spending", -Fmt.monthly(b.expenses), Color.WHITE)
	_total_row(g, "Net per month", Fmt.monthly(b.net), Fmt.GOOD if b.net >= 0.0 else Fmt.BAD)

	_output.text = "Output £%.0fM a month, industry £%.0fM." % [Fmt.monthly(b.gdp), Fmt.monthly(b.industry)]
	_refresh_law(n)

	for id in _program_boxes:
		var def: Dictionary = Economy.cfg.programs[id]
		var check: CheckBox = _program_boxes[id]
		check.set_pressed_no_signal(n.programs.has(id))
		check.text = "%s  (%s a month)" % [def.name, Fmt.money(-def.cost_gdp_share * Fmt.monthly(b.gdp), true)]
		check.tooltip_text = "Effect: " + _effects_text(def.effects)


## Shows the law in force, which others can be taken (the rest are greyed, with why), and what
## the law does.
func _refresh_law(n: Nation) -> void:
	_law_updating = true
	for i in _law.item_count:
		var id: String = _law.get_item_metadata(i)
		var problem := Economy.law_problem(GameState, n.tag, id)
		var lower: bool = Economy.law_ids().find(id) < Economy.law_ids().find(n.economy_law)
		if lower:
			problem = Economy.law_requirement(GameState, n.tag, id)
		_law.set_item_disabled(i, id != n.economy_law and not problem.is_empty())
		_law.set_item_tooltip(i, "%s%s" % [_law_text(id), ("\n" + problem) if id != n.economy_law and not problem.is_empty() else ""])
		if id == n.economy_law:
			_law.select(i)
	_law_updating = false
	_refresh_funding(n)
	var law := Economy.law_of(n)
	_law_note.text = "%s Consumer goods take %d%% of civilian factory work, so %.0f construction points a day are left (%d factories). Military factories +%d%%, national output %+d%%." % [
			_law_requires_text(n.economy_law), roundi(law.consumer * 100.0), n.budget.construction_points, int(n.budget.factories),
			roundi((law.military - 1.0) * 100.0), roundi((law.gdp - 1.0) * 100.0)]
	if law.weariness > 0.0:
		_law_note.text += " Costs %.1f war support a month at war." % law.weariness


func _law_text(id: String) -> String:
	var law: Dictionary = Economy.cfg.laws[id]
	return "%s: consumer goods %d%%, military factories %+d%%, output %+d%%, mobilization %d to %d%%%s." % [law.name, roundi(law.consumer * 100.0),
			roundi((law.military - 1.0) * 100.0), roundi((law.gdp - 1.0) * 100.0),
			roundi(law.mobilization[0] * 100.0), roundi(law.mobilization[1] * 100.0),
			(", %.1f war support a month at war" % law.weariness) if law.weariness > 0.0 else ""]


func _law_requires_text(id: String) -> String:
	var req: Dictionary = Economy.cfg.laws[id].requires
	if req.is_empty():
		return "Peacetime economy."
	var parts: PackedStringArray = []
	if req.get("war", false):
		parts.append("at war")
	if req.has("war_or_mobilization"):
		parts.append("at war or %d%% mobilized" % roundi(float(req.war_or_mobilization) * 100.0))
	if req.has("mobilization"):
		parts.append("%d%% mobilized" % roundi(float(req.mobilization) * 100.0))
	return "Needs: " + ", ".join(parts) + "."


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

	_resources.add_child(HSeparator.new())
	_resources.add_child(_heading("Where it goes, a month"))
	var uses := _grid(5)
	_resources.add_child(uses)
	for h in ["", "Industry", "Homes", "Buildings", "Equipment"]:
		_cell(uses, h, -1, Fmt.DIM)
	var kit := Production.planned_materials(n)
	for r in Economy.resource_ids():
		var info: Dictionary = b.resources[r]
		_cell(uses, Economy.cfg.resources[r].name, 0)
		_cell(uses, Fmt.kt(Fmt.monthly(info.from_industry)), 1)
		_cell(uses, Fmt.kt(Fmt.monthly(info.from_homes)), 1)
		_cell(uses, Fmt.kt(Fmt.monthly(info.from_buildings)), 1, Color.WHITE, "Factories and railways burn coal and iron to run.")
		_cell(uses, Fmt.kt(Fmt.monthly(float(kit.get(r, 0.0)))), 1, Color.WHITE,
				"What your equipment lines use at full tilt. It comes out of the stockpile first and is bought abroad, at a markup, when that runs dry.")
	for r in Economy.resource_ids():
		var info2: Dictionary = b.resources[r]
		if info2.shortage > 0.0:
			_resources.add_child(_status("Short of %s: industry %d%% down, output %d%% down." % [
					Economy.cfg.resources[r].name.to_lower(), roundi(info2.cost_industry * 100.0), roundi(info2.cost_gdp * 100.0)], Fmt.BAD))
	_resources.add_child(_note("Green balances are exported, orange ones imported. Imports lock civilian factories. A blockade stops both, the stockpile runs down, and shortages cut industry and output."))


# ---------------------------------------------------------------- production

func _refresh_production(n: Nation) -> void:
	_clear(_production)
	var cats: Array = Military.equipment_ids()
	var store: PackedStringArray = []
	for cat in cats:
		store.append("%s %s" % [Military.cfg.equipment.categories[cat].name, Fmt.thousands(roundi(n.equipment.get(cat, 0.0)))])
	var head := Label.new()
	head.text = "In store: " + ",  ".join(store)
	head.tooltip_text = "Arms in thousands of rifles, artillery in batteries. Units draw what they lack from the store."
	head.mouse_filter = Control.MOUSE_FILTER_PASS
	_production.add_child(head)
	var factories := Label.new()
	factories.text = "Military factories: %d, %d free" % [Production.total_factories(n), Production.free_factories(n)]
	factories.tooltip_text = "Your military factories and the arsenals every army has. Retool factories in the Construction panel (B)."
	factories.mouse_filter = Control.MOUSE_FILTER_PASS
	_production.add_child(factories)
	var auto := CheckButton.new()
	auto.text = "Automatic"
	auto.focus_mode = Control.FOCUS_NONE
	auto.button_pressed = n.lines_auto
	auto.tooltip_text = "Shares the factories between the categories and keeps them in use as their number changes. Changing a line by hand turns this off."
	auto.toggled.connect(func(on: bool) -> void:
		GameState.issue(SetProductionAuto.new(GameState.player_tag, on))
		_refresh()
	)
	_production.add_child(auto)
	_production.add_child(HSeparator.new())

	var g := _grid(6)
	_production.add_child(g)
	for h in ["Line", "Factories", "Efficiency", "A month", "Cost", ""]:
		_cell(g, h, -1, Fmt.DIM)
	for line in n.production_lines:
		_production_row(g, n, line, cats)
	if n.production_lines.is_empty():
		_production.add_child(_note("No lines: the factories make nothing."))
	var add := Button.new()
	add.text = "New line"
	add.focus_mode = Control.FOCUS_NONE
	add.disabled = Production.free_factories(n) < 1
	add.tooltip_text = "No free factory." if add.disabled else "Opens an arms line with one free factory."
	add.pressed.connect(func() -> void:
		GameState.issue(SetProductionLine.new(GameState.player_tag, 0, cats[0], 1))
		_refresh()
	)
	_production.add_child(add)
	_production.add_child(_note("A factory makes one kind of equipment. A line starts at %d%% efficiency and reaches %d%% after %d days; changing what it makes keeps only %d%% of it. Each item costs industrial capacity and iron, coal or nitrates, which are flows: a line short of one makes less. Shells feed the artillery in battle, and with none left a gun loses %d%% of its attack." % [roundi(Military.cfg.equipment.efficiency_start * 100.0), roundi(Military.cfg.equipment.efficiency_cap * 100.0), int(Military.cfg.equipment.efficiency_days), roundi(Military.cfg.equipment.efficiency_keep_kind * 100.0), roundi(Military.cfg.combat.shell_penalty * 100.0)]))


func _production_row(g: GridContainer, n: Nation, line: Dictionary, cats: Array) -> void:
	var pick := OptionButton.new()
	pick.focus_mode = Control.FOCUS_NONE
	pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for i in cats.size():
		pick.add_item(Military.cfg.equipment.categories[cats[i]].name)
		if cats[i] == line.category:
			pick.select(i)
	pick.item_selected.connect(func(i: int) -> void:
		GameState.issue(SetProductionLine.new(GameState.player_tag, line.id, cats[i], line.factories))
		_refresh()
	)
	g.add_child(pick)
	var count := HBoxContainer.new()
	count.alignment = BoxContainer.ALIGNMENT_END
	var less := Button.new()
	less.text = "-"
	less.focus_mode = Control.FOCUS_NONE
	less.pressed.connect(func() -> void:
		GameState.issue(SetProductionLine.new(GameState.player_tag, line.id, line.category, line.factories - 1))
		_refresh()
	)
	count.add_child(less)
	var shown := Label.new()
	shown.text = str(line.factories)
	shown.custom_minimum_size = Vector2(26, 0)
	shown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count.add_child(shown)
	var more := Button.new()
	more.text = "+"
	more.focus_mode = Control.FOCUS_NONE
	more.disabled = Production.free_factories(n) < 1
	more.pressed.connect(func() -> void:
		GameState.issue(SetProductionLine.new(GameState.player_tag, line.id, line.category, line.factories + 1))
		_refresh()
	)
	count.add_child(more)
	g.add_child(count)
	var eff := Production.efficiency(line)
	_cell(g, "%d%%" % roundi(eff * 100.0), 1, Fmt.GOOD if eff >= Military.cfg.equipment.efficiency_cap - 0.001 else Fmt.WARN,
			"Efficiency of the line: it climbs while the line runs and starts over if it changes what it makes.")
	var made_month: float = line.made * 30.0
	var short: bool = line.limit != ""
	_cell(g, "%.0f" % made_month, 1, Fmt.BAD if short else Color.WHITE,
			("Held back by a lack of %s." % line.limit) if short else "Items made a month at today's rate (%.0f at best)." % (Production.capacity(n, line) * 30.0))
	var cost := Production.item_cost(line.category)
	var parts: PackedStringArray = []
	for key in cost:
		if key == "ic":
			parts.append("%s IC" % Fmt.thousands(roundi(made_month * float(cost[key]))))
		else:
			parts.append("%s %s" % [Economy.cfg.resources[key].name.to_lower(), Fmt.kt(made_month * float(cost[key]))])
	_cell(g, parts[0], 1, Color.WHITE, ", ".join(parts))
	var close := Button.new()
	close.text = "x"
	close.focus_mode = Control.FOCUS_NONE
	close.tooltip_text = "Close the line and free its factories."
	close.pressed.connect(func() -> void:
		GameState.issue(SetProductionLine.new(GameState.player_tag, line.id, line.category, 0))
		_refresh()
	)
	g.add_child(close)


# ---------------------------------------------------------------- mass build

func _effects_text(effects: Dictionary) -> String:
	var names := {"gdp": "output", "industry": "industry", "food": "food", "trade": "trade income", "growth": "growth/yr"}
	var parts: PackedStringArray = []
	for k in effects:
		if k == "diplomacy":
			parts.append("+%.1f diplomacy points a month" % effects[k])
		else:
			parts.append("+%d%% %s" % [roundi(effects[k] * 100.0), names[k]])
	return ", ".join(parts)


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_E:
		toggle()
