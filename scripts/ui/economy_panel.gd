extends FloatingWindow
## The economy of the player's nation, in three sections that follow its three pillars (see Economy), all
## figures per month (building is in the Construction panel, B):
##   Money:    problems, the tax rate, income and spending.
##   Industry: construction points, what the queue takes, and the raw materials.
##   People:   manpower, mobilization, and food.
## Toggle with E. Hover over a label for the detail behind it.

var _alerts := VBoxContainer.new()
var _tax_slider := HSlider.new()
var _tax_label := Label.new()
var _tax_note := Label.new()
var _budget := HBoxContainer.new()
var _industry := VBoxContainer.new()
var _people := VBoxContainer.new()
var _mob_slider := HSlider.new()
var _mob_label := Label.new()
var _mob_note := Label.new()
var _army_slider := HSlider.new()
var _army_label := Label.new()
var _army_note := Label.new()
var _invest_slider := HSlider.new()
var _invest_label := Label.new()
var _invest_note := Label.new()
var _arms_slider := HSlider.new()
var _arms_label := Label.new()
var _arms_note := Label.new()
var _arms := VBoxContainer.new()
var _buy := Button.new()
var _updating := false
var _province := 0


func _ready() -> void:
	add_to_group("economy_panel")
	visible = false
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	column.add_child(_heading("Money"))
	column.add_child(_build_money())
	column.add_child(_heading("Industry"))
	column.add_child(_build_arms())
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
	_tax_slider.min_value = Economy.cfg.min_tax_rate
	_tax_slider.max_value = Economy.cfg.max_tax_rate
	_tax_slider.value_changed.connect(func(v: float) -> void:
		if not _updating:
			GameState.issue(SetEconomyPolicy.new(GameState.player_tag, "tax_rate", v))
	)
	_tax_note.modulate = Fmt.WARN
	box.add_child(_slider_row("Tax rate", _tax_slider, _tax_label, _tax_note,
			"Share of output taken as tax. Above %d%% less of it reaches the treasury, and heavy taxes slow growth and wear down the people's support." % roundi(Economy.cfg.default_tax_rate * 100.0)))
	_invest_slider.min_value = 0.0
	_invest_slider.max_value = 1.0
	_invest_slider.value_changed.connect(func(v: float) -> void:
		if not _updating:
			var n := GameState.get_player()
			GameState.issue(SetEconomyPolicy.new(GameState.player_tag, "investment", v * float(n.budget.get("gdp", 0.0)) / 12.0 * 0.1))
	)
	_invest_note.modulate = Fmt.DIM
	box.add_child(_slider_row("Investment", _invest_slider, _invest_label, _invest_note,
			"Money the state puts into roads, schools and credit each month: it is spent like any other cost and makes the economy grow faster, each further pound doing a little less."))
	_budget.add_theme_constant_override("separation", 14)
	box.add_child(_budget)
	return box


## Arms production: the share of the day's IC that goes to munitions, the stockpile, and munitions bought abroad.
func _build_arms() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	_arms_slider.min_value = 0.0
	_arms_slider.max_value = 1.0
	_arms_slider.value_changed.connect(func(v: float) -> void:
		if not _updating:
			GameState.issue(SetEconomyPolicy.new(GameState.player_tag, "arms_share", v))
	)
	_arms_note.modulate = Fmt.DIM
	box.add_child(_slider_row("Arms", _arms_slider, _arms_label, _arms_note,
			"The share of each day's industry (IC) that makes munitions for the guns, before buildings and ships. The factories making shells are not making the people's goods, so output falls a little. In battle the guns burn munitions; without them they fight weaker."))
	_buy.focus_mode = Control.FOCUS_NONE
	_buy.pressed.connect(func() -> void:
		GameState.issue(BuyMunitions.new(GameState.player_tag, _buy_amount()))
		_refresh()
	)
	box.add_child(_arms)
	box.add_child(_buy)
	return box


## What one press of the buy button spends: a month of revenue, at least £1M.
func _buy_amount() -> float:
	var n: Nation = GameState.get_player()
	return maxf(1.0, roundf(Fmt.monthly(float(n.budget.get("revenue", 12.0)))))


