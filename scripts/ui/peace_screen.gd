extends FloatingWindow
## The peace screen. Opened from the Wars tab or the diplomacy panel, it lets the player
## draw up terms for one of their wars: demand terms from the enemy, or offer terms to
## them, and shows what the terms cost against the war score. It also shows a peace offer
## that an AI nation has made to the player, with Accept and Refuse. A cost bar compares
## the price of the terms with the score that pays for them.

var _war: War = null
var _offer: Dictionary = {}
var _incoming := false

var _title := Label.new()
var _flag_a := FlagIcon.new()
var _flag_b := FlagIcon.new()
var _score := Label.new()
var _goal := Label.new()
var _goal_button := Button.new()
var _mode := OptionButton.new()
var _compose := VBoxContainer.new()
var _provinces := ItemList.new()
var _province_ids: Array[int] = []
var _held_button := Button.new()
var _clear_button := Button.new()
var _indemnity := CheckBox.new()
var _share := HSlider.new()
var _months := HSlider.new()
var _indemnity_label := Label.new()
var _release := CheckBox.new()
var _release_picker := OptionButton.new()
var _disarm := CheckBox.new()
var _years := HSlider.new()
var _years_label := Label.new()
var _cost_bar := ProgressBar.new()
var _cost_label := Label.new()
var _result := Label.new()
var _propose := Button.new()
var _close := Button.new()
var _incoming_text := Label.new()
var _accept := Button.new()
var _refuse := Button.new()
var _incoming_row := HBoxContainer.new()
var _compose_row := HBoxContainer.new()
var _updating := false
var _box := VBoxContainer.new()


