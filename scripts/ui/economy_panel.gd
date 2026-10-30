extends FloatingWindow
## The economy of the player's nation, in three sections (see Economy), all figures per month (building is in the
## Construction panel, B):
##   Gold:         problems, income by source and spending by kind, and the net.
##   Construction: construction points, where they come from and what they buy.
##   People:       manpower, mobilization and the standing army.
## Toggle with E. Hover over a label for the detail behind it.

var _alerts := VBoxContainer.new()
var _budget := HBoxContainer.new()
var _industry := VBoxContainer.new()
var _people := VBoxContainer.new()
var _mob_slider := HSlider.new()
var _mob_label := Label.new()
var _mob_note := Label.new()
var _army_slider := HSlider.new()
var _army_label := Label.new()
var _army_note := Label.new()
var _updating := false
var _province := 0


func _ready() -> void:
	add_to_group("economy_panel")
	visible = false
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	column.add_child(_heading("Gold"))
	column.add_child(_build_money())
	column.add_child(_heading("Construction"))
	column.add_child(_industry)
	column.add_child(_heading("People"))
	column.add_child(_build_people())
	add_child(_scroll(column, "Economy"))
	setup_window("Economy", true, Vector2(520, 0), 0)
	_fit_tab()

	GameState.economy_updated.connect(_refresh)
	GameState.player_changed.connect(func(_t: String) -> void: _refresh())
	_refresh()


func toggle() -> void:
	toggle_window()
	if visible:
		_refresh()
		_fit_tab.call_deferred()


## Sizes the window to its content, unless the player has sized it.
func _fit_tab() -> void:
	fit_window(minf(get_child(0).get_child(0).get_combined_minimum_size().y + 34.0, 520.0))


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