func _refresh_arms(n: Nation) -> void:
	var b := n.budget
	_updating = true
	_arms_slider.set_value_no_signal(n.arms_share)
	_updating = false
	_arms_label.text = "%d%%" % roundi(n.arms_share * 100.0)
	var pool: float = b.get("construction_points", 0.0)
	_arms_note.text = "%d IC a day into munitions; output %d%% lower for it. %s" % [roundi(pool * n.arms_share), roundi((1.0 - float(b.get("arms_mult", 1.0))) * 100.0), Munitions.line(GameState, n.tag)]
	_clear(_arms)
	if n.shell_ratio < 0.99 and not GameState.wars_of(n.tag).is_empty():
		_arms.add_child(_status("Short of shells: the guns got %d%% of what they needed yesterday." % roundi(n.shell_ratio * 100.0), Fmt.BAD))
	var amount := _buy_amount()
	var got := Munitions.bought_for(n, amount)
	_buy.text = "Buy munitions abroad: £%.0fM for %s IC" % [amount, Fmt.thousands(roundi(got))]
	_buy.tooltip_text = "Shells and guns bought from foreign firms, at £%.2fM a thousand. A blockade cuts what arrives (now %d%%)." % [float(Munitions.cfg().import_price) * 1000.0, roundi(n.blockade * 100.0)]
	_buy.disabled = n.treasury < amount


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
			"How much of the manpower pool is called up. More men under arms means a stronger army and weaker factories and fields; the reservists are paid, and the line below says what the level costs a month."))
	_army_slider.value_changed.connect(func(v: float) -> void:
		if not _updating:
			GameState.issue(SetEconomyPolicy.new(GameState.player_tag, "standing_army", v * 1000.0))
	)
	_army_note.modulate = Fmt.DIM
	box.add_child(_slider_row("Standing army", _army_slider, _army_label, _army_note,
			"The men kept under arms in peace, in thousands. Money is what limits it: every division costs its upkeep each month. Raise the units themselves on the Military tab once the recruits are in."))
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
	_refresh_arms(n)
	_refresh_industry(n)
	_refresh_people(n)