func _ready() -> void:
	add_to_group("peace_screen")
	visible = false
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(440, 160)
	add_child(scroll)
	var box := _box
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	scroll.add_child(box)
	setup_window("Peace talks", true, Vector2(600, 0), 0, true)

	_title.add_theme_font_size_override("font_size", 20)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	_flag_a.custom_minimum_size = Vector2(42, 28)
	_flag_b.custom_minimum_size = Vector2(42, 28)
	head.add_child(_flag_a)
	head.add_child(_flag_b)
	head.add_child(_title)
	box.add_child(head)
	_score.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_score)
	_goal.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_goal.modulate = Fmt.DIM
	box.add_child(_goal)

	_incoming_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_incoming_text)

	_compose.add_theme_constant_override("separation", 6)
	box.add_child(_compose)
	var mode_row := HBoxContainer.new()
	var mode_label := Label.new()
	mode_label.text = "Terms"
	mode_row.add_child(mode_label)
	_mode.add_item("Demand terms from the enemy")
	_mode.add_item("Offer terms to the enemy")
	_mode.focus_mode = Control.FOCUS_NONE
	_mode.tooltip_text = "Demand: the enemy gives up what you pick. Offer: you give up what you pick to end the war."
	_mode.item_selected.connect(func(_i: int) -> void: _rebuild_terms())
	mode_row.add_child(_mode)
	_compose.add_child(mode_row)

	var prov_title := Label.new()
	prov_title.text = "Provinces (price in war score; ground already held costs half)"
	prov_title.modulate = Fmt.DIM
	_compose.add_child(prov_title)
	_provinces.select_mode = ItemList.SELECT_MULTI
	_provinces.custom_minimum_size = Vector2(0, 170)
	_provinces.focus_mode = Control.FOCUS_NONE
	_provinces.multi_selected.connect(func(_i: int, _s: bool) -> void: _refresh_cost())
	_compose.add_child(_provinces)
	var prov_row := HBoxContainer.new()
	_held_button.text = "Select held ground"
	_held_button.focus_mode = Control.FOCUS_NONE
	_held_button.tooltip_text = "Ticks every province you already occupy: the cheapest ground to ask for."
	_held_button.pressed.connect(_select_held)
	prov_row.add_child(_held_button)
	_goal_button.text = "Select goal"
	_goal_button.focus_mode = Control.FOCUS_NONE
	_goal_button.tooltip_text = "Ticks the provinces the war is being fought for. A war goal makes its own terms half price and everything else dearer."
	_goal_button.pressed.connect(_select_goal)
	prov_row.add_child(_goal_button)
	_clear_button.text = "Clear"
	_clear_button.focus_mode = Control.FOCUS_NONE
	_clear_button.tooltip_text = "Unpick every province."
	_clear_button.pressed.connect(func() -> void:
		_provinces.deselect_all()
		_refresh_cost()
	)
	prov_row.add_child(_clear_button)
	_compose.add_child(prov_row)

	_indemnity.text = "Indemnity"
	_indemnity.focus_mode = Control.FOCUS_NONE
	_indemnity.tooltip_text = "A share of the loser's output paid to the winner each year for a number of months."
	_indemnity.toggled.connect(func(_on: bool) -> void: _refresh_cost())
	_share.min_value = 5
	_share.max_value = 50
	_share.step = 5
	_share.value = 10
	_months.min_value = 6
	_months.max_value = 60
	_months.step = 6
	_months.value = 24
	for s: HSlider in [_share, _months]:
		s.custom_minimum_size = Vector2(110, 0)
		s.focus_mode = Control.FOCUS_NONE
		s.value_changed.connect(func(_v: float) -> void: _refresh_cost())
	var ind_row := HBoxContainer.new()
	for c in [_indemnity, _share, _months, _indemnity_label]:
		ind_row.add_child(c)
	_compose.add_child(ind_row)

	_release.text = "End its ties with"
	_release.focus_mode = Control.FOCUS_NONE
	_release.tooltip_text = "Tears up the loser's treaties with the nation picked, such as an alliance or a guarantee."
	_release.toggled.connect(func(_on: bool) -> void: _refresh_cost())
	_release_picker.focus_mode = Control.FOCUS_NONE
	_release_picker.item_selected.connect(func(_i: int) -> void: _refresh_cost())
	var rel_row := HBoxContainer.new()
	rel_row.add_child(_release)
	rel_row.add_child(_release_picker)
	_compose.add_child(rel_row)

	_disarm.text = "Withdraw its border armies"
	_disarm.focus_mode = Control.FOCUS_NONE
	_disarm.tooltip_text = "The loser may keep no armies near the winner's border for the years chosen."
	_disarm.toggled.connect(func(_on: bool) -> void: _refresh_cost())
	_years.min_value = 1
	_years.max_value = 10
	_years.step = 1
	_years.value = 3
	_years.custom_minimum_size = Vector2(110, 0)
	_years.focus_mode = Control.FOCUS_NONE
	_years.value_changed.connect(func(_v: float) -> void: _refresh_cost())
	var dis_row := HBoxContainer.new()
	for c in [_disarm, _years, _years_label]:
		dis_row.add_child(c)
	_compose.add_child(dis_row)

	_cost_bar.custom_minimum_size = Vector2(0, 18)
	_cost_bar.tooltip_text = "How much of the war score the terms use. Terms that cost more than the score are refused."
	_cost_bar.show_percentage = false
	_compose.add_child(_cost_bar)
	_cost_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_compose.add_child(_cost_label)

	_result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_result)

	_compose_row.add_theme_constant_override("separation", 8)
	_propose.text = "Propose peace"
	_propose.focus_mode = Control.FOCUS_NONE
	_propose.tooltip_text = "Sends the terms. The other side accepts if it has lost enough to want peace and the terms are fair for the war score."
	_propose.pressed.connect(_on_propose)
	_compose_row.add_child(_propose)
	_close.text = "Close"
	_close.focus_mode = Control.FOCUS_NONE
	_close.pressed.connect(func() -> void: visible = false)
	_compose_row.add_child(_close)
	box.add_child(_compose_row)

	_incoming_row.add_theme_constant_override("separation", 8)
	_accept.text = "Accept"
	_accept.focus_mode = Control.FOCUS_NONE
	_accept.tooltip_text = "Ends the war on these terms."
	_accept.pressed.connect(func() -> void: _answer(true))
	_incoming_row.add_child(_accept)
	_refuse.text = "Refuse"
	_refuse.focus_mode = Control.FOCUS_NONE
	_refuse.tooltip_text = "The war goes on."
	_refuse.pressed.connect(func() -> void: _answer(false))
	_incoming_row.add_child(_refuse)
	box.add_child(_incoming_row)

	GameState.peace_offered.connect(func(_o: Dictionary) -> void: _show_next_offer())
	GameState.war_changed.connect(func(_a: String, _b: String, _w: bool) -> void:
		if visible and not _incoming and (_war == null or not _war.active()):
			visible = false
	)
	GameState.player_changed.connect(func(_t: String) -> void: visible = false)
	GameState.scenario_loaded.connect(func() -> void: visible = false)
	_set_mode_incoming(false)
	_show_next_offer()


func _fit() -> void:
	fit_window(_box.get_combined_minimum_size().y + 4.0)