func _slider_row(name_text: String, slider: HSlider, label: Label, note: Label, tip: String) -> Control:
	var box := VBoxContainer.new()
	var row := HBoxContainer.new()
	var name_label := Label.new()
	name_label.text = name_text
	name_label.custom_minimum_size = Vector2(100, 0)
	slider.step = 0.01
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.focus_mode = Control.FOCUS_NONE
	slider.tooltip_text = tip
	label.custom_minimum_size = Vector2(44, 0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	for c in [name_label, slider, label]:
		row.add_child(c)
	box.add_child(row)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(400, 0)
	box.add_child(note)
	return box


func _build_money() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	_alerts.add_theme_constant_override("separation", 1)
	box.add_child(_alerts)
	_budget.add_theme_constant_override("separation", 14)
	box.add_child(_budget)
	return box


func _build_people() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	_mob_slider.min_value = 0.0
	_mob_slider.max_value = 1.0
	_mob_slider.value_changed.connect(func(v: float) -> void:
		if not _updating:
			GameState.issue(SetEconomyPolicy.new(GameState.player_tag, "mobilization", v))
	)
	_mob_note.modulate = Fmt.DIM
	box.add_child(_slider_row("Mobilization", _mob_slider, _mob_label, _mob_note,
			"How much of the manpower pool is called up. More men under arms means a stronger army and less base income from the provinces; the line below says what the level costs a month."))
	_army_slider.value_changed.connect(func(v: float) -> void:
		if not _updating:
			GameState.issue(SetEconomyPolicy.new(GameState.player_tag, "standing_army", v * 1000.0))
	)
	_army_note.modulate = Fmt.DIM
	box.add_child(_slider_row("Standing army", _army_slider, _army_label, _army_note,
			"The men kept under arms in peace, in thousands. Gold is what limits it: every division costs its upkeep each month. Raise the units themselves on the Military tab once the recruits are in."))
	_army_slider.step = 12.0
	box.add_child(_people)
	return box


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


# ---------------------------------------------------------------- refresh

func _refresh() -> void:
	var n := GameState.get_player()
	if n == null or n.budget.is_empty() or not visible:
		return
	_refresh_money(n)
	_refresh_industry(n)
	_refresh_people(n)


func _refresh_money(n: Nation) -> void:
	var b := n.budget
	# Problems first, so they cannot be missed.
	_clear(_alerts)
	var problems: PackedStringArray = []
	if n.blockade > 0.0:
		var by: PackedStringArray = []
		for t in n.blockade_by:
			by.append(GameState.nations[t].display_name)
		var cause := (" Enemy ships hold the sea routes (%s)." % ", ".join(by)) if not by.is_empty() else ""
		problems.append("Blockaded: port income is cut by %d%% and factory income by %d%%.%s" % [roundi(n.blockade * 100.0),
				roundi(n.blockade * float(Economy.cfg.income.blockade_factory_loss) * 100.0), cause])
	if n.treasury < 0.0:
		problems.append("The treasury is in debt: interest takes %s a month." % Fmt.gold(b.interest))
	elif b.net < 0.0:
		problems.append("Running a deficit of %s a month." % Fmt.gold(-b.net))
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
	var levels: Dictionary = b.get("levels", {})
	var inc: Dictionary = Economy.cfg.income
	_head_row(g, "Income")
	_cell(g, "Provinces", 0, Color.WHITE, "Base income from the people of the provinces you hold (fixed: it grows only with what you build or take). Mobilization takes up to %d%% of it." % roundi(float(inc.mobilization_loss) * 100.0))
	_cell(g, Fmt.money(b.base, true), 1)
	_cell(g, "Civilian factories", 0, Color.WHITE, "%d factories, %s a month each." % [int(levels.get("civilian_factory", 0)), Fmt.gold(float(Economy.cfg.buildings.civilian_factory.income))])
	_cell(g, Fmt.money(b.factories, true), 1)
	if b.ports > 0.04 or int(levels.get("port", 0)) > 0:
		_cell(g, "Ports", 0, Color.WHITE, "%d port levels, %s a month each; a blockade cuts it." % [int(levels.get("port", 0)), Fmt.gold(float(Economy.cfg.buildings.port.income))])
		_cell(g, Fmt.money(b.ports, true), 1)
	if b.occupied > 0.04:
		_cell(g, "Occupied ground", 0, Color.WHITE, "%d%% of the base income of the enemy provinces you hold." % roundi(float(inc.occupied_share) * 100.0))
		_cell(g, Fmt.money(b.occupied, true), 1)
	_total_row(g, "Total income", b.income, Color.WHITE)

	_head_row(spend, "Spending")
	_cell(spend, "Army", 0, Color.WHITE, "Every unit's upkeep, in the field and in training (more for armies on exercise).")
	_cell(spend, Fmt.money(-b.army, true), 1)
	_cell(spend, "Navy", 0, Color.WHITE, "The ships' upkeep and the shore establishment.")
	_cell(spend, Fmt.money(-b.navy, true), 1)
	_cell(spend, "Buildings", 0, Color.WHITE, "The upkeep of construction sectors, railways, forts and trenches (civilian factories and ports cost nothing to keep).")
	_cell(spend, Fmt.money(-b.buildings, true), 1)
	if b.interest > 0.04:
		_cell(spend, "Interest", 0, Color.WHITE, "%d%% a year on the debt." % roundi(float(Economy.cfg.debt.interest) * 100.0))
		_cell(spend, Fmt.money(-b.interest, true), 1)
	_total_row(spend, "Total spending", -b.expenses, Color.WHITE)
	_total_row(g, "Net per month", b.net, Fmt.GOOD if b.net >= 0.0 else Fmt.BAD)


func _refresh_industry(n: Nation) -> void:
	_clear(_industry)
	var b := n.budget
	var levels: Dictionary = b.get("levels", {})
	var g := _grid(2)
	_industry.add_child(g)
	_cell(g, "Construction points", 0, Color.WHITE, "In hand: starting a building spends its gold and its points at once.")
	_cell(g, "%d" % roundi(n.cp), 1)
	_cell(g, "Points a day", 0, Color.WHITE, "%d construction sectors, %s a day each, the capital's %s, and the national focus." % [int(levels.get("construction_sector", 0)),
			str(Economy.cfg.buildings.construction_sector.cp_per_day), str(Economy.cfg.construction.capital_cp)])
	_cell(g, "%.2f (%d a month)" % [float(b.cp), roundi(float(b.cp) * 30.0)], 1)
	var under_way := 0
	for job in n.construction:
		if job.started:
			under_way += 1
	_cell(g, "Projects", 0, Color.WHITE, "Under way, and waiting in the queue for their province to be free or for the gold and points.")
	_cell(g, "%d under way, %d waiting" % [under_way, n.construction.size() - under_way], 1)
	var f: Dictionary = Economy.build_plan(GameState, 0, "civilian_factory")
	_industry.add_child(_note("A civilian factory costs %s and %d points and takes %d days; it earns %s a month. Your surplus pays for one every %s, your points every %s." % [
			Fmt.gold(f.gold), roundi(f.cp), f.days, Fmt.gold(float(Economy.cfg.buildings.civilian_factory.income)),
			_months(f.gold, float(b.net)), _months(f.cp, float(b.cp) * 30.0)]))


## "3.2 months", or "never" with nothing coming in.
func _months(need: float, per_month: float) -> String:
	if per_month <= 0.001:
		return "never"
	return "%.1f months" % (need / per_month)


func _refresh_people(n: Nation) -> void:
	var b := n.budget
	var range := Economy.mobilization_range(GameState, n)
	_updating = true
	_mob_slider.min_value = range.x
	_mob_slider.max_value = range.y
	_mob_slider.set_value_no_signal(n.mobilization)
	_updating = false
	_mob_label.text = "%d%%" % roundi(n.mobilization * 100.0)
	var cap := Economy.standing_cap(GameState, n)
	var per_div := Economy.division_upkeep(GameState, n)
	_updating = true
	_army_slider.min_value = 0.0
	_army_slider.max_value = maxf(cap, n.peacetime_army) / 1000.0
	_army_slider.set_value_no_signal(n.peacetime_army / 1000.0)
	_updating = false
	_army_label.text = "%dk" % roundi(n.peacetime_army / 1000.0)
	var keepable := floori(maxf(0.0, float(b.net)) / maxf(per_div, 0.0001))
	_army_note.text = "Up to %dk in peace. A division of 12,000 costs %s a month to keep: your monthly surplus pays for %d more. %dk are under arms now." % [roundi(cap / 1000.0), Fmt.gold(per_div), keepable, roundi(n.men_in_units / 1000.0)]
	var cost := Economy.mobilization_cost(GameState, n, n.mobilization)
	_mob_note.text = "May be between %d%% and %d%% %s. %s" % [roundi(range.x * 100.0), roundi(range.y * 100.0), "at war" if not GameState.wars_of(n.tag).is_empty() else "in peace",
			"At %d%% it costs about %s a month of base income." % [roundi(n.mobilization * 100.0), Fmt.gold(cost)] if n.mobilization > 0.005 else "Each step costs base income: at %d%% about %s a month." % [roundi(range.y * 100.0), Fmt.gold(Economy.mobilization_cost(GameState, n, range.y))]]
	_clear(_people)
	var g := _grid(2)
	_people.add_child(g)
	_cell(g, "Population", 0)
	_cell(g, Fmt.people(n.population), 1)
	_cell(g, "Under arms", 0, Color.WHITE, "In armies and in training.")
	_cell(g, Fmt.people(n.men_in_units), 1)
	_cell(g, "Reserve", 0, Color.WHITE, "Recruits not yet in a unit; refilled monthly.")
	_cell(g, Fmt.people(n.manpower), 1)
	_cell(g, "Most that may be called up", 0)
	_cell(g, Fmt.people(b.manpower_max), 1)
	# What the money is for: divisions the surplus keeps, the treasury raises and the reserve fills, and the war chest.
	var inf: Dictionary = Military.cfg.unit_types.infantry
	_cell(g, "Divisions the budget can keep", 0, Color.WHITE, "More divisions the monthly surplus would pay for, at %s a month each." % Fmt.gold(per_div))
	_cell(g, "%d more" % keepable, 1, Fmt.GOOD if keepable > 0 else Fmt.WARN)
	_cell(g, "Divisions the treasury can raise", 0, Color.WHITE, "At %s each, paid when training begins." % Fmt.gold(float(inf.cost)))
	_cell(g, "%d" % floori(maxf(0.0, n.treasury) / maxf(float(inf.cost), 0.001)), 1)
	_cell(g, "Recruits ready for", 0, Color.WHITE, "The reserve, in divisions of %s. Raise the standing army to call more." % Fmt.thousands(int(inf.size)))
	_cell(g, "%d divisions" % floori(float(n.manpower) / maxf(float(inf.size), 1.0)), 1)
	var war_cost := Economy.mobilization_cost(GameState, n, 1.0)
	if war_cost > 0.01:
		_cell(g, "War chest", 0, Color.WHITE, "How long the treasury pays for full mobilization in a war (about %s a month on top of today's budget) before the state borrows." % Fmt.gold(war_cost))
		_cell(g, "%d months" % floori(maxf(0.0, n.treasury) / war_cost), 1)
	_cell(g, "War support", 0)
	_cell(g, "%d" % roundi(n.war_support), 1)


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_E and not event.ctrl_pressed:
		toggle()
