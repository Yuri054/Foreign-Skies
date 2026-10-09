extends FloatingWindow
## The account of a battle at sea: where and when, what each side brought and lost, who holds
## the water now, and the day-by-day events. Opened by clicking the crossed swords on a sea
## zone; it follows a battle in progress and keeps the record of a finished one.

var _headline := Label.new()
var _table := GridContainer.new()
var _events := ItemList.new()
var _focus := Button.new()
var _battle_id := 0
var _zone := 0
var _cells: Array[Label] = []


func _ready() -> void:
	add_to_group("naval_battle_screen")
	visible = false
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_headline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_headline.custom_minimum_size = Vector2(360, 0)
	box.add_child(_headline)
	_table.columns = 4
	_table.add_theme_constant_override("h_separation", 14)
	box.add_child(_table)
	var title := Label.new()
	title.text = "Events"
	title.modulate = Fmt.DIM
	box.add_child(title)
	_events.custom_minimum_size = Vector2(0, 130)
	_events.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_events)
	_focus.text = "Show on map"
	_focus.focus_mode = Control.FOCUS_NONE
	_focus.pressed.connect(func() -> void:
		if _zone > 0:
			get_tree().call_group("camera_focus", "focus_on", MapData.sea_zones[_zone].center))
	box.add_child(_focus)
	add_child(box)
	setup_window("Naval battle", true, Vector2(420, 0), 3, true)
	GameState.fleets_changed.connect(_refresh)


## Shows a battle by its id (a battle in progress or one in the archive).
func open_battle(id: int) -> void:
	if id <= 0:
		return
	_battle_id = id
	visible = true
	move_to_front()
	_refresh()
	_fit.call_deferred()


func _find() -> Dictionary:
	for b: Dictionary in GameState.sea_battles.values():
		if b.id == _battle_id:
			return b
	return GameState.sea_battle_archive.get(_battle_id, {})


func _fit() -> void:
	if is_inside_tree():
		fit_window(maxf(_table.get_combined_minimum_size().y, 40.0) + 250.0)


## Squadrons each nation still has in the zone.
func _afloat(zone: int, tag: String) -> int:
	var n := 0
	for f in Navy.fleets_in_zone(GameState, zone):
		if f.tag == tag:
			n += f.ships.size()
	return n


func _refresh() -> void:
	if not visible or _battle_id == 0:
		return
	var b := _find()
	if b.is_empty():
		return
	_zone = b.zone
	var state := "in progress, day %d" % b.days if b.active else "ended %s" % b.end_date
	var head := "Battle in the %s: %s (began %s)." % [b.name, state, b.start_date]
	if not b.active and b.winner != "":
		head += " %s came off better." % GameState.nations[b.winner].display_name
	_headline.text = head
	for c in _cells:
		_table.remove_child(c)
		c.queue_free()
	_cells.clear()
	for h in ["Nation", "Brought", "Lost", "Afloat" if b.active else "Sunk"]:
		_cell(h, Fmt.DIM)
	for tag: String in b.start_ships:
		_cell(GameState.nations[tag].display_name, GameState.nations[tag].color.lightened(0.4))
		_cell("%d" % b.start_ships[tag], Color.WHITE)
		_cell("%.1f sq." % b.lost.get(tag, 0.0), Fmt.BAD if b.lost.get(tag, 0.0) > 0.5 else Color.WHITE)
		_cell("%d" % (_afloat(b.zone, tag) if b.active else b.sunk.get(tag, 0)), Color.WHITE)
	_events.clear()
	for line: String in b.events:
		_events.add_item(line)
	_events.ensure_current_is_visible()


func _cell(text: String, color: Color) -> void:
	var l := Label.new()
	l.text = text
	l.modulate = color
	_table.add_child(l)
	_cells.append(l)
