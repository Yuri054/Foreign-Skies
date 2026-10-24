extends FloatingWindow
## The country panel, docked on the left of the screen as in the Paradox games: one nation's
## flag, name and standing in figures (overview, economy, military, politics, raw materials,
## with its rank among all nations beside the figures that can be compared), and, for a
## nation that is not yours, everything you can do about it: declare war with a casus belli or
## ask for peace, propose a treaty, send a gift, tear up a treaty. Right-click a nation on the
## map and the panel changes to it; the Nation button beside the settings gear, or N, opens it
## on your own nation. It is a normal window as well: it can be moved, resized, minimized and
## closed, and opens in the same place each time.

const DiplomacyPanel := preload("res://scripts/ui/diplomacy_panel.gd")
const SECTION := Color(0.75, 0.82, 0.95)
## Space kept clear on the left below the top bar and above the map mode palette.
const DOCK_TOP := 40.0
const DOCK_BOTTOM := 118.0

var _picker := OptionButton.new()
var _flag := FlagIcon.new()
var _name := Label.new()
var _sub := Label.new()
var _content := VBoxContainer.new()
var _scroll := ScrollContainer.new()
var _cb_picker := OptionButton.new()
var _declare := Button.new()
var _war_row := HBoxContainer.new()
var _peace := Button.new()
var _propose_buttons: Dictionary = {}
var _gift_amount := SpinBox.new()
var _gift := Button.new()
var _gift_row := HBoxContainer.new()
var _improve := Button.new()
var _relation_label := Label.new()
var _relation_bar := Control.new()
var _bar_value := 0.0
var _bar_base := 0.0
var _cancel_box := VBoxContainer.new()
var _open_diplomacy := Button.new()
var _status := Label.new()
var _actions_box := VBoxContainer.new()
var _cb_ids: Array[String] = []
var _tags: Array[String] = []
## The nation on show; "" follows the player's.
var _chosen := ""
var _dirty := false


func _ready() -> void:
	add_to_group("nation_stats")
	visible = false

	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 4)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.custom_minimum_size = Vector2(320, 120)
	_scroll.add_child(box)
	add_child(_scroll)
	setup_window("Nation", true, Vector2(390, 0), 0)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	_flag.custom_minimum_size = Vector2(60, 40)
	head.add_child(_flag)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name.add_theme_font_size_override("font_size", 20)
	_sub.modulate = Fmt.DIM
	titles.add_child(_name)
	titles.add_child(_sub)
	head.add_child(titles)
	box.add_child(head)

	var pick := HBoxContainer.new()
	var pick_label := Label.new()
	pick_label.text = "Show"
	pick_label.modulate = Fmt.DIM
	pick.add_child(pick_label)
	_picker.focus_mode = Control.FOCUS_NONE
	_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_picker.item_selected.connect(func(i: int) -> void:
		_chosen = _tags[i] if _tags[i] != GameState.player_tag else ""
		_refresh()
	)
	pick.add_child(_picker)
	box.add_child(pick)

	_build_actions()
	box.add_child(_actions_box)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 2)
	box.add_child(_content)

	GameState.economy_updated.connect(_mark_dirty)
	GameState.war_changed.connect(_mark_dirty.unbind(3))
	GameState.treaty_changed.connect(_mark_dirty.unbind(2))
	GameState.relations_changed.connect(_mark_dirty.unbind(2))
	GameState.war_support_changed.connect(_mark_dirty.unbind(2))
	GameState.diplomacy_points_changed.connect(_mark_dirty.unbind(2))
	GameState.armies_changed.connect(_mark_dirty)
	GameState.fleets_changed.connect(_mark_dirty)
	GameState.player_changed.connect(func(_t: String) -> void:
		_chosen = ""
		_mark_dirty()
	)
	_refresh()


func toggle() -> void:
	if visible:
		close_window()
		return
	_dock()
	visible = true
	_refresh()


