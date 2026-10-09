extends PanelContainer
## Top HUD bar. Left: the player's flag and name, then the figures that matter (treasury with
## its monthly change, population, manpower, diplomacy points), each in its own chip with the
## detail in its tooltip. Right: buttons that open the Economy, Military and Diplomacy windows
## (lit while open), the date, Play/Pause and five speed buttons. When the screen is too narrow
## the least important chips (population, then manpower) are dropped so the clock never
## leaves the screen. Space pauses; + and - change speed.

const SPEEDS := 5
const CHIP_COLOR := Color(0.15, 0.18, 0.24, 1.0)
## Window buttons: group of the window, label, key.
const WINDOWS := [
	["economy_panel", "Economy", "E"],
	["military_panel", "Military", "M"],
	["diplomacy_panel", "Diplomacy", "F"],
]

var _flag := FlagIcon.new()
var _nation := Label.new()
var _treasury := Label.new()
var _net := Label.new()
var _population := Label.new()
var _manpower := Label.new()
var _points := Label.new()
var _chips: Dictionary = {}
var _date := Label.new()
var _pause := Button.new()
var _speed_buttons: Array[Button] = []
var _window_buttons: Dictionary = {}
var _row := HBoxContainer.new()
var _settings_button := Button.new()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.11, 0.15, 0.97)
	style.border_color = Color(0.25, 0.29, 0.36)
	style.border_width_bottom = 1
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	add_theme_stylebox_override("panel", style)

	_row.add_theme_constant_override("separation", 4)
	add_child(_row)

	# The nation.
	_flag.custom_minimum_size = Vector2(33, 22)
	var flag_box := CenterContainer.new()
	flag_box.add_child(_flag)
	_row.add_child(flag_box)
	_nation.add_theme_font_size_override("font_size", 16)
	_nation.custom_minimum_size = Vector2(60, 0)
	_row.add_child(_nation)
	_row.add_child(VSeparator.new())

	# The figures.
	var money := HBoxContainer.new()
	money.add_theme_constant_override("separation", 6)
	money.add_child(_treasury)
	money.add_child(_net)
	_chips["treasury"] = _chip(money)
	_chips["population"] = _chip(_population)
	_chips["manpower"] = _chip(_manpower)
	_chips["points"] = _chip(_points)
	for key in ["treasury", "population", "manpower", "points"]:
		_row.add_child(_chips[key])
	_chips["treasury"].tooltip_text = "Treasury (GBP millions), and what it gains or loses each month."
	_chips["population"].tooltip_text = "People living in your provinces."
	_chips["manpower"].tooltip_text = "Recruits in reserve, ready to be raised into units."
	_chips["points"].tooltip_text = "Diplomacy points. Nothing earns or spends them yet."

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.add_child(spacer)

	# Windows.
	for w: Array in WINDOWS:
		var b := Button.new()
		b.text = w[1]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.tooltip_text = "%s window (%s)" % [w[1], w[2]]
		b.pressed.connect(func() -> void: get_tree().call_group(w[0], "toggle"))
		_row.add_child(b)
		_window_buttons[w[0]] = b
	_row.add_child(VSeparator.new())

	# Time.
	# As wide as the longest date, so the bar does not shift as the days pass.
	var font := _date.get_theme_font("font")
	_date.custom_minimum_size = Vector2(ceilf(font.get_string_size("30 September 1914", HORIZONTAL_ALIGNMENT_LEFT, -1, _date.get_theme_font_size("font_size")).x) + 4.0, 0)
	_date.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_row.add_child(_date)
	_pause.custom_minimum_size = Vector2(58, 0)
	_pause.focus_mode = Control.FOCUS_NONE
	_pause.pressed.connect(Clock.toggle_pause)
	_row.add_child(_pause)
	var speeds := HBoxContainer.new()
	speeds.add_theme_constant_override("separation", 2)
	var group := ButtonGroup.new()
	for i in SPEEDS:
		var b := Button.new()
		b.text = str(i + 1)
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(22, 0)
		b.tooltip_text = "Speed %d (- and + change it)" % (i + 1)
		b.pressed.connect(func() -> void: Clock.speed = i + 1)
		speeds.add_child(b)
		_speed_buttons.append(b)
	_row.add_child(speeds)

	# The settings button, a gear, at the far right.
	_row.add_child(VSeparator.new())
	_settings_button.toggle_mode = true
	_settings_button.focus_mode = Control.FOCUS_NONE
	_settings_button.custom_minimum_size = Vector2(30, 0)
	_settings_button.tooltip_text = "Settings (F10): UI scale"
	_settings_button.pressed.connect(func() -> void: get_tree().call_group("settings_window", "toggle"))
	_settings_button.draw.connect(_draw_gear)
	_row.add_child(_settings_button)

	Clock.date_changed.connect(_refresh)
	Clock.pause_changed.connect(func(_p: bool) -> void: _refresh())
	Clock.speed_changed.connect(func(_s: int) -> void: _refresh())
	GameState.economy_updated.connect(_refresh)
	GameState.player_changed.connect(func(_t: String) -> void: _refresh())
	GameState.scenario_loaded.connect(_refresh)
	GameState.join_requested.connect(func(_d: Dictionary) -> void: _refresh())
	GameState.join_resolved.connect(func(_d: Dictionary, _j: bool) -> void: _refresh())
	GameState.peace_offered.connect(func(_o: Dictionary) -> void: _refresh())
	GameState.peace_resolved.connect(func(_o: Dictionary, _a: bool) -> void: _refresh())
	get_viewport().size_changed.connect(_fit_width)
	_bind_windows.call_deferred()
	_refresh()


