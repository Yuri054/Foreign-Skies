extends FloatingWindow
## Diplomacy of the player's nation: every other nation with its opinion of you and what ties
## you, and for the one selected, its treaties and the things you can do: declare war (with a
## casus belli and its price shown), propose an alliance, guarantee, non-aggression pact or
## passage, send a gift, tear up a treaty, and open the peace screen if you are at war.
## Clicking a province on the map selects its owner. Toggle with F (D pans the map).

## Why a declaration or proposal is not possible, in words.
const BLOCKS := {
	"same": "That is your own nation.",
	"unknown": "Unknown nation.",
	"no_land": "One of you holds no land.",
	"at_war": "Already at war.",
	"allied": "You are allied.",
	"nap": "A non-aggression pact stands: cancel it first.",
	"mobilization": "A war without a cause needs more mobilization first.",
	"points": "Not enough diplomacy points.",
	"active": "You are already improving relations with them.",
	"limit": "All your efforts are in use (three at a time).",
	"maxed": "Relations cannot get any better.",
	"full": "The stock of points is full.",
	"money": "Not enough money.",
	"exists": "That treaty already stands.",
	"kind": "Unknown treaty.",
}
const PROPOSALS := [
	["alliance", "Alliance", "Bind you both to each other's defence. Needs a warm opinion and no opposed blocs."],
	["guarantee", "Guarantee", "You guarantee their borders: you will be asked to defend them if they are attacked."],
	["nap", "Non-aggression", "Neither may declare war on the other until it is cancelled."],
	["passage", "Ask passage", "Their land is opened to your armies."],
]

var _points := Label.new()
var _buy := Button.new()
var _projects := Label.new()
var _improve := Button.new()
var _perspective := Label.new()
var _back := Button.new()
var _perspective_row := VBoxContainer.new()
var _list := ItemList.new()
var _detail := Label.new()
var _treaties := ItemList.new()
var _cancel := Button.new()
var _cb_picker := OptionButton.new()
var _cb_info := Label.new()
var _declare := Button.new()
var _propose_buttons: Dictionary = {}
var _gift_amount := SpinBox.new()
var _gift := Button.new()
var _peace := Button.new()
var _status := Label.new()
var _action_labels: Array[Label] = []
var _scroll := ScrollContainer.new()
var _box := VBoxContainer.new()

var _tags: Array[String] = []
var _selected := ""
var _treaty_ids: Array[int] = []
var _treaty_kinds: Array[String] = []
var _cb_ids: Array[String] = []
var _dirty := false
const MapView := preload("res://scripts/map/map_view.gd")


