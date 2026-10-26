extends FloatingWindow
## A crisis or event that concerns the player's nation (see Pressure): time stops, the situation is told, and
## each way to answer is a button with what it would do. The next waiting event follows.

var _box := VBoxContainer.new()
var _title := Label.new()
var _text := Label.new()
var _options := VBoxContainer.new()
var _date := Label.new()
var _decision: Dictionary = {}


func _ready() -> void:
	add_to_group("event_prompt")
	visible = false
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(440, 160)
	add_child(scroll)
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_theme_constant_override("separation", 8)
	scroll.add_child(_box)
	setup_window("Event", false, Vector2(580, 0), 0, true, Color(0.5, 0.2, 0.14))
	_date.modulate = Fmt.DIM
	_title.add_theme_font_size_override("font_size", 22)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_options.add_theme_constant_override("separation", 6)
	for c: Control in [_date, _title, _text, HSeparator.new(), _options]:
		_box.add_child(c)
	GameState.event_posted.connect(func(_d: Dictionary) -> void: _show_next())
	GameState.event_resolved.connect(func(_d: Dictionary, _o: int) -> void: _show_next())
	GameState.player_changed.connect(func(_t: String) -> void: visible = false)
	GameState.scenario_loaded.connect(func() -> void: visible = false)
	_show_next()


## Shows the oldest waiting event, or hides the prompt if there is none.
func _show_next() -> void:
	if GameState.pending_events.is_empty():
		visible = false
		_decision = {}
		return
	_decision = GameState.pending_events[0]
	var d := _decision
	_date.text = d.date
	_title.text = d.title
	_text.text = d.text
	for c in _options.get_children():
		_options.remove_child(c)
		c.queue_free()
	for i in d.options.size():
		_options.add_child(_option_block(d, i))
	visible = true
	_fit()


func _fit() -> void:
	# After the labels have wrapped to the window's width.
	await get_tree().process_frame
	await get_tree().process_frame
	_box.reset_size()
	fit_window(_box.get_combined_minimum_size().y + 12.0)


func _option_block(d: Dictionary, index: int) -> Control:
	var option: Dictionary = d.options[index]
	var block := VBoxContainer.new()
	block.add_theme_constant_override("separation", 1)
	var button := Button.new()
	button.text = option.label
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(func() -> void: _answer(index))
	block.add_child(button)
	var about := Label.new()
	about.text = option.text
	about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	about.modulate = Fmt.DIM
	block.add_child(about)
	var advice := Pressure.advisor_line(GameState, option, d.roles)
	if advice != "":
		var advisor := Label.new()
		advisor.text = "Largest effect: " + advice
		advisor.add_theme_font_size_override("font_size", 12)
		advisor.modulate = Color(0.85, 0.75, 0.5)
		advisor.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		block.add_child(advisor)
	# What the answer would do is for the mouse to ask: over the button or its description.
	var lines := Pressure.effect_lines(GameState, option, d.roles)
	var tip := "\n".join(lines) if not lines.is_empty() else "No lasting effects."
	button.tooltip_text = tip
	about.tooltip_text = tip
	about.mouse_filter = Control.MOUSE_FILTER_PASS
	return block


func _answer(index: int) -> void:
	if _decision.is_empty():
		return
	GameState.issue(AnswerEvent.new(_decision.id, index))
	_decision = {}
	_show_next()
