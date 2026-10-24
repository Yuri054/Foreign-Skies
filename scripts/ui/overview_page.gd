class_name OverviewPage
extends PanelContainer
## The first tab of the NationScreen: how the nation stands, on one page. What is wrong comes first, then
## the figures that matter (money, industry, people, forces), the wars, and what is being worked on.
## It reads the same budget the Economy tab shows and links nowhere: the tabs are for acting.

var host: Node = null
var _box := VBoxContainer.new()


func _ready() -> void:
	add_to_group("overview_panel")
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_theme_constant_override("separation", 8)
	scroll.add_child(_box)
	add_child(scroll)
	visibility_changed.connect(func() -> void:
		if visible:
			_refresh()
	)
	GameState.economy_updated.connect(_refresh)
	GameState.armies_changed.connect(_refresh)
	GameState.fleets_changed.connect(_refresh)
	GameState.player_changed.connect(func(_t: String) -> void: _refresh())
	Clock.date_changed.connect(_refresh)


func toggle() -> void:
	if host != null:
		host.toggle_page(self)
	else:
		visible = not visible


func _heading(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Color(0.75, 0.82, 0.95))
	l.add_theme_font_size_override("font_size", 15)
	return l


func _line(text: String, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.modulate = color
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(300, 0)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


func _grid() -> GridContainer:
	var g := GridContainer.new()
	g.columns = 4
	g.add_theme_constant_override("h_separation", 24)
	g.add_theme_constant_override("v_separation", 4)
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return g


func _pair(g: GridContainer, name_text: String, value: String, color := Color.WHITE, tip := "") -> void:
	var a := Label.new()
	a.text = name_text
	a.modulate = Fmt.DIM
	a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var b := Label.new()
	b.text = value
	b.modulate = color
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	if tip != "":
		a.tooltip_text = tip
		b.tooltip_text = tip
		a.mouse_filter = Control.MOUSE_FILTER_PASS
		b.mouse_filter = Control.MOUSE_FILTER_PASS
	g.add_child(a)
	g.add_child(b)


func _clear() -> void:
	for c in _box.get_children():
		_box.remove_child(c)
		c.queue_free()


## What is wrong, worst first: the same checks the Economy tab makes, in words for a glance.
static func problems(n: Nation) -> PackedStringArray:
	var out: PackedStringArray = []
	var b: Dictionary = n.budget
	if b.is_empty():
		return out
	if n.treasury < 0.0:
		out.append("The treasury is in debt (£%.1fM): interest takes £%.1fM a month." % [-n.treasury, Fmt.monthly(b.interest)])
	elif b.net < 0.0 and n.treasury < -b.net * 0.5:
		out.append("A deficit of £%.1fM a month will empty the treasury in %d months." % [-Fmt.monthly(b.net), maxi(1, ceili(n.treasury / maxf(-Fmt.monthly(b.net), 0.01)))])
	if b.food_shortage > 0.0:
		out.append("Famine: %d%% of the food is missing." % roundi(b.food_shortage * 100.0))
	if b.materials.ratio < 0.999:
		out.append("Raw materials are short (%d%% of the need): industry is cut." % roundi(b.materials.ratio * 100.0))
	if n.blockade > 0.05:
		out.append("A blockade cuts %d%% of the imports." % roundi(n.blockade * 100.0))
	if not GameState.wars_of(n.tag).is_empty() and n.war_support <= 35.0:
		out.append("War support is %d: the people may force a peace." % roundi(n.war_support))
	return out


func _refresh() -> void:
	if not visible:
		return
	var n := GameState.get_player()
	_clear()
	if n == null or n.budget.is_empty():
		_box.add_child(_line("No nation chosen yet.", Fmt.DIM))
		return
	var b: Dictionary = n.budget

	_box.add_child(_heading("Needs your attention"))
	var list := problems(n)
	if list.is_empty():
		_box.add_child(_line("Nothing is wrong.", Fmt.GOOD))
	for p in list:
		_box.add_child(_line(p, Fmt.BAD))

	_box.add_child(HSeparator.new())
	_box.add_child(_heading("The nation"))
	var g := _grid()
	_box.add_child(g)
	var net := Fmt.monthly(b.net)
	_pair(g, "Treasury", "£%.1fM" % n.treasury, Fmt.BAD if n.treasury < 0.0 else Color.WHITE)
	_pair(g, "Population", Fmt.people(n.population))
	# A balance that rounds to nothing is shown as nothing, not as a red "-0.0".
	var level := absf(net) < 0.05
	_pair(g, "Net a month", "£%.1fM" % 0.0 if level else "£%+.1fM" % net, Color.WHITE if level else (Fmt.GOOD if net > 0.0 else Fmt.BAD))
	_pair(g, "Under arms", Fmt.people(n.men_in_units), Color.WHITE, "In armies and in training.")
	_pair(g, "Income", "£%.1fM" % Fmt.monthly(b.revenue))
	_pair(g, "Reserve", Fmt.people(n.manpower), Color.WHITE, "Recruits not yet in a unit.")
	_pair(g, "Spending", "£%.1fM" % Fmt.monthly(b.expenses))
	_pair(g, "Mobilization", "%d%%" % roundi(n.mobilization * 100.0))
	_pair(g, "Tax rate", "%d%%" % roundi(n.tax_rate * 100.0))
	_pair(g, "War support", "%d" % roundi(n.war_support), Fmt.BAD if n.war_support <= 35.0 and not GameState.wars_of(n.tag).is_empty() else Color.WHITE)
	_pair(g, "Industry", "%d points a day" % roundi(b.construction_points), Color.WHITE, "What the buildings and ships under way share.")
	_pair(g, "Prestige", "%d" % roundi(n.prestige))
	_pair(g, "Raw materials", "%d%% of the need" % roundi(b.materials.ratio * 100.0), Fmt.GOOD if b.materials.ratio >= 0.999 else Fmt.WARN)
	_pair(g, "Diplomacy points", "%d  (+%.1f a month)" % [roundi(n.diplomacy_points), Diplomacy.point_income(GameState, n.tag)])

	_box.add_child(HSeparator.new())
	_box.add_child(_heading("Europe"))
	var tension := _line("Tension %d of 100" % roundi(GameState.tension), Fmt.BAD if GameState.tension >= 70.0 else (Fmt.WARN if GameState.tension >= 45.0 else Color.WHITE))
	tension.tooltip_text = Pressure.tip(GameState)
	tension.mouse_filter = Control.MOUSE_FILTER_PASS
	_box.add_child(tension)
	var bar := ProgressBar.new()
	bar.max_value = 100.0
	bar.value = GameState.tension
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 8)
	bar.tooltip_text = tension.tooltip_text
	_box.add_child(bar)
	var stands := HBoxContainer.new()
	stands.add_theme_constant_override("separation", 6)
	for kind: String in ["calm", "rattle"]:
		var def: Dictionary = Pressure.cfg.appeals[kind]
		var button := Button.new()
		button.text = "%s (%d)" % [def.label, int(def.cost)]
		button.focus_mode = Control.FOCUS_NONE
		var block := Pressure.appeal_block(GameState, n.tag, kind)
		button.disabled = block != ""
		button.tooltip_text = "%s\nCosts %d diplomacy points; the same nation may do either again after %d days.\nTension %+d, prestige %+d%s" % [def.tip, int(def.cost), int(Pressure.cfg.appeals.wait_days), int(def.tension), int(def.prestige), (", war support %+d" % int(def.war_support)) if int(def.war_support) != 0 else ""]
		if block != "":
			button.tooltip_text = block + "\n" + button.tooltip_text
		button.pressed.connect(func() -> void:
			GameState.issue(Appeal.new(n.tag, kind))
			_refresh()
		)
		stands.add_child(button)
	_box.add_child(stands)
	for item: Dictionary in GameState.chronicle.slice(0, 4):
		var line := _line("%s  %s" % [item.date, item.title], Fmt.DIM)
		line.tooltip_text = item.text
		line.mouse_filter = Control.MOUSE_FILTER_PASS
		_box.add_child(line)

	_box.add_child(HSeparator.new())
	_box.add_child(_heading("War and peace"))
	var wars := GameState.wars_of(n.tag)
	if wars.is_empty():
		_box.add_child(_line("At peace.", Fmt.GOOD))
	else:
		for w: War in wars:
			_box.add_child(_line("At war with %s since %s." % [GameState.nations[w.other(n.tag)].display_name, w.start_date], Fmt.BAD))

	_box.add_child(HSeparator.new())
	_box.add_child(_heading("Focus"))
	var work: PackedStringArray = []
	if not n.focus.is_empty():
		work.append("National focus: %s, %d of %d days." % [Focus.find(n.tag, n.focus.id).get("name", n.focus.id), int(n.focus.days_total) - int(n.focus.days_left), int(n.focus.days_total)])
	else:
		work.append("No national focus chosen (open the Focus tab).")
	for line in work:
		_box.add_child(_line(line, Color.WHITE if not line.begins_with("No ") else Fmt.WARN))