func _ready() -> void:
	add_to_group("diplomacy_panel")
	visible = false

	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.custom_minimum_size = Vector2(300, 100)
	# Two panes: the nations on the left, everything about the chosen one on the right.
	var split := HSplitContainer.new()
	add_child(split)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(190, 0)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 0.8
	split.add_child(left)
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_stretch_ratio = 1.2
	split.add_child(_scroll)
	setup_window("Diplomacy", true, Vector2(700, 0), 2)
	_box.add_theme_constant_override("separation", 4)
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_box)
	get_viewport().size_changed.connect(_fit_height)

	_points.tooltip_text = "Diplomacy points are earned each month and spent on declaring war, proposing and cancelling treaties, and gifts."
	_perspective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_perspective.custom_minimum_size = Vector2(170, 0)
	_perspective.add_theme_color_override("font_color", Fmt.WARN)
	_perspective_row.add_child(_perspective)
	_back.focus_mode = Control.FOCUS_NONE
	_back.pressed.connect(func() -> void: get_tree().call_group("map_view", "set_viewpoint", ""))
	_perspective_row.add_child(_back)
	_perspective_row.visible = false
	left.add_child(_perspective_row)
	left.add_child(_points)
	_buy.focus_mode = Control.FOCUS_NONE
	_buy.pressed.connect(_on_buy)
	left.add_child(_buy)
	_projects.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_projects.custom_minimum_size = Vector2(170, 0)
	_projects.modulate = Fmt.DIM
	left.add_child(_projects)

	_list.custom_minimum_size = Vector2(0, 120)
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.focus_mode = Control.FOCUS_NONE
	_list.item_selected.connect(func(i: int) -> void:
		_selected = _tags[i]
		_refresh_detail()
	)
	left.add_child(_list)

	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.custom_minimum_size = Vector2(250, 0)
	_box.add_child(_detail)

	_box.add_child(_heading("Treaties"))
	_treaties.custom_minimum_size = Vector2(0, 46)
	_treaties.focus_mode = Control.FOCUS_NONE
	_treaties.item_selected.connect(func(_i: int) -> void: _refresh_actions())
	_box.add_child(_treaties)
	_cancel.text = "Cancel treaty"
	_cancel.focus_mode = Control.FOCUS_NONE
	_cancel.pressed.connect(_on_cancel)
	_box.add_child(_cancel)

	_action_labels.append(_heading("War"))
	_box.add_child(_action_labels.back())
	var war_row := HBoxContainer.new()
	_cb_picker.focus_mode = Control.FOCUS_NONE
	_cb_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cb_picker.item_selected.connect(func(_i: int) -> void: _refresh_actions())
	war_row.add_child(_cb_picker)
	_declare.text = "Declare war"
	_declare.focus_mode = Control.FOCUS_NONE
	_declare.pressed.connect(_on_declare)
	war_row.add_child(_declare)
	_box.add_child(war_row)
	_cb_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_cb_info.custom_minimum_size = Vector2(250, 0)
	_cb_info.modulate = Fmt.DIM
	_box.add_child(_cb_info)
	_peace.text = "Peace talks…"
	_peace.focus_mode = Control.FOCUS_NONE
	_peace.pressed.connect(_on_peace)
	_box.add_child(_peace)

	_action_labels.append(_heading("Propose"))
	_box.add_child(_action_labels.back())
	var grid := GridContainer.new()
	grid.columns = 2
	for p: Array in PROPOSALS:
		var b := Button.new()
		b.text = p[1]
		b.tooltip_text = p[2]
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func() -> void: _on_propose(p[0]))
		grid.add_child(b)
		_propose_buttons[p[0]] = b
	_box.add_child(grid)

	var gift_row := HBoxContainer.new()
	var gift_label := Label.new()
	gift_label.text = "Gift £M"
	gift_row.add_child(gift_label)
	_action_labels.append(gift_label)
	_gift_amount.min_value = 1.0
	_gift_amount.max_value = 100.0
	_gift_amount.step = 1.0
	_gift_amount.value = 5.0
	gift_row.add_child(_gift_amount)
	_gift.text = "Send gift"
	_gift.tooltip_text = "Money for goodwill: the receiver's opinion of you rises."
	_gift.focus_mode = Control.FOCUS_NONE
	_gift.pressed.connect(_on_gift)
	gift_row.add_child(_gift)
	_box.add_child(gift_row)
	_improve.focus_mode = Control.FOCUS_NONE
	_improve.pressed.connect(_on_improve)
	_box.add_child(_improve)

	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(250, 0)
	_box.add_child(_status)

	# The Diplomacy window shows the Diplomacy map while it is open.
	visibility_changed.connect(func() -> void:
		if visible:
			get_tree().call_group("map_view", "push_mode", MapView.Mode.DIPLOMACY)
		else:
			get_tree().call_group("map_view", "pop_mode", MapView.Mode.DIPLOMACY)
	)
	var view := get_tree().get_first_node_in_group("map_view")
	if view != null:
		view.viewpoint_changed.connect(_mark_dirty.unbind(1))
		view.mode_changed.connect(_mark_dirty.unbind(2))
	GameState.relations_changed.connect(_mark_dirty.unbind(2))
	GameState.treaty_changed.connect(_mark_dirty.unbind(2))
	GameState.war_changed.connect(_mark_dirty.unbind(3))
	GameState.war_support_changed.connect(_mark_dirty.unbind(2))
	GameState.diplomacy_points_changed.connect(_mark_dirty.unbind(2))
	GameState.economy_updated.connect(_mark_dirty)
	GameState.player_changed.connect(func(_t: String) -> void:
		_selected = ""
		_mark_dirty()
	)
	_refresh()