func _refresh_money(n: Nation) -> void:
	var b := n.budget
	_updating = true
	_tax_slider.set_value_no_signal(n.tax_rate)
	_updating = false
	_tax_label.text = "%d%%" % roundi(n.tax_rate * 100.0)
	var most: float = maxf(float(b.get("gdp", 0.0)) / 12.0 * 0.1, 0.001)
	_updating = true
	_invest_slider.set_value_no_signal(clampf(n.investment / most, 0.0, 1.0))
	_updating = false
	_invest_label.text = "£%.1fM" % n.investment
	_invest_note.text = "Growth %.2f points a year higher for £%.1fM a month (at most £%.1fM, a tenth of the month's output)." % [Economy.investment_growth(n) * 100.0, n.investment, most]
	var strain: float = b.get("tax_strain", 0.0)
	var relief: float = b.get("tax_relief", 0.0)
	_tax_note.visible = true
	var cost: Dictionary = Economy.cfg.tax_strain
	var gift: Dictionary = Economy.cfg.tax_relief
	if strain > 0.005:
		_tax_note.text = "Heavy taxes: growth %.1f points a year lower, war support settles %d lower in peace, and %.1f a month is lost at war." % [
				cost.growth_penalty * strain * 100.0, roundi(cost.support_penalty * strain), cost.war_weariness * strain]
		_tax_note.modulate = Fmt.WARN
	elif relief > 0.005:
		_tax_note.text = "Light taxes: growth %.1f points a year higher and war support settles %d higher, for less in the treasury." % [
				float(gift.growth_bonus) * relief * 100.0, roundi(float(gift.support_bonus) * relief)]
		_tax_note.modulate = Fmt.GOOD
	else:
		_tax_note.text = "The usual rate. Higher fills the treasury but slows growth and wears on the people; lower spurs growth for less money."
		_tax_note.modulate = Fmt.DIM

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
		problems.append("The treasury is in debt: interest takes £%.1fM a month." % Fmt.monthly(b.interest))
	elif b.net < 0.0:
		problems.append("Running a deficit of £%.1fM a month." % (-Fmt.monthly(b.net)))
	if b.food_shortage > 0.0:
		problems.append("Starvation: %d%% of food needs unmet." % roundi(b.food_shortage * 100.0))
	if b.materials.ratio < 0.999:
		problems.append("Raw materials: %d%% of what industry needs, so output is cut." % roundi(b.materials.ratio * 100.0))
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
	var mats: Dictionary = b.materials
	var taxes: float = Fmt.monthly(b.revenue - b.trade - mats.income)
	_head_row(g, "Income")
	_cell(g, "Taxes", 0, Color.WHITE, "Output of £%.1fM a month taxed at %d%%." % [Fmt.monthly(b.gdp), roundi(n.tax_rate * 100.0)])
	_cell(g, Fmt.money(taxes, true), 1)
	if b.trade > 0.04:
		_cell(g, "Trade", 0, Color.WHITE, "Duties at the ports.")
		_cell(g, Fmt.money(Fmt.monthly(b.trade), true), 1)
	if mats.income > 0.04:
		_cell(g, "Exports", 0, Color.WHITE, "Raw materials sold abroad.")
		_cell(g, Fmt.money(Fmt.monthly(mats.income), true), 1)
	_total_row(g, "Total income", Fmt.monthly(b.revenue), Color.WHITE)

	_head_row(spend, "Spending")
	_cell(spend, "Civil", 0, Color.WHITE, "Running the state. It follows the output: as the economy grows, so does the state, and it takes about three quarters of what the extra output pays in tax.")
	_cell(spend, Fmt.money(-Fmt.monthly(b.civil), true), 1)
	_cell(spend, "Military", 0, Color.WHITE, "Army upkeep £%.1fM, navy £%.1fM." % [Fmt.monthly(b.army), Fmt.monthly(b.naval)])
	_cell(spend, Fmt.money(-Fmt.monthly(b.army + b.naval), true), 1)
	var imports: float = Fmt.monthly(b.food_imports + b.materials_cost)
	if imports > 0.04:
		_cell(spend, "Imports", 0, Color.WHITE, "Food £%.1fM, raw materials £%.1fM." % [Fmt.monthly(b.food_imports), Fmt.monthly(b.materials_cost)])
		_cell(spend, Fmt.money(-imports, true), 1)
	if b.get("investment", 0.0) > 0.04:
		_cell(spend, "Investment", 0, Color.WHITE, "What the state puts into the economy's growth.")
		_cell(spend, Fmt.money(-Fmt.monthly(b.investment), true), 1)
	if b.get("munitions_storage", 0.0) > 0.04:
		_cell(spend, "Arms in store", 0, Color.WHITE, "Keeping the stockpile of munitions.")
		_cell(spend, Fmt.money(-Fmt.monthly(b.munitions_storage), true), 1)
	if b.interest > 0.04:
		_cell(spend, "Interest", 0, Color.WHITE, "On the debt.")
		_cell(spend, Fmt.money(-Fmt.monthly(b.interest), true), 1)
	_total_row(spend, "Total spending", -Fmt.monthly(b.expenses), Color.WHITE)
	_total_row(g, "Net per month", Fmt.monthly(b.net), Fmt.GOOD if b.net >= 0.0 else Fmt.BAD)


