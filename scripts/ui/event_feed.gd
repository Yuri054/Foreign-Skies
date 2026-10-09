extends VBoxContainer
## Short-lived messages on the left under the top bar: battles the player is in, provinces
## changing hands, wars starting, units finishing training.

const LIFETIME := 9.0
const MAX_LINES := 6

## Provinces where a battle was announced and is still going.
var _active: Dictionary = {}
var _fought_today: Dictionary = {}


func _ready() -> void:
	add_to_group("event_feed")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_left = 0.5
	anchor_right = 0.5
	offset_left = -200.0
	offset_right = 200.0
	offset_top = 44.0
	add_theme_constant_override("separation", 2)
	GameState.battle_fought.connect(_on_battle)
	GameState.armies_changed.connect(_end_of_day)
	GameState.province_controller_changed.connect(_on_controller_changed)
	GameState.unit_trained.connect(func(tag: String, province: int, type: String) -> void:
		if tag == GameState.player_tag:
			say("%s trained in %s." % [Military.cfg.unit_types[type].name, MapData.provinces[province].name], Fmt.GOOD)
	)
	GameState.nation_collapsed.connect(func(tag: String, men: int) -> void:
		say("%s holds no land: its armies (%s men) disband." % [_name(tag), Fmt.people(men)], Fmt.WARN)
	)
	_connect_diplomacy()
	GameState.war_changed.connect(func(a: String, b: String, at_war: bool) -> void:
		var text := "%s and %s are now at war." if at_war else "%s and %s have made peace."
		say(text % [_name(a), _name(b)], Fmt.BAD if at_war else Fmt.GOOD)
	)


## Treaties, calls to arms, alarms and peace offers.
func _connect_diplomacy() -> void:
	GameState.treaty_changed.connect(func(t: Treaty, added: bool) -> void:
		if not t.involves(GameState.player_tag):
			return
		var label: String = Diplomacy.cfg.treaties[t.kind].label
		say("%s between %s and %s %s." % [label, _name(t.a), _name(t.b), "signed" if added else "ended"], Fmt.GOOD if added else Fmt.WARN)
	)
	GameState.join_called.connect(func(d: Dictionary) -> void:
		say("%s is mobilizing to join the war on the side of %s." % [_name(d.tag), _name(d.ally)], Fmt.WARN)
	)
	GameState.join_resolved.connect(func(d: Dictionary, joined: bool) -> void:
		if joined:
			say("%s joins the war on the side of %s." % [_name(d.tag), _name(d.ally)], Fmt.BAD)
		elif not d.conflict and d.kind != "entente":
			say("%s does not honour its ties to %s." % [_name(d.tag), _name(d.ally)], Fmt.WARN)
	)
	GameState.mobilization_alarm.connect(func(tag: String, neighbor: String) -> void:
		if tag == GameState.player_tag or neighbor == GameState.player_tag:
			say("%s's mobilization alarms %s." % [_name(tag), _name(neighbor)], Fmt.WARN)
	)
	GameState.peace_resolved.connect(func(offer: Dictionary, accepted: bool) -> void:
		if not (offer.from == GameState.player_tag or offer.to == GameState.player_tag):
			return
		say("%s %s the peace offered by %s." % [_name(offer.to), "accepts" if accepted else "refuses", _name(offer.from)], Fmt.GOOD if accepted else Fmt.WARN)
	)


func say(text: String, color := Color.WHITE) -> void:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.modulate = color
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	while get_child_count() > MAX_LINES:
		var oldest := get_child(0)
		remove_child(oldest)
		oldest.queue_free()
	var tween := label.create_tween()
	tween.tween_interval(LIFETIME)
	tween.tween_property(label, "modulate:a", 0.0, 1.5)
	tween.tween_callback(label.queue_free)


func _on_battle(province: int, tags: Array) -> void:
	_fought_today[province] = tags


func _end_of_day() -> void:
	for id in _active.keys():
		if not _fought_today.has(id):
			_active.erase(id)
	for id in _fought_today:
		if _active.has(id):
			continue
		_active[id] = true
		var tags: Array = _fought_today[id]
		if tags.has(GameState.player_tag):
			var names: PackedStringArray = []
			for t in tags:
				names.append(_name(t))
			say("Battle in %s: %s." % [MapData.provinces[id].name, " vs ".join(names)], Fmt.WARN)
	_fought_today.clear()


func _on_controller_changed(id: int, _old: String, new_controller: String) -> void:
	var owner_tag: String = GameState.province_owner[id]
	if new_controller != GameState.player_tag and owner_tag != GameState.player_tag:
		return
	var verb := "%s now holds %s" % [_name(new_controller), MapData.provinces[id].name]
	if new_controller == owner_tag:
		verb = "%s has been liberated" % MapData.provinces[id].name
	say(verb + ".", Fmt.GOOD if new_controller == GameState.player_tag or new_controller == owner_tag and owner_tag == GameState.player_tag else Fmt.BAD)


func _name(tag: String) -> String:
	return GameState.nations[tag].display_name