func _heading(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.modulate = Fmt.DIM
	return l


func toggle() -> void:
	visible = not visible
	if visible:
		_refresh()


## Whose point of view the window shows: the one picked with a right click in the Diplomacy
## map mode, else the player's own. Only the player's own view has actions.
func _viewpoint() -> String:
	var view := get_tree().get_first_node_in_group("map_view")
	if view != null and view.mode == MapView.Mode.DIPLOMACY:
		return view.diplomacy_viewpoint()
	return GameState.player_tag


func _acting() -> bool:
	return _viewpoint() == GameState.player_tag


## A nation as the text should call it: "you" for the player when acting, else its name.
func _who(tag: String) -> String:
	return "you" if tag == GameState.player_tag and _acting() else GameState.nations[tag].display_name


## Opens the panel on a nation (used by the right-click menu).
func show_nation(tag: String) -> void:
	if GameState.nations.has(tag) and tag != GameState.player_tag:
		_selected = tag
	if not visible:
		toggle()
	else:
		_refresh()


## The map's selected province changed: select the nation that owns it.
func set_province(id: int) -> void:
	if id <= 0 or id >= GameState.province_owner.size():
		return
	var tag: String = GameState.province_owner[id]
	if tag != _viewpoint() and tag != _selected and (tag != GameState.player_tag or not _acting()):
		_selected = tag
		if visible:
			_refresh()


## Opinions move every month and treaties rarely; refresh at most once a frame, and only
## while the panel is open.
func _mark_dirty() -> void:
	if not visible or _dirty:
		return
	_dirty = true
	_refresh.call_deferred()


func _fit_height() -> void:
	if not is_inside_tree():
		return
	fit_window(minf(_box.get_combined_minimum_size().y + 4.0, 430.0))


func _refresh() -> void:
	_dirty = false
	var player: String = GameState.player_tag
	if not GameState.nations.has(player):
		return
	var me := _viewpoint()
	var acting := me == player
	_points.text = "Diplomacy points: %d (+%.1f a month)" % [roundi(GameState.nations[player].diplomacy_points), Diplomacy.point_income(GameState, player)]
	_buy.visible = acting
	_projects.visible = acting
	if acting:
		var price := Diplomacy.purchase_price(GameState, player)
		_buy.text = "Buy %d points (£%.1fM)" % [int(Diplomacy.cfg.points.purchase.batch), price]
		var buy_block := Diplomacy.purchase_block(GameState, player)
		_buy.disabled = buy_block != ""
		_buy.tooltip_text = BLOCKS[buy_block] if buy_block != "" else "Turn money into diplomacy points. The price rises with each purchase and eases back over the months."
		var efforts: PackedStringArray = []
		for p in Diplomacy.projects_of(GameState, player):
			efforts.append("%s (%d months)" % [GameState.nations[p.to].display_name, p.months_left])
		_projects.text = "Improving relations: " + ", ".join(efforts) if not efforts.is_empty() else ""
		_projects.visible = not efforts.is_empty()
	_perspective_row.visible = not acting
	if not acting:
		_perspective.text = "Seen from %s. Right-click a nation on the map to look from there." % GameState.nations[me].display_name
		_back.text = "Back to %s" % GameState.nations[player].display_name
	var tags: Array[String] = []
	for tag: String in GameState.nations:
		if tag != me and not GameState.nations[tag].provinces.is_empty():
			tags.append(tag)
	tags.sort_custom(func(a: String, b: String) -> bool:
		return Diplomacy.relation(GameState, me, a) > Diplomacy.relation(GameState, me, b)
	)
	_tags = tags
	if _selected not in tags:
		_selected = tags[0] if not tags.is_empty() else ""
	_list.clear()
	for i in tags.size():
		var tag := tags[i]
		var n: Nation = GameState.nations[tag]
		_list.add_item("%s   %+d   %s" % [n.display_name, roundi(Diplomacy.relation(GameState, me, tag)), _status_tags(me, tag)])
		_list.set_item_custom_fg_color(i, _relation_color(Diplomacy.relation(GameState, me, tag), GameState.at_war(me, tag)))
		if tag == _selected:
			_list.select(i)
	_refresh_detail()


## Short tags for how a nation stands with the viewpoint nation: war, ally, entente,
## guarantees, pacts.
func _status_tags(me: String, tag: String) -> String:
	var tags: PackedStringArray = []
	var acting := me == GameState.player_tag
	if GameState.at_war(me, tag):
		tags.append("WAR")
	for t in Diplomacy.treaties_between(GameState, me, tag):
		match t.kind:
			"alliance":
				tags.append("entente" if t.terms.get("entente", false) else "ally")
			"guarantee":
				if acting:
					tags.append("you guarantee" if t.a == me else "guarantees you")
				else:
					tags.append("protects it" if t.a == me else "protected by it")
			"nap":
				tags.append("pact")
			"passage":
				tags.append("passage" if t.b == me else "lets it cross" if t.a == tag else "")
	return ", ".join(tags)


static func _relation_color(r: float, war: bool) -> Color:
	if war:
		return Fmt.BAD
	if r >= 25.0:
		return Fmt.GOOD
	if r <= -25.0:
		return Fmt.WARN
	return Color.WHITE


func _refresh_detail() -> void:
	var me := _viewpoint()
	var acting := _acting()
	var has := GameState.nations.has(_selected)
	_treaties.visible = has
	for c in [_cancel, _cb_picker, _cb_info, _declare, _peace, _gift_amount, _gift, _improve] + _action_labels:
		c.visible = has and acting
	for b: Button in _propose_buttons.values():
		b.visible = has and acting
	_status.visible = acting
	if not has:
		_detail.text = "No nation selected."
		return
	var n: Nation = GameState.nations[_selected]
	var lines: PackedStringArray = []
	var r := Diplomacy.relation(GameState, me, _selected)
	var base: float = GameState.relation_base.get(Diplomacy.pair_key(me, _selected), 0.0)
	lines.append("%s: opinion of %s %+d (settles at %+d)" % [n.display_name, _who(me), roundi(r), roundi(base)])
	var bloc := Diplomacy.bloc_of(GameState, _selected)
	lines.append("Bloc: %s. War support %d, mobilization %d%%, prestige %d." % [bloc if bloc != "" else "none", roundi(n.war_support), roundi(n.mobilization * 100.0), roundi(n.prestige)])
	var grievance := Diplomacy.grievance(GameState, _selected, me)
	if grievance >= 1.0:
		lines.append("They resent %s (%d)." % [_who(me), roundi(grievance)])
	if GameState.alarms.has("%s>%s" % [_selected, me]):
		lines.append("Their mobilization threatens %s." % _who(me))
	if GameState.alarms.has("%s>%s" % [me, _selected]):
		lines.append("%s mobilization alarms them." % ("Your" if acting else GameState.nations[me].display_name + "'s"))
	var effort_here: Variant = Diplomacy.improving(GameState, me, _selected)
	if effort_here != null and acting:
		lines.append("You are improving relations: %d months to go." % effort_here.months_left)
	var war := GameState.war_between(me, _selected)
	if war != null:
		lines.append("At war since %s. War score: %s %+.1f." % [war.start_date, _who(me), Peace.war_score(GameState, war, me)])
	_detail.text = "\n".join(lines)
	_refresh_actions()
	_fit_height.call_deferred()


func _refresh_actions() -> void:
	var me := _viewpoint()
	if not GameState.nations.has(_selected):
		return
	var tag := _selected
	# Treaties between the two.
	var keep := -1
	var picked := _treaties.get_selected_items()
	if not picked.is_empty() and picked[0] < _treaty_ids.size():
		keep = _treaty_ids[picked[0]]
	_treaties.clear()
	_treaty_ids.clear()
	_treaty_kinds.clear()
	for t in Diplomacy.treaties_between(GameState, me, tag):
		_treaties.add_item(_treaty_text(t, me))
		_treaty_ids.append(t.id)
		_treaty_kinds.append(t.kind)
		if t.id == keep:
			_treaties.select(_treaties.item_count - 1)
	if _treaties.item_count == 0:
		_treaties.add_item("No treaties.")
		_treaties.set_item_disabled(0, true)
	_cancel.disabled = _treaties.get_selected_items().is_empty() or _treaty_ids.is_empty()
	if not _acting():
		return
	var picked_now := _treaties.get_selected_items()
	if not picked_now.is_empty() and picked_now[0] < _treaty_kinds.size():
		var cancel_cost := Diplomacy.cost_of("cancel", _treaty_kinds[picked_now[0]])
		_cancel.text = "Cancel treaty (%d points)" % int(cancel_cost) if cancel_cost > 0.0 else "Cancel treaty"
		if not Diplomacy.can_afford(GameState, me, cancel_cost):
			_cancel.disabled = true
			_cancel.tooltip_text = "Not enough diplomacy points (need %d, have %d)." % [int(cancel_cost), roundi(Diplomacy.points(GameState, me))]
		else:
			_cancel.tooltip_text = ""
	else:
		_cancel.text = "Cancel treaty"

	# War.
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
	_cb_picker.visible = not at_war
	_declare.visible = not at_war
	_cb_info.visible = not at_war
	_peace.visible = at_war
	if not at_war:
		var cb := _cb_ids[_cb_picker.selected]
		var block := Diplomacy.declare_block(GameState, me, tag)
		var gate := Diplomacy.declare_gate(GameState, me, cb)
		var war_cost := Diplomacy.cost_of("declare_war", cb)
		var poor := not Diplomacy.can_afford(GameState, me, war_cost)
		_declare.text = "Declare war (%d)" % int(war_cost) if war_cost > 0.0 else "Declare war"
		_declare.disabled = block != "" or gate != "" or poor
		_cb_info.text = BLOCKS.get(block, "") if block != "" else _cb_cost_text(cb, gate)

	# Proposals and gifts.
	for kind: String in _propose_buttons:
		var block := Diplomacy.proposal_block(GameState, me, tag, kind)
		var b: Button = _propose_buttons[kind]
		var cost := Diplomacy.cost_of("propose", kind)
		var poor := not Diplomacy.can_afford(GameState, me, cost)
		b.text = "%s (%d)" % [PROPOSALS.filter(func(p: Array) -> bool: return p[0] == kind)[0][1], int(cost)]
		b.disabled = block != "" or poor
		var need: int = Diplomacy.cfg.actions.treaty_accept[kind]
		var verdict: String = BLOCKS.get(block, "") if block != "" else ("Not enough diplomacy points (need %d, have %d)." % [int(cost), roundi(Diplomacy.points(GameState, me))] if poor else "Possible")
		b.tooltip_text = "%s\nCosts %d diplomacy points (half back if refused).\n%s (their opinion of you %+d, needs %+d)" % [
				PROPOSALS.filter(func(p: Array) -> bool: return p[0] == kind)[0][2], int(cost), verdict,
				roundi(Diplomacy.relation(GameState, tag, me)), need]
	var improve_cost := Diplomacy.cost_of("improve_relations")
	var improve_block := Diplomacy.improve_block(GameState, me, tag)
	var effort: Variant = Diplomacy.improving(GameState, me, tag)
	var improve_poor := not Diplomacy.can_afford(GameState, me, improve_cost)
	_improve.text = "Improving… (%d months left)" % effort.months_left if effort != null else "Improve relations (%d)" % int(improve_cost)
	_improve.disabled = improve_block != "" or improve_poor
	_improve.tooltip_text = (BLOCKS.get(improve_block, "") if improve_block != "" else ("Not enough diplomacy points (need %d, have %d)." % [int(improve_cost), roundi(Diplomacy.points(GameState, me))] if improve_poor else "")) + "\n" + "For a year, each month the two nations think better of each other (+%d, and part of it lasts). %d points; up to %d efforts at a time." % [int(Diplomacy.cfg.points.improve.monthly), int(Diplomacy.cost_of("improve_relations")), int(Diplomacy.cfg.points.improve.max_active)]
	var treasury: float = GameState.nations[me].treasury
	var gift_cost := Diplomacy.cost_of("gift")
	_gift_amount.max_value = maxf(1.0, floorf(treasury))
	_gift.text = "Send gift (%d points)" % int(gift_cost)
	_gift.disabled = treasury < 1.0 or not Diplomacy.can_afford(GameState, me, gift_cost)


func _treaty_text(t: Treaty, me: String) -> String:
	var label: String = Diplomacy.cfg.treaties[t.kind].label
	var other := t.other(me)
	var extra: PackedStringArray = []
	if t.terms.get("entente", false):
		extra.append("entente")
	if t.terms.get("defensive_only", false):
		extra.append("defensive only")
	if t.kind == "guarantee":
		extra.append("%s guarantees %s" % [_who(t.a), _who(t.b)])
	if t.kind == "passage":
		extra.append("%s lets %s cross" % [_who(t.a), _who(t.b)])
	if t.end_day >= 0:
		extra.append("until %s" % Clock.date_after(t.end_day - Clock.days_elapsed))
	return label + (" (%s)" % ", ".join(extra) if not extra.is_empty() else "")


## What a declaration with this casus belli would cost, in words.
func _cb_cost_text(cb: String, gate: String) -> String:
	var rules: Dictionary = Diplomacy.cfg.war.casus_belli[cb]
	var parts: PackedStringArray = ["Their opinion %+d" % rules.target_relations]
	if rules.world_relations != 0:
		parts.append("everyone else's %+d" % rules.world_relations)
	if rules.prestige != 0:
		parts.append("prestige %+d" % rules.prestige)
	if rules.war_support != 0:
		parts.append("war support %+d" % rules.war_support)
	var text := ", ".join(parts) + "."
	if cb == "none":
		text += " Your neighbours and their guarantors will gain a claim against you."
	var points_cost := Diplomacy.cost_of("declare_war", cb)
	if points_cost > 0.0:
		text += "\nCosts %d diplomacy points%s." % [int(points_cost), "" if Diplomacy.can_afford(GameState, GameState.player_tag, points_cost) else " (you have %d)" % roundi(Diplomacy.points(GameState, GameState.player_tag))]
	if gate != "":
		text += "\n%s (now %d%%, needs %d%%)" % [BLOCKS[gate], roundi(GameState.get_player().mobilization * 100.0), roundi(Diplomacy.cfg.crisis.min_mobilization * 100.0)]
	return text


func _on_declare() -> void:
	if _cb_ids.is_empty():
		return
	var cb := _cb_ids[_cb_picker.selected]
	var name: String = GameState.nations[_selected].display_name
	var cmd := DeclareWar.new(GameState.player_tag, _selected, cb)
	if GameState.issue(cmd):
		_status.text = "You declared war on %s." % name
		_status.modulate = Fmt.WARN
	else:
		_status.text = BLOCKS["points"] if cmd.reason == "points" else "The declaration was refused."
		_status.modulate = Fmt.BAD
	_refresh()


func _on_buy() -> void:
	var cmd := BuyPoints.new(GameState.player_tag)
	if GameState.issue(cmd):
		_status.text = "You bought %d diplomacy points." % int(Diplomacy.cfg.points.purchase.batch)
		_status.modulate = Fmt.GOOD
	else:
		_status.text = BLOCKS.get(cmd.reason, "That is not possible.")
		_status.modulate = Fmt.BAD
	_refresh()


func _on_improve() -> void:
	var cmd := ImproveRelations.new(GameState.player_tag, _selected)
	if GameState.issue(cmd):
		_status.text = "You begin to improve relations with %s." % GameState.nations[_selected].display_name
		_status.modulate = Fmt.GOOD
	else:
		_status.text = BLOCKS.get(cmd.reason, "That is not possible.")
		_status.modulate = Fmt.BAD
	_refresh()


func _on_peace() -> void:
	var war := GameState.war_between(GameState.player_tag, _selected)
	if war != null:
		get_tree().call_group("peace_screen", "open_war", war.id)


func _on_propose(kind: String) -> void:
	var name: String = GameState.nations[_selected].display_name
	var cmd := ProposeTreaty.new(GameState.player_tag, _selected, kind)
	if not GameState.issue(cmd):
		_status.text = BLOCKS.get(cmd.result.reason, "That is not possible.")
		_status.modulate = Fmt.BAD
	elif cmd.result.accepted:
		_status.text = "%s agrees." % name
		_status.modulate = Fmt.GOOD
	else:
		_status.text = "%s refuses: their opinion of you is too low." % name
		_status.modulate = Fmt.WARN
	_refresh()


func _on_gift() -> void:
	var amount := _gift_amount.value
	var cmd := Gift.new(GameState.player_tag, _selected, amount)
	if GameState.issue(cmd):
		_status.text = "You sent £%.0fM to %s." % [amount, GameState.nations[_selected].display_name]
		_status.modulate = Fmt.GOOD
	else:
		_status.text = BLOCKS["points"] if cmd.reason == "points" else "You cannot afford that."
		_status.modulate = Fmt.BAD
	_refresh()


func _on_cancel() -> void:
	var picked := _treaties.get_selected_items()
	if picked.is_empty() or picked[0] >= _treaty_ids.size():
		return
	var cmd := CancelTreaty.new(GameState.player_tag, _treaty_ids[picked[0]])
	if GameState.issue(cmd):
		_status.text = "Treaty cancelled."
		_status.modulate = Fmt.WARN
	elif cmd.reason == "points":
		_status.text = BLOCKS["points"]
		_status.modulate = Fmt.BAD
	_refresh()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F:
		toggle()
