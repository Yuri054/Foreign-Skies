extends FloatingWindow
## The detailed account of one battle, in progress or finished: both sides' strength, losses,
## morale, generals, armies and composition; how morale changed day by day; and what happened. Opened by clicking a battle's icon on the map or an entry in the Wars tab
## of the Military panel. A battle in progress updates every day while the screen is open.

const BattleChart := preload("res://scripts/ui/battle_chart.gd")

var _battle_id := 0
var _title := Label.new()
var _status := Label.new()
var _sides := HBoxContainer.new()
var _staff := Label.new()
var _morale_chart := BattleChart.new()
var _events := ItemList.new()
var _map_button := Button.new()


func _ready() -> void:
	add_to_group("battle_screen")
	visible = false
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(560, 160)
	add_child(scroll)
	setup_window("Battle", true, Vector2(800, 540), 0, true, Color(0.45, 0.2, 0.2))
	closed.connect(func() -> void: _battle_id = 0)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	scroll.add_child(box)

	var header := HBoxContainer.new()
	_title.add_theme_font_size_override("font_size", 20)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title)
	box.add_child(header)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)
	box.add_child(HSeparator.new())

	_sides.add_theme_constant_override("separation", 14)
	box.add_child(_sides)
	_staff.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_staff.custom_minimum_size = Vector2(500, 0)
	box.add_child(_staff)
	box.add_child(HSeparator.new())
	box.add_child(_morale_chart)
	var events_title := Label.new()
	events_title.text = "What happened"
	box.add_child(events_title)
	_events.custom_minimum_size = Vector2(0, 110)
	_events.focus_mode = Control.FOCUS_NONE
	_events.auto_height = false
	_events.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_events)
	var buttons := HBoxContainer.new()
	_map_button.text = "Show on map"
	_map_button.focus_mode = Control.FOCUS_NONE
	_map_button.pressed.connect(_show_on_map)
	buttons.add_child(_map_button)
	box.add_child(buttons)

	GameState.armies_changed.connect(func() -> void:
		if visible:
			_refresh()
	)
	GameState.scenario_loaded.connect(close_screen)


## Opens the screen on a battle (by id) and brings it up to date.
func open_battle(id: int) -> void:
	if GameState.battle_by_id(id).is_empty():
		return
	_battle_id = id
	visible = true
	_refresh()


func close_screen() -> void:
	visible = false
	_battle_id = 0


func _show_on_map() -> void:
	var battle := GameState.battle_by_id(_battle_id)
	if not battle.is_empty():
		get_tree().call_group("camera_focus", "focus_on", MapData.provinces[battle.province].center)


func _refresh() -> void:
	var battle := GameState.battle_by_id(_battle_id)
	if battle.is_empty():
		close_screen()
		return
	var terrain: String = Military.cfg.terrain[battle.terrain].name.to_lower()
	_title.text = "Battle of %s" % battle.name
	var days: int = battle.days if not battle.active else Clock.days_elapsed - battle.start_day + 1
	if battle.active:
		_status.text = "In progress: day %d, fought on %s ground since %s." % [days, terrain, battle.start_date]
		_status.modulate = Fmt.WARN
	else:
		var result := "%s won." % GameState.nations[battle.winner].display_name if not battle.winner.is_empty() else "No side won."
		_status.text = "Ended %s after %d day%s, fought on %s ground since %s. %s" % [
				battle.end_date, days, "" if days == 1 else "s", terrain, battle.start_date, result]
		_status.modulate = Color.WHITE
	_map_button.disabled = false
	_rebuild_sides(battle)
	_staff.text = staff_report(battle)
	_staff.visible = _staff.text != ""
	_update_charts(battle)
	_events.clear()
	for line: String in battle.events:
		_events.add_item(line)
	if _events.item_count > 0:
		_events.ensure_current_is_visible()


## The staff's report on a battle in progress that the player is in: how it is going, and what would change it. Each
## "what if" is worked out by Military.battle_forecast with the same rules the fighting uses. "" when the player is not
## in the battle or it is over.
func staff_report(battle: Dictionary) -> String:
	var me := GameState.player_tag
	if not battle.active or not battle.sides.has(me):
		return ""
	var now := Military.battle_forecast(GameState, battle.province)
	if not now.ok or not now.sides.has(me):
		return ""
	var foe := ""
	for tag: String in now.sides:
		if tag != me:
			foe = tag
	if foe == "":
		return ""
	var ours: Dictionary = now.sides[me]
	var theirs: Dictionary = now.sides[foe]
	var lines: PackedStringArray = []
	var ratio: float = theirs.rate / maxf(ours.rate, 0.0001)
	var verdict := "favours you" if ratio > 1.3 else ("goes against you" if ratio < 0.77 else "is even")
	lines.append("Staff report: the battle %s. Each day you lose about %s men (%.1f%%), the enemy %s (%.1f%%)." % [verdict, Fmt.people(ours.loss), ours.rate * 100.0, Fmt.people(theirs.loss), theirs.rate * 100.0])
	if ours.half_days < INF and theirs.half_days < INF:
		lines.append("At this rate you are half your strength in %d days, the enemy in %d." % [ceili(ours.half_days), ceili(theirs.half_days)])
	var ideas: PackedStringArray = []
	var more := Military.battle_forecast(GameState, battle.province, {"power": {me: 1.25}})
	if more.ok:
		ideas.append("a quarter more fighting power would raise the enemy's daily loss by %d%%" % roundi(100.0 * (more.sides[foe].loss / maxf(theirs.loss, 1.0) - 1.0)))
	var weaker := Military.battle_forecast(GameState, battle.province, {"power": {foe: 0.75}})
	if weaker.ok:
		ideas.append("an enemy a quarter weaker would cut your daily loss by %d%%" % roundi(100.0 * (1.0 - weaker.sides[me].loss / maxf(ours.loss, 1.0))))
	var holds := false
	for id: int in battle.sides[me].armies:
		var a: Army = GameState.armies.get(id)
		if a != null and a.province == battle.province and not a.attacking:
			holds = true
	if holds:
		var dug := Military.battle_forecast(GameState, battle.province, {"entrench": {me: 1}})
		if dug.ok and dug.sides[me].loss < ours.loss - 0.5:
			ideas.append("one more level of trench would cut your daily loss by %d%%" % roundi(100.0 * (1.0 - dug.sides[me].loss / maxf(ours.loss, 1.0))))
	if not ideas.is_empty():
		lines.append("What would change it: " + "; ".join(ideas) + ". Terrain and the works of the province count already.")
	var shells: float = GameState.nations[me].shell_ratio
	if shells < 0.99:
		lines.append("Your guns are short of shells: they got %d%% of what they needed and fight the weaker for it (more arms production, or buy abroad)." % roundi(shells * 100.0))
	return "\n".join(lines)