func _refresh_industry(n: Nation) -> void:
	_clear(_industry)
	var b := n.budget
	var mats: Dictionary = b.materials
	_industry.add_child(_heading("Construction"))
	var g := _grid(2)
	_industry.add_child(g)
	_cell(g, "Building capacity a day", 0, Color.WHITE, "The industry's output times %.2f, plus %d for small works everywhere (less in a small economy), plus the national focus." % [Economy.cfg.construction.ic_per_industry, roundi(Economy.base_ic(float(b.gdp)))])
	_cell(g, Fmt.thousands(roundi(b.construction_points)), 1)
	_cell(g, "Industrial output", 0, Color.WHITE, "Before the cuts below: £%.0fM a month." % Fmt.monthly(b.industry / maxf(b.industry_scale, 0.001)))
	_cell(g, "£%.0fM a month" % Fmt.monthly(b.industry), 1)
	_cell(g, "Workers left", 0, Color.WHITE, "After the men under arms, famine and war weariness.")
	_cell(g, "%d%%" % roundi(Economy.worker_share(n) * 100.0), 1)
	_industry.add_child(HSeparator.new())
	_industry.add_child(_heading("Imports and the blockade: raw materials"))
	var m := _grid(2)
	_industry.add_child(m)
	_cell(m, "Own deposits", 0, Color.WHITE, "Coal, iron and timber from your provinces.")
	_cell(m, Fmt.kt(mats.own), 1)
	_cell(m, "Industry needs", 0)
	_cell(m, Fmt.kt(mats.need), 1)
	if mats.imported > 0.5:
		_cell(m, "Imported", 0, Color.WHITE, "The shortfall bought abroad (up to %d%% of the need), cut by a blockade; it costs £%.1fM a month." % [roundi(Economy.cfg.materials.import_cap * 100.0), Fmt.monthly(mats.cost)])
		_cell(m, Fmt.kt(mats.imported), 1)
	if mats.exported > 0.5:
		_cell(m, "Sold abroad", 0)
		_cell(m, Fmt.kt(mats.exported), 1)
	_cell(m, "Supplied", 0, Color.WHITE, "Industry is cut by what is short, never below %d%%." % roundi(Economy.cfg.materials.floor * 100.0))
	_cell(m, "%d%%" % roundi(mats.ratio * 100.0), 1, Fmt.GOOD if mats.ratio >= 0.999 else Fmt.WARN)
	_industry.add_child(_note("Munitions, ships and buildings all draw on the same points. What your own deposits do not give is bought abroad, so only a blockade leaves industry short: keep the sea open, and hold the iron and coal."))


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
	var keepable := floori(maxf(0.0, float(b.net) / 12.0) / maxf(per_div, 0.0001))
	_army_note.text = "Up to %dk in peace. A division of 12,000 costs £%.2fM a month to keep: your monthly surplus pays for %d more. %dk are under arms now." % [roundi(cap / 1000.0), per_div, keepable, roundi(n.men_in_units / 1000.0)]
	var cost := Economy.mobilization_cost(GameState, n, n.mobilization)
	_mob_note.text = "May be between %d%% and %d%% %s. %s" % [roundi(range.x * 100.0), roundi(range.y * 100.0), "at war" if not GameState.wars_of(n.tag).is_empty() else "in peace",
			"At %d%%, once the reserve is called up, it costs about £%.1fM a month (reservists' pay and the output lost)." % [roundi(n.mobilization * 100.0), cost] if n.mobilization > 0.005 else "Each step costs reservists' pay and output: at %d%% about £%.1fM a month." % [roundi(range.y * 100.0), Economy.mobilization_cost(GameState, n, range.y)]]
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
	_cell(g, "Divisions the budget can keep", 0, Color.WHITE, "More divisions the monthly surplus would pay for, at £%.2fM a month each." % per_div)
	_cell(g, "%d more" % keepable, 1, Fmt.GOOD if keepable > 0 else Fmt.WARN)
	_cell(g, "Divisions the treasury can raise", 0, Color.WHITE, "At £%.1fM each, paid when training begins." % float(inf.cost))
	_cell(g, "%d" % floori(maxf(0.0, n.treasury) / maxf(float(inf.cost), 0.001)), 1)
	_cell(g, "Recruits ready for", 0, Color.WHITE, "The reserve, in divisions of %s. Raise the standing army to call more." % Fmt.thousands(int(inf.size)))
	_cell(g, "%d divisions" % floori(float(n.manpower) / maxf(float(inf.size), 1.0)), 1)
	var war_cost := Economy.mobilization_cost(GameState, n, 1.0)
	if war_cost > 0.01:
		_cell(g, "War chest", 0, Color.WHITE, "How long the treasury pays for full mobilization in a war (about £%.1fM a month on top of today's budget) before the state borrows." % war_cost)
		_cell(g, "%d months" % floori(maxf(0.0, n.treasury) / war_cost), 1)
	_cell(g, "Food", 0, Color.WHITE, "People the land can feed, against the population. A shortfall is imported unless blockaded.")
	_cell(g, "%s fed of %s" % [Fmt.people(b.food_production + b.food_imported), Fmt.people(b.food_need)], 1, Fmt.BAD if b.food_shortage > 0.0 else Color.WHITE)
	_cell(g, "War support", 0)
	_cell(g, "%d" % roundi(n.war_support), 1)
	_cell(g, "War weariness", 0, Color.WHITE, "A share of the workers lost to long wars; it eases in peace.")
	_cell(g, "%d%%" % roundi(n.weariness * 100.0), 1)


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_E and not event.ctrl_pressed:
		toggle()
