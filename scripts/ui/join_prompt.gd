extends FloatingWindow
## The join prompt: when an ally, a guarantee or an entente asks the player's nation to enter
## a war, time stops and this shows who is fighting whom, what joining would cost and what
## staying out would cost. Join or Stay out answers it; the next waiting decision follows.

var _title := Label.new()
var _flag := FlagIcon.new()
var _why := Label.new()
var _join_text := Label.new()
var _stay_text := Label.new()
var _join := Button.new()
var _stay := Button.new()
var _decision: Dictionary = {}
var _box := VBoxContainer.new()


func _ready() -> void:
	add_to_group("join_prompt")
	visible = false
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(400, 120)
	add_child(scroll)
	var box := _box
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)
	scroll.add_child(box)
	setup_window("Decision", false, Vector2(540, 0), 0, true, Color(0.55, 0.4, 0.12))

	_title.add_theme_font_size_override("font_size", 22)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	_flag.custom_minimum_size = Vector2(48, 32)
	head.add_child(_flag)
	head.add_child(_title)
	box.add_child(head)
	for l: Label in [_why, _join_text, _stay_text]:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(l)
	_join_text.modulate = Fmt.WARN
	_stay_text.modulate = Fmt.DIM

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_join.focus_mode = Control.FOCUS_NONE
	_join.pressed.connect(func() -> void: _answer(true))
	row.add_child(_join)
	_stay.text = "Stay out"
	_stay.focus_mode = Control.FOCUS_NONE
	_stay.pressed.connect(func() -> void: _answer(false))
	row.add_child(_stay)
	box.add_child(row)

	GameState.join_requested.connect(func(_d: Dictionary) -> void: _show_next())
	GameState.player_changed.connect(func(_t: String) -> void: visible = false)
	GameState.scenario_loaded.connect(func() -> void: visible = false)
	_show_next()


## Shows the oldest waiting decision, or hides the prompt if there is none.
func _show_next() -> void:
	if GameState.pending_joins.is_empty():
		visible = false
		_decision = {}
		return
	_decision = GameState.pending_joins[0]
	var d := _decision
	_flag.tag = d.ally
	var ally: String = GameState.nations[d.ally].display_name
	var names: PackedStringArray = []
	for e: String in d.enemies:
		names.append(GameState.nations[e].display_name)
	var enemies := ", ".join(names)
	match d.kind:
		"guarantee":
			_title.text = "%s has been attacked" % ally
			_why.text = "You guarantee %s. If you honour it you go to war with %s." % [ally, enemies]
		"alliance_defence":
			_title.text = "Your ally %s has been attacked" % ally
			_why.text = "Your alliance binds you to its defence against %s." % enemies
		"alliance_called":
			_title.text = "%s calls you to arms" % ally
			_why.text = "Your ally %s is at war with %s and asks you to fight beside it." % [ally, enemies]
		_:
			_title.text = "%s asks for your help" % ally
			_why.text = "You are friends, not bound: joining means war with %s, staying out costs nothing." % enemies
	var jc: Dictionary = d.join_cost
	var join_parts: PackedStringArray = ["War with %s" % enemies, "their opinion of you %+d" % jc.target_relations]
	if jc.prestige != 0:
		join_parts.append("prestige %+d" % jc.prestige)
	if jc.war_support != 0:
		join_parts.append("war support %+d" % jc.war_support)
	_join_text.text = "If you join: " + ", ".join(join_parts) + "."
	var dc: Dictionary = d.decline_cost
	if d.kind == "entente":
		_stay_text.text = "If you stay out: nothing changes."
	elif d.conflict:
		_stay_text.text = "You could not join without fighting a friend or a treaty partner, so staying out is free."
	else:
		var stay_parts: PackedStringArray = ["%s's opinion of you %+d" % [ally, dc.ally_relations], "prestige %+d" % dc.prestige]
		if dc.end_treaty:
			stay_parts.append("the treaty ends")
		_stay_text.text = "If you stay out: " + ", ".join(stay_parts) + "."
	_join.text = "Join the war"
	_join.disabled = d.conflict
	visible = true
	fit_window(_box.get_combined_minimum_size().y + 4.0)


func _answer(joins: bool) -> void:
	if _decision.is_empty():
		return
	GameState.issue(AnswerJoin.new(_decision.id, joins))
	_decision = {}
	_show_next()