## Opens the peace screen for one of the player's wars.
func open_war(war_id: int) -> void:
	for w: War in GameState.wars.values():
		if w.id == war_id and w.involves(GameState.player_tag):
			_war = w
			_offer = {}
			_set_mode_incoming(false)
			_result.text = ""
			_mode.select(0)
			_rebuild_terms()
			visible = true
			_fit.call_deferred()
			return


## Shows the oldest peace offer waiting for the player, if any.
func _show_next_offer() -> void:
	if GameState.pending_offers.is_empty():
		if _incoming:
			visible = false
		return
	var offer: Dictionary = GameState.pending_offers[0]
	var war: War = GameState.war_between(offer.from, offer.to)
	_war = war
	_offer = offer
	_set_mode_incoming(true)
	var me: String = GameState.player_tag
	var other: String = offer.from
	var other_name: String = GameState.nations[other].display_name
	_flag_a.tag = other
	_flag_b.tag = me
	_title.text = "%s proposes peace" % other_name
	var score := Peace.war_score(GameState, war, me) if war != null else 0.0
	_score.text = "War score: you %+.1f." % score
	var terms: PackedStringArray = []
	for d: Dictionary in offer.demands:
		terms.append(Peace.describe_demand(GameState, d))
	if terms.is_empty():
		_incoming_text.text = "%s offers a white peace: the war ends and everything goes back as it was." % other_name
	elif offer.taker == me:
		_incoming_text.text = "%s offers to give you %s." % [other_name, "; ".join(terms)]
	else:
		_incoming_text.text = "%s demands %s." % [other_name, "; ".join(terms)]
	if offer.forced and offer.giver == me:
		_incoming_text.text += "\nYour war support is gone or your capital is lost: you cannot refuse without cost."
	_result.text = ""
	visible = true
	_fit.call_deferred()


func _answer(accept: bool) -> void:
	if _offer.is_empty():
		return
	GameState.issue(AnswerPeace.new(_offer.id, accept))
	_offer = {}
	_show_next_offer()
	if GameState.pending_offers.is_empty():
		visible = false


func _set_mode_incoming(incoming: bool) -> void:
	_incoming = incoming
	closable = not incoming
	_compose.visible = not incoming
	_compose_row.visible = not incoming
	_incoming_row.visible = incoming
	_incoming_text.visible = incoming
	_result.visible = not incoming


# --- Composing a proposal ------------------------------------------------------------------

func _me() -> String:
	return GameState.player_tag


func _enemy() -> String:
	return _war.other(_me()) if _war != null else ""


## "demand" if the player takes terms, "offer" if the player gives them.
func _proposal_mode() -> String:
	return "demand" if _mode.selected == 0 else "offer"


## Who gives the terms (and so whose provinces can be asked for).
func _giver() -> String:
	return _enemy() if _proposal_mode() == "demand" else _me()


func _taker() -> String:
	return _me() if _proposal_mode() == "demand" else _enemy()


func _rebuild_terms() -> void:
	if _war == null:
		return
	_updating = true
	var giver := _giver()
	var taker := _taker()
	var me_name: String = GameState.nations[_me()].display_name
	var enemy_name: String = GameState.nations[_enemy()].display_name
	_flag_a.tag = _me()
	_flag_b.tag = _enemy()
	_title.text = "Peace between %s and %s" % [me_name, enemy_name]
	_goal.text = (WarGoal.line(GameState, _war) + "\n" if WarGoal.line(GameState, _war) != "" else "") + AIPeace.explain(GameState, _enemy(), _war)
	_goal.visible = _goal.text != ""
	var goal: Dictionary = _war.goal if taker == _war.a else {}
	_goal_button.disabled = goal.is_empty() or not goal.has("ids")
	var entries: Array = []
	for id: int in GameState.nations[giver].provinces:
		entries.append([id, Peace.province_price(GameState, id, taker, giver) * WarGoal.price_factor(_war, taker, {"kind": "province"}, id), GameState.province_controller[id] == taker])
	entries.sort_custom(func(a: Array, b: Array) -> bool:
		if a[2] != b[2]:
			return a[2]
		return a[1] > b[1]
	)
	_provinces.clear()
	_province_ids.clear()
	for e: Array in entries:
		var held := "held by %s" % GameState.nations[taker].display_name if e[2] else ""
		var is_goal: bool = goal.has("ids") and e[0] in goal.ids
		_provinces.add_item("%s · %.1f %s%s" % [MapData.provinces[e[0]].name, e[1], held, "  (goal)" if is_goal else ""])
		_province_ids.append(e[0])
	_indemnity.button_pressed = false
	_release.button_pressed = false
	_disarm.button_pressed = false
	_release_picker.clear()
	var partners: Array[String] = []
	for t in Diplomacy.treaties_of(GameState, giver):
		if t.kind == "alliance" or t.kind == "guarantee":
			var partner := t.other(giver)
			if partner != taker and partner not in partners:
				partners.append(partner)
	for p in partners:
		_release_picker.add_item(GameState.nations[p].display_name)
		_release_picker.set_item_metadata(_release_picker.item_count - 1, p)
	_release.disabled = partners.is_empty()
	_release_picker.disabled = partners.is_empty()
	_updating = false
	_refresh_cost()