## Shows a nation: a right click on the map, or another window asking for it. The panel opens
## on the left if it was closed.
func show_nation(tag: String) -> void:
	if GameState.nations.has(tag):
		_chosen = "" if tag == GameState.player_tag else tag
		_status.text = ""
	if not visible:
		_dock()
		visible = true
	_refresh()


## Puts the window back in its place on the left of the screen, from below the top bar to above
## the map mode palette.
func _dock() -> void:
	var view := get_viewport_rect().size
	user_sized = false
	if minimized:
		set_minimized(false)
	size = Vector2(maxf(390.0, get_combined_minimum_size().x), maxf(view.y - DOCK_TOP - DOCK_BOTTOM, 200.0))
	position = Vector2(8.0, DOCK_TOP + 4.0)


## The nation on show.
func shown_tag() -> String:
	return _chosen if _chosen != "" and GameState.nations.has(_chosen) else GameState.player_tag


func _mark_dirty() -> void:
	if not visible or _dirty:
		return
	_dirty = true
	_refresh.call_deferred()


func _refresh() -> void:
	_dirty = false
	if not GameState.nations.has(GameState.player_tag):
		return
	var tag := shown_tag()
	var n: Nation = GameState.nations[tag]
	var mine := tag == GameState.player_tag
	title = "Nation: %s" % n.display_name
	_flag.tag = tag
	_name.text = n.display_name
	var bloc := Diplomacy.bloc_name(GameState, tag)
	_sub.text = "%s · %s%s" % [n.government.replace("_", " ").capitalize() if n.government != "" else "Government unknown",
			bloc if bloc != "" else "no bloc", " · your nation" if mine else ""]
	_fill_picker(tag)
	_actions_box.visible = not mine
	for c in _content.get_children():
		_content.remove_child(c)
		c.queue_free()

	var ranks := _ranks()
	var b := n.budget
	var at_war := GameState.wars_of(tag)

	var overview := _section("Overview")
	var capital_text := "—"
	if n.capital > 0:
		capital_text = MapData.provinces[n.capital].name
		var holder: String = GameState.province_controller[n.capital]
		if holder != tag:
			capital_text += " (held by %s)" % GameState.nations[holder].display_name
	_row(overview, "Capital", capital_text, "", Fmt.BAD if capital_text.contains("held by") else Color.WHITE)
	var held_elsewhere := 0
	var lost := 0
	for id in range(1, GameState.province_owner.size()):
		if GameState.province_controller[id] == tag and GameState.province_owner[id] != tag:
			held_elsewhere += 1
		elif GameState.province_owner[id] == tag and GameState.province_controller[id] != tag:
			lost += 1
	var provinces_text := "%d" % n.provinces.size()
	if lost > 0 or held_elsewhere > 0:
		provinces_text += "  (%d occupied, %d held abroad)" % [lost, held_elsewhere]
	_row(overview, "Provinces", provinces_text)
	_row(overview, "Population", Fmt.people(n.population), _rank(ranks.population, tag))
	var growth := Population.growth_rate(n)
	_row(overview, "Growth", "%+.1f%% a year" % (growth * 100.0), "", Fmt.BAD if growth < 0.0 else Color.WHITE)
	if n.war_dead >= 1000.0:
		_row(overview, "Lost in war", Fmt.people(n.war_dead))

	var economy := _section("Economy")
	_row(economy, "Output a month", "£%.1fM" % Fmt.monthly(b.get("gdp", 0.0)), _rank(ranks.gdp, tag))
	_row(economy, "Industry a month", "£%.1fM" % Fmt.monthly(b.get("industry", 0.0)))
	_row(economy, "Income", Fmt.money(Fmt.monthly(b.get("revenue", 0.0)), true), _rank(ranks.revenue, tag))
	_row(economy, "Spending", Fmt.money(-Fmt.monthly(b.get("expenses", 0.0)), true))
	var net: float = Fmt.monthly(b.get("net", 0.0))
	_row(economy, "Net per month", Fmt.money(net, true), "", Fmt.GOOD if net >= 0.0 else Fmt.BAD)
	_row(economy, "Treasury", "£%.1fM" % n.treasury, _rank(ranks.treasury, tag), Fmt.BAD if n.treasury < 0.0 else Color.WHITE)
	_row(economy, "Tax rate", "%d%%" % roundi(n.tax_rate * 100.0))

	var military := _section("Military")
	var armies := Military.armies_of(GameState, tag)
	if Intel.is_friend(GameState, tag):
		_row(military, "Under arms", "%s in %d %s" % [Fmt.people(Military.men_in_service(GameState, tag)), armies.size(), "army" if armies.size() == 1 else "armies"], _rank(ranks.army, tag))
	else:
		# What is known of a nation that is not yours or an ally's: a guess at its strength.
		_row(military, "Under arms", "%s men (estimate)" % Intel.estimate_text(Intel.estimate(Military.men_in_service(GameState, tag), tag.hash())), _rank(ranks.army, tag),
				Color.WHITE, "An estimate: your intelligence does not show the real figure.")
	var squadrons := int(Standings.value(GameState, tag, "navy"))
	if squadrons > 0 or n.naval_budget > 0.0:
		_row(military, "Navy", "%d %s afloat" % [squadrons, "squadron" if squadrons == 1 else "squadrons"], _rank(ranks.navy, tag))
	_row(military, "Recruit reserve", Fmt.people(n.manpower))
	_row(military, "Manpower pool", Fmt.people(b.get("manpower_pool", 0.0)))
	_row(military, "Mobilization", "%d%%" % roundi(n.mobilization * 100.0))
	_row(military, "Army upkeep", "£%.1fM a month" % Fmt.monthly(b.get("army", 0.0)))
	if n.naval_budget > 0.0:
		_row(military, "Navy upkeep", "£%.1fM a month" % Fmt.monthly(n.naval_budget))
	if n.blockade > 0.005:
		_row(military, "Blockade", "%d%% of trade cut" % roundi(n.blockade * 100.0), "", Fmt.BAD)

	var politics := _section("Politics")
	var floor_support: float = Diplomacy.cfg.war_support.floor
	var support_color := Fmt.BAD if n.war_support <= floor_support else (Fmt.WARN if n.war_support < 40.0 else Color.WHITE)
	_row(politics, "War support", "%d" % roundi(n.war_support), "", support_color,
			WarSupport.effects_text(GameState, tag) + "\nThis month so far:\n" + WarSupport.drivers_text(GameState, tag))
	_row(politics, "Prestige", "%d" % roundi(n.prestige), _rank(ranks.prestige, tag))
	_row(politics, "Diplomacy points", "%d  (+%.1f a month)" % [roundi(n.diplomacy_points), Diplomacy.point_income(GameState, tag)])
	if not mine:
		_row(politics, "Opinion of you", "%+d" % roundi(Diplomacy.relation(GameState, tag, GameState.player_tag)))
	_row(politics, "Alliances", _alliances_text(n))
	var guarantees := _guarantee_text(n)
	if guarantees != "":
		_row(politics, "Guarantees", guarantees)
	_row(politics, "At war with", _wars_text(tag, at_war), "", Fmt.BAD if not at_war.is_empty() else Color.WHITE)

	var resources := _section("Food and raw materials")
	if not b.is_empty():
		var food_balance: float = b.food_production - b.food_need
		var food_short: bool = b.food_shortage > 0.0
		_row(resources, "Food", "SHORT" if food_short else (("+" if food_balance >= 0.0 else "-") + Fmt.people(absf(food_balance))), "",
				Fmt.BAD if food_short else (Fmt.GOOD if food_balance >= 0.0 else Fmt.WARN))
		var mats: Dictionary = b.materials
		_row(resources, "Raw materials", "%d%% of the need" % roundi(mats.ratio * 100.0), "", Fmt.GOOD if mats.ratio >= 0.999 else (Fmt.WARN if mats.ratio >= 0.7 else Fmt.BAD))
	_refresh_actions(tag)


