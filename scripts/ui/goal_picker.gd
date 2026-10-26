extends FloatingWindow
## Make a demand: choose what to ask of a nation before the crisis opens. Provinces (tick the target's provinces to ask
## for; those on your border come first) or a concession (an indemnity, a border disarmament, no new warships, or an
## end to one of the target's ties). The price in diplomacy points follows the demand; the nation then has a deadline
## to answer, and if it refuses the demand becomes the goal of a war (Crisis.press).

const PanelScript := preload("res://scripts/ui/diplomacy_panel.gd")

var _target := ""
var _kind := OptionButton.new()
var _provinces := ItemList.new()
var _province_ids: Array[int] = []
var _concession := OptionButton.new()
var _info := Label.new()
var _start := Button.new()
var _status := Label.new()
var _title := Label.new()
var _updating := false


func _ready() -> void:
	add_to_group("goal_picker")
	visible = false
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	_title.add_theme_font_size_override("font_size", 16)
	box.add_child(_title)
	var hint := Label.new()
	hint.text = "What do you ask? If it is refused, it is what a war would be for: at peace the goal costs half, everything else more."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(380, 0)
	hint.modulate = Fmt.DIM
	box.add_child(hint)
	_kind.focus_mode = Control.FOCUS_NONE
	_kind.add_item("Province claim")
	_kind.set_item_metadata(0, "provinces")
	_kind.add_item("Concession")
	_kind.set_item_metadata(1, "concession")
	_kind.tooltip_text = "A province claim wins you land; a concession is a payment, a disarmed border or the end of an alliance."
	_kind.item_selected.connect(func(_i: int) -> void: _refresh())
	box.add_child(_kind)
	_provinces.select_mode = ItemList.SELECT_MULTI
	_provinces.custom_minimum_size = Vector2(0, 150)
	_provinces.focus_mode = Control.FOCUS_NONE
	_provinces.tooltip_text = "Up to %d provinces. Each one named makes the case dearer." % int(WarGoal.cfg().max_provinces)
	_provinces.multi_selected.connect(func(_i: int, _s: bool) -> void: _refresh())
	box.add_child(_provinces)
	_concession.focus_mode = Control.FOCUS_NONE
	_concession.item_selected.connect(func(_i: int) -> void: _refresh())
	box.add_child(_concession)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.custom_minimum_size = Vector2(380, 0)
	box.add_child(_info)
	_start.focus_mode = Control.FOCUS_NONE
	_start.pressed.connect(_on_start)
	box.add_child(_start)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)
	setup_window("Make a demand", true, Vector2(420, 0), 1, true)
	GameState.player_changed.connect(func(_t: String) -> void: visible = false)


## Opens the picker against `target`.
func open(target: String) -> void:
	var me := GameState.player_tag
	if not GameState.nations.has(target) or me == "":
		return
	_target = target
	_updating = true
	_title.text = "A demand of %s" % GameState.nations[target].display_name
	_status.text = ""
	var entries: Array = []
	for id: int in GameState.nations[target].provinces:
		var border := false
		for n: int in Military.neighbors(id):
			if GameState.province_owner[n] == me:
				border = true
				break
		entries.append([id, border, Peace.province_share(GameState, id, target)])
	entries.sort_custom(func(a: Array, b: Array) -> bool:
		if a[1] != b[1]:
			return a[1]
		return a[2] > b[2])
	_provinces.clear()
	_province_ids.clear()
	for e: Array in entries:
		_provinces.add_item("%s%s  (%d%% of its weight)" % [MapData.provinces[e[0]].name, "  · on your border" if e[1] else "", roundi(e[2] * 100.0)])
		_province_ids.append(e[0])
	_concession.clear()
	var c: Dictionary = WarGoal.cfg().concession
	_concession.add_item("An indemnity (%d%% of revenue for %d months)" % [roundi(float(c.indemnity_share) * 100.0), int(c.indemnity_months)])
	_concession.set_item_metadata(0, {"kind": "indemnity", "share": c.indemnity_share, "months": c.indemnity_months})
	if not Military.border_provinces(GameState, target, me).is_empty():
		_concession.add_item("Its border armies withdrawn for %d years" % int(c.disarm_years))
		_concession.set_item_metadata(_concession.item_count - 1, {"kind": "disarm_border", "years": c.disarm_years})
	if Navy.strength_of(GameState, target) > 0.0:
		var years := int(Crisis.cfg.kinds.naval.years)
		_concession.add_item("No new warships for %d years" % years)
		_concession.set_item_metadata(_concession.item_count - 1, {"kind": "fleet_limit", "years": years})
	var partners: Array[String] = []
	for t in Diplomacy.treaties_of(GameState, target):
		if t.kind == "alliance" or t.kind == "guarantee":
			var partner := t.other(target)
			if partner != me and partner not in partners:
				partners.append(partner)
	for p in partners:
		_concession.add_item("An end to its ties with %s" % GameState.nations[p].display_name)
		_concession.set_item_metadata(_concession.item_count - 1, {"kind": "release_ally", "nation": p})
	_kind.select(0)
	_updating = false
	visible = true
	_refresh()