## A small dark box around a figure.
func _chip(content: Control) -> PanelContainer:
	var chip := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = CHIP_COLOR
	style.set_corner_radius_all(3)
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	chip.add_theme_stylebox_override("panel", style)
	chip.add_child(content)
	chip.mouse_filter = Control.MOUSE_FILTER_PASS
	return chip


## A gear: a ring with eight teeth, centred on the settings button.
func _draw_gear() -> void:
	var c := _settings_button.size * 0.5
	var color := Color(0.85, 0.9, 1.0) if not _settings_button.disabled else Color(0.5, 0.5, 0.5)
	_settings_button.draw_arc(c, 5.0, 0.0, TAU, 24, color, 2.0)
	for i in 8:
		var a := i * TAU / 8.0
		_settings_button.draw_line(c + Vector2.from_angle(a) * 6.5, c + Vector2.from_angle(a) * 9.0, color, 2.5)


## Lights each window's button while the window is open. The windows are made after this bar,
## so this runs once everything exists.
func _bind_windows() -> void:
	for w: Array in WINDOWS:
		var node := get_tree().get_first_node_in_group(w[0])
		if node == null:
			continue
		var button: Button = _window_buttons[w[0]]
		node.visibility_changed.connect(func() -> void: button.set_pressed_no_signal(node.visible))
		button.set_pressed_no_signal(node.visible)
	var settings := get_tree().get_first_node_in_group("settings_window")
	if settings != null:
		settings.visibility_changed.connect(func() -> void: _settings_button.set_pressed_no_signal(settings.visible))


func _refresh() -> void:
	var n := GameState.get_player()
	if n:
		_flag.tag = n.tag
		_nation.text = n.display_name
		_treasury.text = "£%.1fM" % n.treasury
		_treasury.modulate = Fmt.BAD if n.treasury < 0.0 else Color.WHITE
		var net: float = n.budget.get("net", 0.0) / 12.0
		_net.text = "%+.1f" % net
		_net.modulate = Fmt.GOOD if net >= 0.0 else Fmt.BAD
		_population.text = "Pop %.1fM" % (n.population / 1_000_000.0)
		_manpower.text = "Manpower %dk" % roundi(n.manpower / 1000.0)
		_points.text = "Diplomacy %d" % roundi(n.diplomacy_points)
	else:
		_flag.tag = ""
		_nation.text = "No nation"
		_treasury.text = ""
		_net.text = ""
		_population.text = ""
		_manpower.text = ""
		_points.text = ""
	_date.text = Clock.date_string()
	var waiting := GameState.has_pending()
	_pause.text = "Waiting" if waiting else ("Play" if Clock.paused else "Pause")
	_pause.disabled = waiting
	_pause.tooltip_text = "Answer the waiting decision first." if waiting else "Space"
	for i in _speed_buttons.size():
		_speed_buttons[i].set_pressed_no_signal(i + 1 == Clock.speed)
	_fit_width.call_deferred()


## Makes the bar fit the screen's width: as it narrows, population goes, then manpower, then the
## window buttons shrink to their key letters, then diplomacy points and the nation's name go.
func _fit_width() -> void:
	if not is_inside_tree():
		return
	var available := get_viewport_rect().size.x
	for level in 5:
		_apply_level(level)
		if _row.get_combined_minimum_size().x + 16.0 <= available:
			return


func _apply_level(level: int) -> void:
	_chips["population"].visible = level < 1
	_chips["manpower"].visible = level < 2
	_chips["points"].visible = level < 4
	_nation.visible = level < 4
	for w: Array in WINDOWS:
		var b: Button = _window_buttons[w[0]]
		b.text = w[2] if level >= 3 else w[1]


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.ctrl_pressed:
		# Ctrl and + or -: the UI scale. Ctrl 0 resets it.
		match event.keycode:
			KEY_EQUAL, KEY_KP_ADD:
				UiSettings.step_scale(get_window(), 1)
			KEY_MINUS, KEY_KP_SUBTRACT:
				UiSettings.step_scale(get_window(), -1)
			KEY_0, KEY_KP_0:
				UiSettings.set_scale(get_window(), 1.0)
		return
	match event.keycode:
		KEY_SPACE:
			Clock.toggle_pause()
		KEY_EQUAL, KEY_KP_ADD:
			Clock.speed += 1
		KEY_MINUS, KEY_KP_SUBTRACT:
			Clock.speed -= 1