## The list of nations to pick from, with the one on show chosen.
func _fill_picker(shown: String) -> void:
	var tags: Array[String] = []
	for tag: String in GameState.nations:
		if not GameState.nations[tag].provinces.is_empty():
			tags.append(tag)
	tags.sort_custom(func(a: String, b: String) -> bool:
		return GameState.nations[a].display_name < GameState.nations[b].display_name
	)
	if tags == _tags and _picker.item_count == tags.size():
		_picker.select(_tags.find(shown))
		return
	_tags = tags
	_picker.clear()
	for tag in tags:
		_picker.add_item(GameState.nations[tag].display_name + (" (you)" if tag == GameState.player_tag else ""))
	_picker.select(_tags.find(shown))


# --- Rankings ------------------------------------------------------------------------------

## Every nation with land, by each figure that can be ranked: tag -> value, per figure.
func _ranks() -> Dictionary:
	var out := {"population": {}, "gdp": {}, "revenue": {}, "treasury": {}, "army": {}, "navy": {}, "prestige": {}}
	for tag: String in GameState.nations:
		var n: Nation = GameState.nations[tag]
		if n.provinces.is_empty():
			continue
		out.population[tag] = float(n.population)
		out.gdp[tag] = n.budget.get("gdp", 0.0)
		out.revenue[tag] = n.budget.get("revenue", 0.0)
		out.treasury[tag] = n.treasury
		out.army[tag] = Military.men_in_service(GameState, tag)
		out.navy[tag] = Standings.value(GameState, tag, "navy")
		out.prestige[tag] = n.prestige
	return out


