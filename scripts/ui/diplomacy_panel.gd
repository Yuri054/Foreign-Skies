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
var _scroll := ScrollContainer.new()
var _box := VBoxContainer.new()

var _tags: Array[String] = []
var _selected := ""
var _treaty_ids: Array[int] = []
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

	_points.tooltip_text = "Nothing earns or spends diplomacy points yet."
	left.add_child(_points)

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

	_box.add_child(_heading("War"))
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

	_box.add_child(_heading("Propose"))
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
	GameState.relations_changed.connect(_mark_dirty.unbind(2))
	GameState.treaty_changed.connect(_mark_dirty.unbind(2))
	GameState.war_changed.connect(_mark_dirty.unbind(3))
	GameState.war_support_changed.connect(_mark_dirty.unbind(2))
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
	if tag != GameState.player_tag and tag != _selected:
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
	var me: String = GameState.player_tag
	if not GameState.nations.has(me):
		return
	_points.text = "Diplomacy points: %d" % roundi(GameState.nations[me].diplomacy_points)
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


## Short tags for how a nation stands with you: war, ally, entente, guarantees, pacts.
func _status_tags(me: String, tag: String) -> String:
	var tags: PackedStringArray = []
	if GameState.at_war(me, tag):
		tags.append("WAR")
	for t in Diplomacy.treaties_between(GameState, me, tag):
		match t.kind:
			"alliance":
				tags.append("entente" if t.terms.get("entente", false) else "ally")
			"guarantee":
				tags.append("you guarantee" if t.a == me else "guarantees you")
			"nap":
				tags.append("pact")
			"passage":
				tags.append("passage" if t.b == me else "lets you cross" if t.a == tag else "")
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
	var me: String = GameState.player_tag
	var has := GameState.nations.has(_selected)
	for c in [_treaties, _cancel, _cb_picker, _cb_info, _declare, _peace, _gift_amount, _gift]:
		c.visible = has
	for b: Button in _propose_buttons.values():
		b.visible = has
	if not has:
		_detail.text = "No nation selected."
		return
	var n: Nation = GameState.nations[_selected]
	var lines: PackedStringArray = []
	var r := Diplomacy.relation(GameState, me, _selected)
	var base: float = GameState.relation_base.get(Diplomacy.pair_key(me, _selected), 0.0)
	lines.append("%s: opinion of you %+d (settles at %+d)" % [n.display_name, roundi(r), roundi(base)])
	var bloc := Diplomacy.bloc_of(GameState, _selected)
	lines.append("Bloc: %s. War support %d, mobilization %d%%, prestige %d." % [bloc if bloc != "" else "none", roundi(n.war_support), roundi(n.mobilization * 100.0), roundi(n.prestige)])
	var grievance := Diplomacy.grievance(GameState, _selected, me)
	if grievance >= 1.0:
		lines.append("They resent you (%d)." % roundi(grievance))
	if GameState.alarms.has("%s>%s" % [_selected, me]):
		lines.append("Their mobilization threatens you.")
	if GameState.alarms.has("%s>%s" % [me, _selected]):
		lines.append("Your mobilization alarms them.")
	var war := GameState.war_between(me, _selected)
	if war != null:
		lines.append("At war since %s. War score: you %+.1f." % [war.start_date, Peace.war_score(GameState, war, me)])
	_detail.text = "\n".join(lines)
	_refresh_actions()
	_fit_height.call_deferred()


func _refresh_actions() -> void:
	var me: String = GameState.player_tag
	if not GameState.nations.has(_selected):
		return
	var tag := _selected
	# Treaties between you.
	var keep := -1
	var picked := _treaties.get_selected_items()
	if not picked.is_empty() and picked[0] < _treaty_ids.size():
		keep = _treaty_ids[picked[0]]
	_treaties.clear()
	_treaty_ids.clear()
	for t in Diplomacy.treaties_between(GameState, me, tag):
		_treaties.add_item(_treaty_text(t, me))
		_treaty_ids.append(t.id)
		if t.id == keep:
			_treaties.select(_treaties.item_count - 1)
	if _treaties.item_count == 0:
		_treaties.add_item("No treaties.")
		_treaties.set_item_disabled(0, true)
	_cancel.disabled = _treaties.get_selected_items().is_empty() or _treaty_ids.is_empty()

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
		_declare.disabled = block != "" or gate != ""
		_cb_info.text = BLOCKS.get(block, "") if block != "" else _cb_cost_text(cb, gate)

	# Proposals and gifts.
	for kind: String in _propose_buttons:
		var block := Diplomacy.proposal_block(GameState, me, tag, kind)
		var b: Button = _propose_buttons[kind]
		b.disabled = block != ""
		var need: int = Diplomacy.cfg.actions.treaty_accept[kind]
		b.tooltip_text = "%s\n%s (their opinion of you %+d, needs %+d)" % [
				PROPOSALS.filter(func(p: Array) -> bool: return p[0] == kind)[0][2],
				BLOCKS.get(block, "Possible.") if block != "" else "Possible", roundi(Diplomacy.relation(GameState, tag, me)), need]
	var treasury: float = GameState.nations[me].treasury
	_gift_amount.max_value = maxf(1.0, floorf(treasury))
	_gift.disabled = treasury < 1.0


func _treaty_text(t: Treaty, me: String) -> String:
	var label: String = Diplomacy.cfg.treaties[t.kind].label
	var extra: PackedStringArray = []
	if t.terms.get("entente", false):
		extra.append("entente")
	if t.terms.get("defensive_only", false):
		extra.append("defensive only")
	if t.kind == "guarantee":
		extra.append("you guarantee them" if t.a == me else "they guarantee you")
	if t.kind == "passage":
		extra.append("they let you cross" if t.b == me else "you let them cross")
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
	if gate != "":
		text += "\n%s (now %d%%, needs %d%%)" % [BLOCKS[gate], roundi(GameState.get_player().mobilization * 100.0), roundi(Diplomacy.cfg.crisis.min_mobilization * 100.0)]
	return text


func _on_declare() -> void:
	if _cb_ids.is_empty():
		return
	var cb := _cb_ids[_cb_picker.selected]
	var name: String = GameState.nations[_selected].display_name
	if GameState.issue(DeclareWar.new(GameState.player_tag, _selected, cb)):
		_status.text = "You declared war on %s." % name
		_status.modulate = Fmt.WARN
	else:
		_status.text = "The declaration was refused."
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
	if GameState.issue(Gift.new(GameState.player_tag, _selected, amount)):
		_status.text = "You sent £%.0fM to %s." % [amount, GameState.nations[_selected].display_name]
		_status.modulate = Fmt.GOOD
	else:
		_status.text = "You cannot afford that."
		_status.modulate = Fmt.BAD
	_refresh()


func _on_cancel() -> void:
	var picked := _treaties.get_selected_items()
	if picked.is_empty() or picked[0] >= _treaty_ids.size():
		return
	if GameState.issue(CancelTreaty.new(GameState.player_tag, _treaty_ids[picked[0]])):
		_status.text = "Treaty cancelled."
		_status.modulate = Fmt.WARN
	_refresh()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F:
		toggle()