func _side_order(battle: Dictionary) -> Array:
	var tags: Array = battle.sides.keys()
	tags.sort_custom(func(x: String, y: String) -> bool: return x == battle.attacker and y != battle.attacker)
	return tags


func _rebuild_sides(battle: Dictionary) -> void:
	for c in _sides.get_children():
		_sides.remove_child(c)
		c.queue_free()
	for tag: String in _side_order(battle):
		var side: Dictionary = battle.sides[tag]
		var nation: Nation = GameState.nations[tag]
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.add_theme_constant_override("separation", 2)
		var name_label := Label.new()
		var role := "attacking" if tag == battle.attacker else ("defending" if not battle.attacker.is_empty() else "")
		name_label.text = nation.display_name + ("  (%s)" % role if not role.is_empty() else "")
		name_label.add_theme_font_size_override("font_size", 15)
		name_label.modulate = nation.color.lightened(0.4)
		column.add_child(name_label)
		var start: float = battle.start_men.get(tag, 0.0)
		var lost: float = battle.lost.get(tag, 0.0)
		var left: float = side.men_now if battle.active else side.men_end
		var morale: float = _final_morale(battle, tag) if not battle.active else side.morale
		var lines: PackedStringArray = [
			"%s men of %s %s" % [Fmt.people(left), Fmt.people(start), "now" if battle.active else "left"],
			"Lost %s (%d%%), morale %d%%" % [Fmt.people(lost), roundi(100.0 * lost / maxf(start, 1.0)), roundi(morale * 100.0)],
		]
		if side.defense > 1.0 and battle.active:
			lines.append("Defence ×%.2f from terrain and trenches" % side.defense)
		if not side.generals.is_empty():
			lines.append("Led by " + ", ".join(side.generals))
		var stats := Label.new()
		stats.text = "\n".join(lines)
		stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		column.add_child(stats)
		var comp := Label.new()
		var comp_now: String = _comp_text(side.comp_now if battle.active else side.comp_end)
		var comp_start: String = _comp_text(side.comp_start)
		comp.text = comp_start if comp_now == comp_start else "At the start: %s\n%s: %s" % [comp_start, "Now" if battle.active else "At the end", comp_now]
		comp.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		comp.modulate = Fmt.DIM
		column.add_child(comp)
		var armies := Label.new()
		var names: PackedStringArray = []
		for id: int in side.armies:
			var a: Army = GameState.armies.get(id)
			var note := ""
			if a == null:
				note = " (lost)"
			elif a.province == battle.province:
				note = " (%s)" % Fmt.people(a.men())
			else:
				note = " (withdrawn)"
			names.append("• " + side.armies[id] + note)
		armies.text = "\n".join(names)
		armies.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		armies.modulate = Fmt.DIM
		column.add_child(armies)
		_sides.add_child(column)


func _comp_text(comp: Dictionary) -> String:
	if comp.is_empty():
		return "none"
	var parts: PackedStringArray = []
	for type in Military.unit_type_ids():
		if comp.has(type):
			parts.append("%d %s" % [comp[type], Military.cfg.unit_types[type].name.get_slice(" ", 0).to_lower()])
	return ", ".join(parts)


func _final_morale(battle: Dictionary, tag: String) -> float:
	for i in range(battle.timeline.size() - 1, -1, -1):
		if battle.timeline[i].morale.has(tag):
			return battle.timeline[i].morale[tag]
	return 0.0


func _update_charts(battle: Dictionary) -> void:
	var morale_series := []
	for tag: String in _side_order(battle):
		var color: Color = GameState.nations[tag].color.lightened(0.25)
		var name: String = GameState.nations[tag].display_name
		var morale_points: Array[Vector2] = [Vector2(0, 1.0)]
		for entry: Dictionary in battle.timeline:
			morale_points.append(Vector2(entry.day, entry.morale.get(tag, 0.0)))
		morale_series.append({"name": name, "color": color, "points": morale_points})
	_morale_chart.set_data("Morale", morale_series, true)


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close_screen()
		get_viewport().set_input_as_handled()