## "#3 of 20": where a nation stands in one ranking (ties share the better place).
func _rank(values: Dictionary, tag: String) -> String:
	if not values.has(tag):
		return ""
	var better := 0
	for other: String in values:
		if values[other] > values[tag] + 0.0001:
			better += 1
	return "#%d of %d" % [better + 1, values.size()]


# --- Text ----------------------------------------------------------------------------------

func _alliances_text(n: Nation) -> String:
	var names: PackedStringArray = []
	for t in Diplomacy.treaties_of(GameState, n.tag, "alliance"):
		var partner: String = GameState.nations[t.other(n.tag)].display_name
		if t.terms.get("entente", false):
			partner += " (entente)"
		elif t.terms.get("defensive_only", false):
			partner += " (defensive)"
		names.append(partner)
	return ", ".join(names) if not names.is_empty() else "none"


func _guarantee_text(n: Nation) -> String:
	var given: PackedStringArray = []
	for tag in Diplomacy.guaranteed_by(GameState, n.tag):
		given.append(GameState.nations[tag].display_name)
	var received: PackedStringArray = []
	for tag in Diplomacy.guarantors_of(GameState, n.tag):
		received.append(GameState.nations[tag].display_name)
	var parts: PackedStringArray = []
	if not given.is_empty():
		parts.append("protects %s" % ", ".join(given))
	if not received.is_empty():
		parts.append("protected by %s" % ", ".join(received))
	return "; ".join(parts)


func _wars_text(tag: String, wars: Array[War]) -> String:
	var names: PackedStringArray = []
	for w in wars:
		var other := w.other(tag)
		names.append("YOU" if other == GameState.player_tag else GameState.nations[other].display_name)
	return ", ".join(names) if not names.is_empty() else "nobody"


# --- Building blocks -----------------------------------------------------------------------

## A heading and the three-column grid under it (label, value, rank).
func _section(text: String) -> GridContainer:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", SECTION)
	if _content.get_child_count() > 0:
		_content.add_child(HSeparator.new())
	_content.add_child(l)
	var g := GridContainer.new()
	g.columns = 3
	g.add_theme_constant_override("h_separation", 12)
	g.add_theme_constant_override("v_separation", 1)
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_child(g)
	return g


