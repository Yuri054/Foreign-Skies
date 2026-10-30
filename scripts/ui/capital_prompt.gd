extends FloatingWindow
## The capital prompt: when the player's capital falls and the nation still holds enough to fight on (Capitulation), time
## stops and this lists the cities the government can move to, most valuable first, with what each is worth. Picking one
## moves the capital there (MoveCapital); the new capital carries half the old one's weight in war score.

var _title := Label.new()
var _flag := FlagIcon.new()
var _why := Label.new()
var _list := VBoxContainer.new()
var _box := VBoxContainer.new()


func _ready() -> void:
	add_to_group("capital_prompt")
	visible = false
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(400, 120)
	add_child(scroll)
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_theme_constant_override("separation", 8)
	scroll.add_child(_box)
	setup_window("Capital fallen", false, Vector2(500, 0), 0, true, Color(0.6, 0.18, 0.12))

	_title.add_theme_font_size_override("font_size", 22)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	_flag.custom_minimum_size = Vector2(48, 32)
	head.add_child(_flag)
	head.add_child(_title)
	_box.add_child(head)
	_why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_box.add_child(_why)
	_list.add_theme_constant_override("separation", 4)
	_box.add_child(_list)

	GameState.capital_choice_posted.connect(func(_c: Dictionary) -> void: _refresh())
	GameState.capital_moved.connect(func(_t: String, _f: int, _to: int) -> void: _refresh())
	GameState.nation_capitulated.connect(func(_t: String) -> void: _refresh())
	GameState.player_changed.connect(func(_t: String) -> void: _refresh())
	GameState.scenario_loaded.connect(_refresh)
	_refresh()


func _refresh() -> void:
	var c: Dictionary = GameState.capital_choice
	if c.is_empty() or c.tag != GameState.player_tag:
		visible = false
		return
	var n: Nation = GameState.nations[c.tag]
	_flag.tag = c.tag
	var lost: String = MapData.provinces[c.lost].name if c.lost > 0 else "the capital"
	_title.text = "%s has fallen" % lost
	_why.text = ("The enemy holds %s. %s still holds %d%% of its strength and can fight on: choose the city the "
			+ "government moves to. The new capital counts half as much as the old in war score; lose it too and the "
			+ "country may capitulate (at %d%% held by the enemy it does). Retake %s and the government goes home.") % [
			lost, n.display_name, roundi((1.0 - Capitulation.progress(GameState, c.tag)) * 100.0),
			roundi(float(Capitulation.cfg().capitulate_share) * 100.0), lost]
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	var shown := 0
	for id: int in c.candidates:
		if GameState.province_controller[id] != c.tag:
			continue
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.text = "%s   (worth %.1f)" % [MapData.provinces[id].name, Peace.province_value(GameState, id)]
		b.tooltip_text = "Move the government to %s." % MapData.provinces[id].name
		b.pressed.connect(func() -> void: GameState.issue(MoveCapital.new(c.tag, id)))
		_list.add_child(b)
		shown += 1
		if shown >= 8:
			break
	visible = true
	_fit.call_deferred()


## Sized once the wrapped text has its width (two frames on).
func _fit() -> void:
	for i in 2:
		await get_tree().process_frame
	if visible:
		fit_window(_box.get_combined_minimum_size().y + 24.0)