func _select_goal() -> void:
	if _war == null or _taker() != _war.a or not _war.goal.has("ids"):
		return
	for i in _province_ids.size():
		if _province_ids[i] in _war.goal.ids:
			_provinces.select(i, false)
	_refresh_cost()


func _select_held() -> void:
	var taker := _taker()
	for i in _province_ids.size():
		if GameState.province_controller[_province_ids[i]] == taker:
			_provinces.select(i, false)
	_refresh_cost()


func _build_demands() -> Array:
	var demands: Array = []
	var ids: Array = []
	for i in _provinces.get_selected_items():
		ids.append(_province_ids[i])
	if not ids.is_empty():
		demands.append({"kind": "province", "ids": ids})
	if _indemnity.button_pressed:
		demands.append({"kind": "indemnity", "share": _share.value / 100.0, "months": int(_months.value)})
	if _release.button_pressed and _release_picker.item_count > 0:
		demands.append({"kind": "release_ally", "nation": _release_picker.get_item_metadata(_release_picker.selected)})
	if _disarm.button_pressed:
		demands.append({"kind": "disarm_border", "years": int(_years.value)})
	return demands


func _refresh_cost() -> void:
	if _updating or _war == null or _incoming:
		return
	_indemnity_label.text = "%d%% a year, %d months" % [int(_share.value), int(_months.value)]
	_years_label.text = "%d years" % int(_years.value)
	var demands := _build_demands()
	var check := Peace.check(GameState, _me(), _enemy(), _proposal_mode(), demands)
	var taker := _taker()
	var score := Peace.war_score(GameState, _war, taker)
	var parts := Peace.score_parts(GameState, _war, _me())
	_score.text = "War score: you %+.1f (ground %+.1f, capital %+.1f, battles %+.1f)." % [parts.total, parts.occupation, parts.capital, parts.battles]
	_cost_bar.max_value = maxf(score, 1.0)
	_cost_bar.value = clampf(check.cost, 0.0, maxf(score, 1.0))
	var who: String = "You" if taker == _me() else GameState.nations[taker].display_name
	if demands.is_empty():
		_cost_label.text = "A white peace: the war ends and nothing changes."
	else:
		_cost_label.text = "Terms cost %.1f of the %.1f score %s can spend." % [check.cost, maxf(score, 0.0), who.to_lower() if who != "You" else "you"]
	if check.get("forced", false) and not demands.is_empty():
		_cost_label.text += " %s has lost its capital or its will, so anything may be asked." % GameState.nations[_giver()].display_name
	var reasons := {
		"too_expensive": "The score does not pay for these terms.",
		"invalid": "One of the terms cannot be made.",
		"pending": "An offer is already waiting in this war.",
		"cooldown": "Wait before asking again.",
		"no_war": "There is no war.",
	}
	_propose.disabled = not check.ok
	if not check.ok:
		_cost_label.text += "\n" + reasons.get(check.reason, "Not possible.")
		_cost_label.modulate = Fmt.WARN
	else:
		_cost_label.modulate = Color.WHITE


func _on_propose() -> void:
	var cmd := ProposePeace.new(_me(), _enemy(), _proposal_mode(), _build_demands())
	if not GameState.issue(cmd):
		_result.text = "That proposal is not possible."
		_result.modulate = Fmt.BAD
		return
	var enemy_name: String = GameState.nations[cmd.to].display_name
	if cmd.result.accepted == true:
		_result.text = "%s accepts. The war is over." % enemy_name
		_result.modulate = Fmt.GOOD
		visible = false
	else:
		_result.text = "%s refuses." % enemy_name
		_result.modulate = Fmt.BAD
		_refresh_cost()


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and not _incoming and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		visible = false
		get_viewport().set_input_as_handled()