## The goal as chosen, or {} if the choice is not complete.
func current_goal() -> Dictionary:
	if _kind.get_item_metadata(_kind.selected) == "provinces":
		var ids: Array = []
		for i in _provinces.get_selected_items():
			ids.append(_province_ids[i])
		return WarGoal.provinces_goal(ids) if not ids.is_empty() else {}
	if _concession.item_count == 0:
		return {}
	return WarGoal.concession_goal(_concession.get_item_metadata(_concession.selected))


func _refresh() -> void:
	if _updating or _target == "":
		return
	var me := GameState.player_tag
	var provinces: bool = _kind.get_item_metadata(_kind.selected) == "provinces"
	_provinces.visible = provinces
	_concession.visible = not provinces
	var goal := current_goal()
	var block := Crisis.press_block(GameState, me, _target, true)
	if goal.is_empty():
		_info.text = "Tick the provinces to ask for." if provinces else "Choose a concession."
		_start.text = "Press the demand"
		_start.disabled = true
		return
	var invalid := Crisis.custom_problem(GameState, me, _target, {"demand": Crisis.demand_for(goal), "goal": goal})
	var cost := Crisis.press_cost(GameState, me, goal)
	var poor := not Diplomacy.can_afford(GameState, me, cost)
	_info.text = "To ask %s: %d diplomacy points. %s has %d days to answer; if it refuses, you hold a casus belli with this as the goal." % [
			Peace.describe_demand(GameState, Crisis.demand_for(goal)), int(cost), GameState.nations[_target].display_name, int(Crisis.cfg.gate.deadline_days)]
	_start.text = "Press the demand (%d)" % int(cost)
	_start.disabled = invalid != "" or block != "" or poor
	if invalid == "count":
		_status.text = "At most %d provinces." % int(WarGoal.cfg().max_provinces)
		_status.modulate = Fmt.WARN
	elif invalid == "detached":
		_status.text = "Every province must touch your land, or the others you claim, or a sea you have a coast on."
		_status.modulate = Fmt.WARN
	elif invalid == "capital":
		_status.text = "The capital cannot be claimed on its own."
		_status.modulate = Fmt.WARN
	elif invalid == "demand":
		_status.text = "That cannot be asked of them now."
		_status.modulate = Fmt.WARN
	elif block != "":
		_status.text = PanelScript.DEMAND_BLOCKS.get(block, PanelScript.BLOCKS.get(block, block))
		_status.modulate = Fmt.WARN
	elif poor:
		_status.text = "Not enough diplomacy points (need %d)." % int(cost)
		_status.modulate = Fmt.WARN
	else:
		_status.text = ""


func _on_start() -> void:
	var goal := current_goal()
	var cmd := PressDemand.new(GameState.player_tag, _target, "", {"demand": Crisis.demand_for(goal), "goal": goal})
	if GameState.issue(cmd):
		visible = false
		get_tree().call_group("diplomacy_panel", "refresh_now")
	else:
		_status.text = "That is not possible (%s)." % cmd.reason
		_status.modulate = Fmt.BAD
