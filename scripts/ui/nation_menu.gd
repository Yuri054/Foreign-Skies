extends FloatingWindow
## The menu that opens where you right-click another nation's land (when no army of yours is
## selected to give orders to; hold Shift to force it): its flag and name, who it is allied
## with and at war with, how many troops it has, and everything you can do about it: declare
## war with a casus belli, ask for peace, propose a treaty, cancel one, send a gift. Escape or a
## click elsewhere closes it.

const DiplomacyPanel := preload("res://scripts/ui/diplomacy_panel.gd")

var _tag := ""
var _flag := FlagIcon.new()
var _name := Label.new()
var _sub := Label.new()
var _lines := Label.new()
var _cb_picker := OptionButton.new()
var _declare := Button.new()
var _war_row := HBoxContainer.new()
var _peace := Button.new()
var _propose_buttons: Dictionary = {}
var _gift_amount := SpinBox.new()
var _gift := Button.new()
var _cancel_box := VBoxContainer.new()
var _open_panel := Button.new()
var _status := Label.new()
var _scroll := ScrollContainer.new()
var _box := VBoxContainer.new()
var _cb_ids: Array[String] = []
var _actions := Label.new()
var _anchor := Vector2.ZERO
var _place_at_cursor := false


func _ready() -> void:
	add_to_group("nation_menu")
	visible = false
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.custom_minimum_size = Vector2(330, 100)
	add_child(_scroll)
	setup_window("Nation", true, Vector2(370, 0), 0)
	_box.add_theme_constant_override("separation", 5)
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_box)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	_flag.custom_minimum_size = Vector2(66, 44)
	head.add_child(_flag)
	var titles := VBoxContainer.new()
	_name.add_theme_font_size_override("font_size", 20)
	_sub.modulate = Fmt.DIM
	titles.add_child(_name)
	titles.add_child(_sub)
	head.add_child(titles)
	_box.add_child(head)

	_lines.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lines.custom_minimum_size = Vector2(320, 0)
	_box.add_child(_lines)
	_box.add_child(HSeparator.new())

	_actions.modulate = Fmt.DIM
	_box.add_child(_actions)

	_cb_picker.focus_mode = Control.FOCUS_NONE
	_cb_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cb_picker.item_selected.connect(func(_i: int) -> void: _refresh_actions())
	_war_row.add_child(_cb_picker)
	_declare.text = "Declare war"
	_declare.focus_mode = Control.FOCUS_NONE
	_declare.pressed.connect(_on_declare)
	_war_row.add_child(_declare)
	_box.add_child(_war_row)
	_peace.text = "Peace talks…"
	_peace.focus_mode = Control.FOCUS_NONE
	_peace.pressed.connect(func() -> void:
		var war := GameState.war_between(GameState.player_tag, _tag)
		if war != null:
			var id := war.id
			close()
			get_tree().call_group("peace_screen", "open_war", id)
	)
	_box.add_child(_peace)

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
	_gift.focus_mode = Control.FOCUS_NONE
	_gift.pressed.connect(_on_gift)
	gift_row.add_child(_gift)
	_box.add_child(gift_row)

	_cancel_box.add_theme_constant_override("separation", 3)
	_box.add_child(_cancel_box)

	_open_panel.text = "Open in the Diplomacy panel"
	_open_panel.focus_mode = Control.FOCUS_NONE
	_open_panel.pressed.connect(func() -> void:
		var tag := _tag
		close()
		get_tree().call_group("diplomacy_panel", "show_nation", tag)
	)
	_box.add_child(_open_panel)

	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(320, 0)
	_box.add_child(_status)

	GameState.player_changed.connect(func(_t: String) -> void: close())
	GameState.scenario_loaded.connect(close)
	GameState.war_changed.connect(func(_a: String, _b: String, _w: bool) -> void:
		if visible:
			_refresh.call_deferred()
	)


## Opens the menu for a nation at a screen position.
func open_nation(tag: String, screen_pos: Vector2) -> void:
	if not GameState.nations.has(tag) or tag == GameState.player_tag:
		return
	_place_at_cursor = not visible
	_tag = tag
	_anchor = screen_pos
	_status.text = ""
	visible = true
	_refresh()


func close() -> void:
	visible = false
	_tag = ""


func _refresh() -> void:
	if _tag == "" or not GameState.nations.has(_tag):
		return
	var me: String = GameState.player_tag
	var n: Nation = GameState.nations[_tag]
	_flag.tag = _tag
	title = n.display_name
	_name.text = n.display_name
	var bloc := Diplomacy.bloc_of(GameState, _tag)
	_sub.text = "%s · %s" % [n.government.replace("_", " ").capitalize() if n.government != "" else "Government unknown", bloc if bloc != "" else "no bloc"]

	var lines: PackedStringArray = []
	var r := Diplomacy.relation(GameState, me, _tag)
	lines.append("Opinion of you: %+d" % roundi(r))
	var armies := Military.armies_of(GameState, _tag)
	lines.append("Troops: %s under arms in %d %s, %s in reserve" % [
			Fmt.people(Military.men_in_service(GameState, _tag)), armies.size(), "army" if armies.size() == 1 else "armies", Fmt.people(n.manpower)])
	lines.append("Mobilization %d%%, war support %d" % [roundi(n.mobilization * 100.0), roundi(n.war_support)])
	lines.append("Alliances: %s" % _alliances_text(n))
	var guarantees := _guarantee_text(n)
	if guarantees != "":
		lines.append(guarantees)
	lines.append("At war with: %s" % _wars_text(me))
	_lines.text = "\n".join(lines)
	_actions.text = "Actions (your diplomacy points: %d)" % roundi(GameState.nations[me].diplomacy_points)
	_refresh_actions()
	_fit.call_deferred()


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
	return "Guarantees: " + "; ".join(parts) if not parts.is_empty() else ""