func _row(g: GridContainer, label: String, value: String, rank := "", color := Color.WHITE, tip := "") -> void:
	var l := Label.new()
	l.text = label
	l.modulate = Fmt.DIM
	if tip != "":
		l.tooltip_text = tip
		l.mouse_filter = Control.MOUSE_FILTER_PASS
	l.custom_minimum_size = Vector2(110, 0)
	g.add_child(l)
	var v := Label.new()
	v.text = value
	v.modulate = color
	if tip != "":
		v.tooltip_text = tip
		v.mouse_filter = Control.MOUSE_FILTER_PASS
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.custom_minimum_size = Vector2(140, 0)
	g.add_child(v)
	var r := Label.new()
	r.text = rank
	r.modulate = Fmt.DIM
	r.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	r.custom_minimum_size = Vector2(62, 0)
	g.add_child(r)


# --- Actions -------------------------------------------------------------------------------

func _build_actions() -> void:
	_actions_box.add_theme_constant_override("separation", 4)
	_actions_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var heading := Label.new()
	heading.text = "Actions"
	heading.add_theme_color_override("font_color", SECTION)
	_actions_box.add_child(heading)

	_cb_picker.focus_mode = Control.FOCUS_NONE
	_cb_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cb_picker.item_selected.connect(func(_i: int) -> void: _refresh_actions(shown_tag()))
	_war_row.add_child(_cb_picker)
	_declare.text = "Declare war"
	_declare.focus_mode = Control.FOCUS_NONE
	_declare.pressed.connect(_on_declare)
	_war_row.add_child(_declare)
	_actions_box.add_child(_war_row)
	_peace.text = "Peace talks…"
	_peace.focus_mode = Control.FOCUS_NONE
	_peace.pressed.connect(func() -> void:
		var war := GameState.war_between(GameState.player_tag, shown_tag())
		if war != null:
			get_tree().call_group("peace_screen", "open_war", war.id)
	)
	_actions_box.add_child(_peace)

	var grid := GridContainer.new()
	grid.columns = 2
	for p: Array in DiplomacyPanel.PROPOSALS:
		var b := Button.new()
		b.text = p[1]
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func() -> void: _on_propose(p[0]))
		grid.add_child(b)
		_propose_buttons[p[0]] = b
	_actions_box.add_child(grid)

	var gift_label := Label.new()
	gift_label.text = "Gift £M"
	_gift_row.add_child(gift_label)
	_gift_amount.min_value = 1.0
	_gift_amount.max_value = 100.0
	_gift_amount.step = 1.0
	_gift_amount.value = 5.0
	_gift_row.add_child(_gift_amount)
	_gift.text = "Send gift"
	_gift.focus_mode = Control.FOCUS_NONE
	_gift.pressed.connect(_on_gift)
	_gift_row.add_child(_gift)
	_actions_box.add_child(_gift_row)
	# Relations with the nation: the number, a gauge from hostile to friendly, and where it is heading.
	_actions_box.add_child(_relation_label)
	_relation_bar.custom_minimum_size = Vector2(0, 14)
	_relation_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_relation_bar.mouse_filter = Control.MOUSE_FILTER_PASS
	_relation_bar.draw.connect(_draw_relation_bar)
	_actions_box.add_child(_relation_bar)
	_improve.focus_mode = Control.FOCUS_NONE
	_improve.pressed.connect(_on_improve)
	_actions_box.add_child(_improve)

	_cancel_box.add_theme_constant_override("separation", 3)
	_actions_box.add_child(_cancel_box)
	_open_diplomacy.text = "Open in the Diplomacy window"
	_open_diplomacy.focus_mode = Control.FOCUS_NONE
	_open_diplomacy.pressed.connect(func() -> void: get_tree().call_group("diplomacy_panel", "show_nation", shown_tag()))
	_actions_box.add_child(_open_diplomacy)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(300, 0)
	_actions_box.add_child(_status)
	_actions_box.add_child(HSeparator.new())


