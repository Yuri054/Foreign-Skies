extends Control
## Choosing which nation to play, by clicking it on the map. The map stays live underneath: a
## click on any province picks the nation that owns it, and a small panel at the right says
## who is picked and starts the game (Play, or Enter), or starts it with no nation to watch (spectator). Only the panel
## takes the mouse.

signal nation_chosen(tag: String)
signal spectate_chosen

var map_view: Node
var _tag := ""
var _flag := FlagIcon.new()
var _name := Label.new()
var _facts := Label.new()
var _play := Button.new()
var _watch := Button.new()


func _ready() -> void:
	add_to_group("nation_picker")
	# The command panel has nothing to show until a nation is picked.
	get_tree().call_group("command_panel", "_refresh")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.offset_left = -300
	panel.offset_right = -16
	panel.offset_top = 56
	panel.add_theme_stylebox_override("panel", UiTheme.map_panel())
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)

	var title := Label.new()
	title.text = GameState.scenario.name
	title.add_theme_font_size_override("font_size", 20)
	box.add_child(title)
	var blurb := Label.new()
	blurb.text = GameState.scenario.get("description", "")
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.custom_minimum_size = Vector2(260, 0)
	box.add_child(blurb)
	var hint := Label.new()
	hint.text = "Click a nation on the map to choose it."
	hint.modulate = Fmt.DIM
	box.add_child(hint)
	box.add_child(HSeparator.new())

	var head := HBoxContainer.new()
	head.add_child(_flag)
	_name.add_theme_font_size_override("font_size", 18)
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(_name)
	box.add_child(head)
	_facts.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_facts)

	_play.pressed.connect(_start)
	box.add_child(_play)
	_watch.text = "Watch as a spectator"
	_watch.tooltip_text = "Every nation is run by the computer: you watch, and may look at any nation with a right click."
	_watch.pressed.connect(func() -> void: spectate_chosen.emit())
	box.add_child(_watch)

	if map_view == null:
		map_view = get_tree().get_first_node_in_group("map_view")
	if map_view != null:
		map_view.province_selected.connect(pick_province)
	# A nation set by anything else (a loaded game, a test) ends the choosing.
	GameState.player_changed.connect(func(_t: String) -> void: queue_free(), CONNECT_ONE_SHOT)
	# Nothing is played until a nation is chosen: the scenario's own nation is only the first suggestion.
	choose(GameState.scenario.get("default_player", ""))
	get_tree().call_group("top_bar", "_refresh")


## A province was clicked: its owner is the nation picked. Sea and empty ground do nothing.
func pick_province(id: int) -> void:
	if id > 0:
		choose(GameState.province_owner[id])


func choose(tag: String) -> void:
	var n: Nation = GameState.nations.get(tag)
	if n == null:
		return
	_tag = tag
	_flag.tag = tag
	_name.text = n.display_name
	var lines: PackedStringArray = [
		"%s people, %d provinces" % [Fmt.people(n.population), n.provinces.size()],
	]
	var bloc := Diplomacy.bloc_of(GameState, tag)
	if bloc != "":
		lines.append("Bloc: %s" % bloc)
	var rank := 1
	for other: Nation in GameState.nations.values():
		if other.population > n.population:
			rank += 1
	lines.append("%s largest of %d nations by population" % [Fmt.ordinal(rank), GameState.nations.size()])
	_facts.text = "\n".join(lines)
	_play.text = "Play as %s" % n.display_name


func chosen() -> String:
	return _tag


func _start() -> void:
	if _tag != "":
		nation_chosen.emit(_tag)


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and (event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER):
		get_viewport().set_input_as_handled()
		_start()