func _wars_text(me: String) -> String:
	var names: PackedStringArray = []
	for w in GameState.wars_of(_tag):
		var other := w.other(_tag)
		names.append("YOU" if other == me else GameState.nations[other].display_name)
	return ", ".join(names) if not names.is_empty() else "nobody"


func _refresh_actions() -> void:
	var me: String = GameState.player_tag
	var tag := _tag
	var war := GameState.war_between(me, tag)
	var at_war := war != null
	# War or peace.
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
		_declare.disabled = block != "" or gate != ""
		var why: String = DiplomacyPanel.BLOCKS.get(block, "") if block != "" else (DiplomacyPanel.BLOCKS[gate] if gate != "" else "")
		_declare.tooltip_text = why if why != "" else _cb_cost(cb)
		_cb_picker.tooltip_text = _declare.tooltip_text
	_war_row.visible = not at_war
	_peace.visible = at_war
	# Treaties.
	for kind: String in _propose_buttons:
		var block := Diplomacy.proposal_block(GameState, me, tag, kind)
		var b: Button = _propose_buttons[kind]
		b.disabled = block != ""
		var need: int = Diplomacy.cfg.actions.treaty_accept[kind]
		var blurb: String = DiplomacyPanel.PROPOSALS.filter(func(p: Array) -> bool: return p[0] == kind)[0][2]
		b.tooltip_text = "%s\n%s (their opinion of you %+d, needs %+d)" % [blurb,
				DiplomacyPanel.BLOCKS.get(block, "") if block != "" else "Possible", roundi(Diplomacy.relation(GameState, tag, me)), need]
	var treasury: float = GameState.nations[me].treasury
	_gift_amount.max_value = maxf(1.0, floorf(treasury))
	_gift.disabled = treasury < 1.0
	# Cancel buttons for the treaties between you.
	for c in _cancel_box.get_children():
		_cancel_box.remove_child(c)
		c.queue_free()
	for t in Diplomacy.treaties_between(GameState, me, tag):
		var b := Button.new()
		b.text = "Cancel: %s" % Diplomacy.cfg.treaties[t.kind].label.to_lower()
		b.focus_mode = Control.FOCUS_NONE
		b.tooltip_text = "Tear up the treaty. It costs %s." % _cancel_cost(t.kind)
		var id: int = t.id
		b.pressed.connect(func() -> void: _on_cancel(id))
		_cancel_box.add_child(b)


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


## Fits the window to its content, and puts a newly opened one by the cursor.
func _fit() -> void:
	if not visible or not is_inside_tree():
		return
	fit_window(_box.get_combined_minimum_size().y + 4.0)
	if _place_at_cursor:
		_place_at_cursor = false
		var view := get_viewport_rect().size
		var pos := _anchor + Vector2(10, 6)
		pos.x = clampf(pos.x, 8.0, maxf(view.x - size.x - 8.0, 8.0))
		pos.y = clampf(pos.y, 48.0, maxf(view.y - size.y - 8.0, 48.0))
		position = pos


func _on_declare() -> void:
	if _cb_ids.is_empty():
		return
	var name: String = GameState.nations[_tag].display_name
	var cb := _cb_ids[_cb_picker.selected]
	if GameState.issue(DeclareWar.new(GameState.player_tag, _tag, cb)):
		_say("You declared war on %s." % name, Fmt.WARN)
	else:
		_say("The declaration was refused.", Fmt.BAD)
	_refresh()


func _on_propose(kind: String) -> void:
	var name: String = GameState.nations[_tag].display_name
	var cmd := ProposeTreaty.new(GameState.player_tag, _tag, kind)
	if not GameState.issue(cmd):
		_say(DiplomacyPanel.BLOCKS.get(cmd.result.reason, "That is not possible."), Fmt.BAD)
	elif cmd.result.accepted:
		_say("%s agrees." % name, Fmt.GOOD)
	else:
		_say("%s refuses: their opinion of you is too low." % name, Fmt.WARN)
	_refresh()


func _on_gift() -> void:
	var amount := _gift_amount.value
	if GameState.issue(Gift.new(GameState.player_tag, _tag, amount)):
		_say("You sent £%.0fM to %s." % [amount, GameState.nations[_tag].display_name], Fmt.GOOD)
	else:
		_say("You cannot afford that.", Fmt.BAD)
	_refresh()


func _on_cancel(treaty_id: int) -> void:
	if GameState.issue(CancelTreaty.new(GameState.player_tag, treaty_id)):
		_say("Treaty cancelled.", Fmt.WARN)
	_refresh()


func _say(text: String, color: Color) -> void:
	_status.text = text
	_status.modulate = color


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()
