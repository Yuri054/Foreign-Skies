extends VBoxContainer
## The sound controls, for the main menu, the pause menu and the settings window: the music player (which piece
## is playing and how far along, previous, pause and next, a list to pick a piece from, Follow the game, Repeat) and the
## volume and mute of each sound bus. With `compact` set before it enters the tree it is the player and the music volume
## alone, for a menu that has little room. Everything goes through the Audio autoload, which saves it.

var compact := false

var _title := Label.new()
var _time := Label.new()
var _pause := Button.new()
var _list := OptionButton.new()
var _auto := CheckBox.new()
var _repeat := CheckBox.new()
var _updating := false


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	var head := Label.new()
	head.text = "Music"
	add_child(head)
	_title.add_theme_font_size_override("font_size", 16)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_title)
	_time.modulate = Fmt.DIM
	add_child(_time)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	var previous := _button("Previous", func() -> void: Audio.step_track(-1))
	_pause.focus_mode = Control.FOCUS_NONE
	_pause.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pause.pressed.connect(func() -> void: Audio.set_music_paused(not Audio.music_paused))
	var next := _button("Next", func() -> void: Audio.step_track(1))
	buttons.add_child(previous)
	buttons.add_child(_pause)
	buttons.add_child(next)
	add_child(buttons)

	if not compact:
		_list.focus_mode = Control.FOCUS_NONE
		_list.tooltip_text = "Pick a piece to play. Choosing one stops the music following the game."
		for t: Dictionary in Audio.tracks():
			_list.add_item(str(t.title))
			_list.set_item_metadata(_list.item_count - 1, t.id)
		_list.item_selected.connect(func(i: int) -> void:
			if not _updating:
				Audio.choose_track(_list.get_item_metadata(i))
		)
		add_child(_list)
		_auto.text = "Follow the game"
		_auto.focus_mode = Control.FOCUS_NONE
		_auto.tooltip_text = "The menu theme in the menus, then one set of pieces at peace and another while your nation is at war."
		_auto.toggled.connect(func(on: bool) -> void:
			if not _updating:
				Audio.set_music_auto(on)
		)
		add_child(_auto)
		_repeat.text = "Repeat this piece"
		_repeat.focus_mode = Control.FOCUS_NONE
		_repeat.toggled.connect(func(on: bool) -> void:
			if not _updating:
				Audio.set_music_repeat(on)
		)
		add_child(_repeat)

	var sound := Label.new()
	sound.text = "Sound" if not compact else "Music volume"
	add_child(sound)
	for bus: String in (["Music"] if compact else Audio.BUSES):
		add_child(_bus_row(bus))
	Audio.music_changed.connect(_sync)
	visibility_changed.connect(_sync)
	_sync()


func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(action)
	return b


## A bus's name, its volume slider and its mute box.
func _bus_row(bus: String) -> Control:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = bus
	label.custom_minimum_size = Vector2(70, 0)
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = Audio.volume(bus)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.focus_mode = Control.FOCUS_NONE
	slider.value_changed.connect(func(v: float) -> void: Audio.set_volume(bus, v))
	row.add_child(slider)
	var mute := CheckBox.new()
	mute.text = "Mute"
	mute.focus_mode = Control.FOCUS_NONE
	mute.button_pressed = Audio.is_muted(bus)
	mute.toggled.connect(func(on: bool) -> void: Audio.set_muted(bus, on))
	row.add_child(mute)
	return row


## Shows what is playing and the state of the boxes.
func _sync() -> void:
	_updating = true
	var id: String = Audio.current_track()
	_title.text = Audio.track_title(id) if not id.is_empty() else "Nothing playing"
	_pause.text = "Play" if Audio.music_paused else "Pause"
	if not compact:
		for i in _list.item_count:
			if _list.get_item_metadata(i) == id:
				_list.select(i)
		_auto.button_pressed = Audio.music_auto
		_repeat.button_pressed = Audio.music_repeat
	_updating = false
	_tick()


func _process(_delta: float) -> void:
	if is_visible_in_tree():
		_tick()


## The time into the piece.
func _tick() -> void:
	var length: float = Audio.music_length()
	_time.text = "%s / %s" % [_clock(Audio.music_position()), _clock(length)] if length > 0.0 else ""


static func _clock(seconds: float) -> String:
	var s := int(seconds)
	return "%d:%02d" % [s / 60, s % 60]