func _refresh_actions(tag: String) -> void:
	var me: String = GameState.player_tag
	if tag == me:
		return
	var war := GameState.war_between(me, tag)
	var at_war := war != null
	var previous := _cb_picker.selected
	_cb_picker.clear()
	_cb_ids.clear()
	if not at_war:
		for cb in Diplomacy.casus_belli_options(GameState, me, tag):
			_cb_picker.add_item(Diplomacy.cfg.war.casus_belli[cb].label)
			_cb_ids.append(cb)
		_cb_picker.select(clampi(previous, 0, _cb_ids.size() - 1))
		var cb := _cb_ids[_cb_picker.selected]
		var block := Diplomacy.declare_block(GameState, me, tag)
		var gate := Diplomacy.declare_gate(GameState, me, cb)
		var war_cost := Diplomacy.cost_of("declare_war", cb)
		var poor := not Diplomacy.can_afford(GameState, me, war_cost)
		_declare.text = "Declare war (%d)" % int(war_cost) if war_cost > 0.0 else "Declare war"
		_declare.disabled = block != "" or gate != "" or poor
		var why: String = DiplomacyPanel.BLOCKS.get(block, "") if block != "" else (DiplomacyPanel.BLOCKS[gate] if gate != "" else ("Not enough diplomacy points (need %d, have %d)." % [int(war_cost), roundi(Diplomacy.points(GameState, me))] if poor else ""))
		_declare.tooltip_text = why if why != "" else _cb_cost(cb)
		_cb_picker.tooltip_text = _declare.tooltip_text
	_war_row.visible = not at_war
	_peace.visible = at_war
	for kind: String in _propose_buttons:
		var block := Diplomacy.proposal_block(GameState, me, tag, kind)
		var b: Button = _propose_buttons[kind]
		var cost := Diplomacy.cost_of("propose", kind)
		var poor := not Diplomacy.can_afford(GameState, me, cost)
		var entry: Array = DiplomacyPanel.PROPOSALS.filter(func(p: Array) -> bool: return p[0] == kind)[0]
		b.text = "%s (%d)" % [entry[1], int(cost)]
		b.disabled = block != "" or poor
		var need: int = Diplomacy.cfg.actions.treaty_accept[kind] - roundi(Diplomacy.prestige_pull(GameState, me))
		var verdict: String = DiplomacyPanel.BLOCKS.get(block, "") if block != "" else ("Not enough diplomacy points (need %d, have %d)." % [int(cost), roundi(Diplomacy.points(GameState, me))] if poor else "Possible")
		b.tooltip_text = "%s\nCosts %d diplomacy points (half back if refused).\n%s (their opinion of you %+d, needs %+d)" % [entry[2], int(cost), verdict,
				roundi(Diplomacy.relation(GameState, tag, me)), need]
	_refresh_relations(me, tag)
	var improve_cost := Diplomacy.cost_of("improve_relations")
	var improve_block := Diplomacy.improve_block(GameState, me, tag)
	var effort: Variant = Diplomacy.improving(GameState, me, tag)
	var improve_poor := not Diplomacy.can_afford(GameState, me, improve_cost)
	_improve.text = "Improving… (%d months left)" % effort.months_left if effort != null else "Improve relations (%d)" % int(improve_cost)
	_improve.disabled = improve_block != "" or improve_poor
	_improve.tooltip_text = (DiplomacyPanel.BLOCKS.get(improve_block, "") if improve_block != "" else ("Not enough diplomacy points (need %d, have %d)." % [int(improve_cost), roundi(Diplomacy.points(GameState, me))] if improve_poor else "")) + "\n" + "For a year, each month the two nations think better of each other (+%d, and part of it lasts). %d points; up to %d efforts at a time." % [int(Diplomacy.cfg.points.improve.monthly), int(Diplomacy.cost_of("improve_relations")), int(Diplomacy.cfg.points.improve.max_active)]
	var treasury: float = GameState.nations[me].treasury
	var gift_cost := Diplomacy.cost_of("gift")
	_gift_amount.max_value = maxf(1.0, floorf(treasury))
	_gift.text = "Send gift (%d points)" % int(gift_cost)
	_gift.disabled = treasury < 1.0 or not Diplomacy.can_afford(GameState, me, gift_cost)
	for c in _cancel_box.get_children():
		_cancel_box.remove_child(c)
		c.queue_free()
	for t in Diplomacy.treaties_between(GameState, me, tag):
		var b := Button.new()
		var cancel_points := Diplomacy.cost_of("cancel", t.kind)
		b.text = "Cancel: %s%s" % [Diplomacy.cfg.treaties[t.kind].label.to_lower(), " (%d points)" % int(cancel_points) if cancel_points > 0.0 else ""]
		b.focus_mode = Control.FOCUS_NONE
		b.disabled = not Diplomacy.can_afford(GameState, me, cancel_points)
		b.tooltip_text = "Tear up the treaty. It costs %s." % _cancel_cost(t.kind) if not b.disabled else "Not enough diplomacy points (need %d, have %d)." % [int(cancel_points), roundi(Diplomacy.points(GameState, me))]
		var id: int = t.id
		b.pressed.connect(func() -> void: _on_cancel(id))
		_cancel_box.add_child(b)


