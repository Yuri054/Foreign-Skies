extends VBoxContainer
## Short-lived messages on the left under the top bar: battles the player is in, provinces
## changing hands, wars starting, units finishing training.

const LIFETIME := 9.0
const MAX_LINES := 6
## A blockade is announced when it reaches this level.
const BLOCKADE_NOTICE := 0.1

## Provinces where a battle was announced and is still going.
var _active: Dictionary = {}
var _fought_today: Dictionary = {}
## The same for sea battles, by zone, and the nations whose blockade has been announced.
var _sea_active: Dictionary = {}
var _sea_fought_today: Dictionary = {}
var _blockaded: Dictionary = {}


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
	GameState.news_posted.connect(func(text: String, level: int) -> void: say(text, Fmt.WARN if level > 0 else Color.WHITE))
	_connect_diplomacy()
	_connect_navy()
	GameState.war_changed.connect(func(a: String, b: String, at_war: bool) -> void:
		var text := "%s and %s are now at war." if at_war else "%s and %s have made peace."
		say(text % [_name(a), _name(b)], Fmt.BAD if at_war else Fmt.GOOD)
	)


## Naval battles, ships sunk and launched, blockades beginning and lifting.
func _connect_navy() -> void:
	GameState.sea_battle_fought.connect(func(zone: int, tags: Array) -> void:
		_sea_fought_today[zone] = tags
	)
	GameState.fleets_changed.connect(_end_of_sea_day)
	GameState.ship_sunk.connect(func(tag: String, zone: int, type: String) -> void:
		var mine: bool = tag == GameState.player_tag
		say("%s lost a %s in the %s." % [_name(tag), Navy.cfg.types[type].name.to_lower(), MapData.sea_zones[zone].name], Fmt.BAD if mine else Fmt.GOOD)
	)
	GameState.casus_belli_ready.connect(func(holder: String, target: String) -> void:
		if holder == GameState.player_tag:
			say("Your claim against %s is ready: a fabricated casus belli." % _name(target), Fmt.GOOD)
		elif target == GameState.player_tag:
			say("%s has fabricated a claim against you." % _name(holder), Fmt.BAD)
	)
	GameState.ship_built.connect(func(tag: String, province: int, type: String) -> void:
		if tag == GameState.player_tag:
			say("%s launched at %s." % [Navy.cfg.types[type].name, MapData.provinces[province].name], Fmt.GOOD)
	)
	GameState.blockade_changed.connect(func(tag: String, value: float) -> void:
		var was: bool = _blockaded.get(tag, false)
		var now := value >= BLOCKADE_NOTICE
		if now == was and not (was and value <= 0.001):
			return
		if was and value <= 0.001:
			_blockaded[tag] = false
			say("The blockade of %s is lifted." % _name(tag), Fmt.GOOD if tag != GameState.player_tag else Fmt.GOOD)
		elif now and not was:
			_blockaded[tag] = true
			var by: PackedStringArray = []
			for t in GameState.nations[tag].blockade_by:
				by.append(_name(t))
			say("%s is being blockaded%s." % [_name(tag), (" by " + ", ".join(by)) if not by.is_empty() else ""],
					Fmt.BAD if tag == GameState.player_tag else Fmt.WARN)
	)


func _end_of_sea_day() -> void:
	for zone in _sea_active.keys():
		if not _sea_fought_today.has(zone):
			_sea_active.erase(zone)
	for zone in _sea_fought_today:
		if _sea_active.has(zone):
			continue
		_sea_active[zone] = true
		var tags: Array = _sea_fought_today[zone]
		if tags.has(GameState.player_tag):
			var names: PackedStringArray = []
			for t in tags:
				if not names.has(_name(t)):
					names.append(_name(t))
			say("Naval battle in the %s: %s." % [MapData.sea_zones[zone].name, " vs ".join(names)], Fmt.WARN)
	_sea_fought_today.clear()


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
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(400, 0)
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