## The gauge of relations: -100 on the left, +100 on the right, the opinion filled from the middle,
## and a tick where it settles.
func _draw_relation_bar() -> void:
	var s := _relation_bar.size
	_relation_bar.draw_rect(Rect2(0, 3, s.x, 8), Color(1, 1, 1, 0.08))
	var mid := s.x * 0.5
	var x := mid + s.x * 0.5 * clampf(_bar_value / 100.0, -1.0, 1.0)
	var color := Color(0.82, 0.25, 0.22).lerp(Color(0.8, 0.8, 0.76), 1.0 - clampf(-_bar_value / 100.0, 0.0, 1.0)) if _bar_value < 0.0 			else Color(0.8, 0.8, 0.76).lerp(Color(0.25, 0.7, 0.35), clampf(_bar_value / 100.0, 0.0, 1.0))
	_relation_bar.draw_rect(Rect2(minf(mid, x), 3, absf(x - mid), 8), color)
	_relation_bar.draw_line(Vector2(mid, 0), Vector2(mid, s.y), Color(1, 1, 1, 0.5), 1.0)
	var base_x := mid + s.x * 0.5 * clampf(_bar_base / 100.0, -1.0, 1.0)
	_relation_bar.draw_line(Vector2(base_x, 1), Vector2(base_x, s.y - 1), Color(1, 1, 1, 0.85), 2.0)


## One word for how two nations stand.
static func relation_word(value: float) -> String:
	if value <= -60.0:
		return "Hostile"
	if value <= -25.0:
		return "Unfriendly"
	if value < 15.0:
		return "Neutral"
	if value < 50.0:
		return "Friendly"
	return "Close"


func _refresh_relations(me: String, tag: String) -> void:
	var value := Diplomacy.relation(GameState, me, tag)
	var base: float = GameState.relation_base.get(Diplomacy.pair_key(me, tag), 0.0)
	_bar_value = value
	_bar_base = base
	var text := "Relations: %+d  %s" % [roundi(value), relation_word(value)]
	var tail: PackedStringArray = []
	var effort: Variant = Diplomacy.improving(GameState, me, tag)
	if GameState.at_war(me, tag):
		tail.append("at war")
	if effort != null:
		tail.append("improving by %d a month, %d months left" % [int(Diplomacy.cfg.points.improve.monthly), effort.months_left])
	elif absf(value - base) >= 1.0:
		tail.append("settling %s toward %+d" % ["down" if value > base else "up", roundi(base)])
	else:
		tail.append("settles at %+d" % roundi(base))
	_relation_label.text = text + "\n" + " · ".join(tail)
	_relation_label.modulate = Fmt.BAD if value <= -25.0 else (Fmt.GOOD if value >= 25.0 else Color.WHITE)
	_relation_bar.tooltip_text = "Opinion from -100 (hostile) to +100 (close). The white tick is where it settles without any effort."
	_relation_bar.queue_redraw()


func _cb_cost(cb: String) -> String:
	var rules: Dictionary = Diplomacy.cfg.war.casus_belli[cb]
	var parts: PackedStringArray = ["their opinion %+d" % rules.target_relations]
	if rules.world_relations != 0:
		parts.append("everyone else's %+d" % rules.world_relations)
	if rules.prestige != 0:
		parts.append("prestige %+d" % rules.prestige)
	if rules.war_support != 0:
		parts.append("war support %+d" % rules.war_support)
	return "Cost: " + ", ".join(parts) + "."


func _cancel_cost(kind: String) -> String:
	var c: Dictionary = Diplomacy.cfg.war.cancel[kind]
	var parts: PackedStringArray = []
	if c.partner_relations != 0:
		parts.append("their opinion %+d" % c.partner_relations)
	if c.world_relations != 0:
		parts.append("everyone else's %+d" % c.world_relations)
	if c.prestige != 0:
		parts.append("prestige %+d" % c.prestige)
	return ", ".join(parts) if not parts.is_empty() else "nothing"


func _on_declare() -> void:
	if _cb_ids.is_empty():
		return
	var tag := shown_tag()
	var name: String = GameState.nations[tag].display_name
	var cb := _cb_ids[_cb_picker.selected]
	var cmd := DeclareWar.new(GameState.player_tag, tag, cb)
	if GameState.issue(cmd):
		_say("You declared war on %s." % name, Fmt.WARN)
	else:
		_say(DiplomacyPanel.BLOCKS["points"] if cmd.reason == "points" else "The declaration was refused.", Fmt.BAD)
	_refresh()


func _on_propose(kind: String) -> void:
	var tag := shown_tag()
	var name: String = GameState.nations[tag].display_name
	var cmd := ProposeTreaty.new(GameState.player_tag, tag, kind)
	if not GameState.issue(cmd):
		_say(DiplomacyPanel.BLOCKS.get(cmd.result.reason, "That is not possible."), Fmt.BAD)
	elif cmd.result.accepted:
		_say("%s agrees." % name, Fmt.GOOD)
	else:
		_say("%s refuses: their opinion of you is too low." % name, Fmt.WARN)
	_refresh()


func _on_gift() -> void:
	var tag := shown_tag()
	var amount := _gift_amount.value
	var cmd := Gift.new(GameState.player_tag, tag, amount)
	if GameState.issue(cmd):
		_say("You sent £%.0fM to %s." % [amount, GameState.nations[tag].display_name], Fmt.GOOD)
	else:
		_say(DiplomacyPanel.BLOCKS["points"] if cmd.reason == "points" else "You cannot afford that.", Fmt.BAD)
	_refresh()


func _on_improve() -> void:
	var tag := shown_tag()
	var cmd := ImproveRelations.new(GameState.player_tag, tag)
	if GameState.issue(cmd):
		_say("You begin to improve relations with %s." % GameState.nations[tag].display_name, Fmt.GOOD)
	else:
		_say(DiplomacyPanel.BLOCKS.get(cmd.reason, "That is not possible."), Fmt.BAD)
	_refresh()


func _on_cancel(treaty_id: int) -> void:
	if GameState.issue(CancelTreaty.new(GameState.player_tag, treaty_id)):
		_say("Treaty cancelled.", Fmt.WARN)
	_refresh()


func _say(text: String, color: Color) -> void:
	_status.text = text
	_status.modulate = color

