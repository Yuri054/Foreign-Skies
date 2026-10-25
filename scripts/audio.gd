extends Node
## Sound. Buses: Master, Music, Effects, Interface (default_bus_layout.tres). Events come from
## data/audio.json (name -> file, bus, volume, cooldown) and are played on the game's signals, so
## nothing in the simulation knows about sound. Fights, buildings and units of other nations are
## left out: only what concerns the player's nation, plus wars, peace and collapses anywhere.
## The soundtrack is a playlist of pieces (data/audio/music/) that crossfade: in Auto it follows the
## game (the menu theme in the menus, one list at peace and another while the player's nation is at
## war); the player can also pick a track, repeat it, or pause. Volumes, mutes and these choices are
## saved with the other settings (UiSettings.path, section "audio").

const MANIFEST := "res://data/audio.json"
const BUSES := ["Master", "Music", "Effects", "Interface"]
## Below this a bus is taken as silent.
const SILENT_DB := -60.0
## A blockade is announced at this level (as in the event feed).
const BLOCKADE_NOTICE := 0.1

## name -> {file, bus, volume_db, cooldown, stream}
var events: Dictionary = {}
var music_cfg: Dictionary = {}
## Seconds on the clock the cooldowns use; tests set it to step time by hand (-1 = real time).
var fake_time := -1.0
## The events played, newest last (kept short; the tests read it).
var played: Array[String] = []
var _last: Dictionary = {}
var _blockaded: Dictionary = {}

## Whether the music follows the game (menu, peace, war); off once the player picks a track.
var music_auto := true
## Whether the playing piece starts over when it ends instead of the next one.
var music_repeat := false
var music_paused := false
## "menu" or "game": where the music is wanted (the menu scene and the game scene say so).
var music_context := "menu"
## The track playing now (an id from the manifest's tracks), and the track the player last picked.
var _track := ""
var _picked := ""
var _players: Array[AudioStreamPlayer] = [AudioStreamPlayer.new(), AudioStreamPlayer.new()]
var _front := 0
## Progress of the crossfade into the front player (1: finished).
var _fade := 1.0
var _at_war := false
var _streams: Dictionary = {}

signal music_changed


func _ready() -> void:
	load_manifest()
	load_settings()
	_connect_game()
	get_tree().node_added.connect(_on_node_added)
	_start_music()


func load_manifest(path := MANIFEST) -> void:
	events.clear()
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (data is Dictionary):
		push_error("audio.json is invalid")
		return
	for name: String in data.get("events", {}):
		var e: Dictionary = data.events[name]
		events[name] = {"file": str(e.file), "bus": str(e.bus), "volume_db": float(e.get("volume_db", 0.0)),
				"cooldown": float(e.get("cooldown", 0.0)), "stream": null}
	music_cfg = data.get("music", {})


## The sound of an event, loaded the first time it is wanted.
func stream_of(event: String) -> AudioStream:
	var e: Dictionary = events.get(event, {})
	if e.is_empty():
		return null
	if e.stream == null:
		e.stream = load("res://data/audio/" + e.file)
	return e.stream


## Plays an event unless it is unknown, cooling down, or on a muted or silent bus. Returns whether
## it played.
func play(event: String) -> bool:
	var e: Dictionary = events.get(event, {})
	if e.is_empty() or is_silent(e.bus):
		return false
	var now := _now()
	if now - float(_last.get(event, -1.0e9)) < e.cooldown:
		return false
	var stream := stream_of(event)
	if stream == null:
		return false
	_last[event] = now
	played.append(event)
	if played.size() > 200:
		played = played.slice(100)
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.bus = e.bus
	p.volume_db = e.volume_db
	p.finished.connect(p.queue_free)
	add_child(p)
	p.play()
	return true


func _now() -> float:
	return fake_time if fake_time >= 0.0 else Time.get_ticks_msec() / 1000.0


## A bus that is muted or turned right down, or whose master is.
func is_silent(bus: String) -> bool:
	for b in ([bus] if bus == "Master" else [bus, "Master"]):
		var i := AudioServer.get_bus_index(b)
		if i < 0 or AudioServer.is_bus_mute(i) or AudioServer.get_bus_volume_db(i) <= SILENT_DB:
			return true
	return false


# Settings -------------------------------------------------------------------------------------

func volume(bus: String) -> float:
	return db_to_linear(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(bus)))


func is_muted(bus: String) -> bool:
	return AudioServer.is_bus_mute(AudioServer.get_bus_index(bus))


## Sets a bus's volume (0 to 1) and saves it.
func set_volume(bus: String, linear: float) -> void:
	linear = clampf(linear, 0.0, 1.0)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(bus), linear_to_db(linear) if linear > 0.001 else -80.0)
	_save(bus, "volume", linear)


func set_muted(bus: String, muted: bool) -> void:
	AudioServer.set_bus_mute(AudioServer.get_bus_index(bus), muted)
	_save(bus, "mute", muted)


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(UiSettings.path) != OK:
		return
	for bus: String in BUSES:
		var i := AudioServer.get_bus_index(bus)
		if i < 0:
			continue
		var v := clampf(float(cfg.get_value("audio", bus.to_lower() + "_volume", 1.0)), 0.0, 1.0)
		AudioServer.set_bus_volume_db(i, linear_to_db(v) if v > 0.001 else -80.0)
		AudioServer.set_bus_mute(i, bool(cfg.get_value("audio", bus.to_lower() + "_mute", false)))
	music_auto = bool(cfg.get_value("audio", "music_auto", true))
	music_repeat = bool(cfg.get_value("audio", "music_repeat", false))
	music_paused = bool(cfg.get_value("audio", "music_paused", false))
	_picked = str(cfg.get_value("audio", "music_track", ""))


func _save(bus: String, what: String, value: Variant) -> void:
	var cfg := ConfigFile.new()
	cfg.load(UiSettings.path)
	cfg.set_value("audio", "%s_%s" % [bus.to_lower(), what], value)
	cfg.save(UiSettings.path)


# Events ---------------------------------------------------------------------------------------

func _connect_game() -> void:
	var gs := GameState
	gs.battle_fought.connect(func(_p: int, tags: Array) -> void:
		if gs.player_tag in tags:
			play("battle")
	)
	gs.sea_battle_fought.connect(func(_z: int, tags: Array) -> void:
		if gs.player_tag in tags:
			play("battle")
	)
	gs.war_changed.connect(func(_a: String, _b: String, at_war: bool) -> void:
		play("war_declared" if at_war else "peace_signed")
	)
	gs.building_completed.connect(func(tag: String, _p: int, _t: String) -> void:
		if tag == gs.player_tag:
			play("building_completed")
	)
	gs.unit_trained.connect(func(tag: String, _p: int, _t: String) -> void:
		if tag == gs.player_tag:
			play("unit_trained")
	)
	gs.ship_built.connect(func(tag: String, _p: int, _t: String) -> void:
		if tag == gs.player_tag:
			play("unit_trained")
	)
	gs.treaty_changed.connect(func(t: Treaty, added: bool) -> void:
		if added and t.involves(gs.player_tag):
			play("treaty_signed")
	)
	gs.join_requested.connect(func(_d: Dictionary) -> void: play("join_request"))
	gs.nation_collapsed.connect(func(_t: String, _m: int) -> void: play("nation_collapse"))
	gs.ship_sunk.connect(func(_t: String, _z: int, _ty: String) -> void: play("ship_sunk"))
	gs.blockade_changed.connect(func(tag: String, value: float) -> void:
		var was: bool = _blockaded.get(tag, false)
		var now := was
		if value <= 0.001:
			now = false
		elif value >= BLOCKADE_NOTICE:
			now = true
		_blockaded[tag] = now
		if now and not was:
			play("blockade_begins")
	)
	gs.scenario_loaded.connect(func() -> void: _blockaded.clear())


## Every button of the game clicks.
func _on_node_added(node: Node) -> void:
	if node is BaseButton and not node.pressed.is_connected(_click):
		node.pressed.connect(_click)


func _click() -> void:
	play("click")


# Music ----------------------------------------------------------------------------------------

func _start_music() -> void:
	if music_cfg.is_empty():
		return
	for p in _players:
		p.bus = music_cfg.get("bus", "Music")
		p.volume_db = -80.0
		p.finished.connect(_on_music_finished.bind(p))
		add_child(p)
	if music_auto or _picked.is_empty() or track_info(_picked).is_empty():
		_follow()
	else:
		play_track(_picked)


## The pieces of the soundtrack, in order: [{id, title, file}].
func tracks() -> Array:
	return music_cfg.get("tracks", [])


func track_info(id: String) -> Dictionary:
	for t: Dictionary in tracks():
		if t.id == id:
			return t
	return {}


func track_title(id: String) -> String:
	return str(track_info(id).get("title", ""))


## The id of the piece playing now ("" before the music starts).
func current_track() -> String:
	return _track


## Seconds into the piece and its length, for the display.
func music_position() -> float:
	return _players[_front].get_playback_position() if _players[_front].playing else 0.0


func music_length() -> float:
	var stream := _players[_front].stream
	return stream.get_length() if stream != null else 0.0


## Tells the music where it is wanted: "menu" or "game". In Auto it changes to what suits.
func set_music_context(context: String) -> void:
	if context == music_context:
		return
	music_context = context
	if music_auto and not music_cfg.is_empty():
		_follow()


## The list Auto draws from now.
func playlist() -> Array:
	var key := "menu" if music_context == "menu" else ("war" if _at_war else "peace")
	return music_cfg.get(key, [])


## Plays the first piece of the situation's list unless a piece of the list is already playing.
func _follow() -> void:
	var list := playlist()
	if list.is_empty() or _track in list:
		return
	play_track(list[0])


## Crossfades to a piece (at once with `fade` false).
func play_track(id: String, fade := true) -> void:
	var info := track_info(id)
	if info.is_empty():
		return
	var stream: AudioStream = _streams.get(id)
	if stream == null:
		stream = load("res://data/audio/" + str(info.file))
		_streams[id] = stream
	if stream == null:
		return
	if "loop" in stream:
		stream.loop = music_repeat
	var back := _players[1 - _front]
	back.stream = stream
	back.volume_db = -80.0
	back.stream_paused = false
	back.play()
	back.stream_paused = music_paused
	_front = 1 - _front
	_track = id
	_fade = 0.0 if fade else 1.0
	if not fade:
		_players[1 - _front].stop()
	_apply_music_volume()
	music_changed.emit()


## The player picks a piece: it plays and the music stops following the game.
func choose_track(id: String) -> void:
	_picked = id
	music_auto = false
	_save_music("music_track", id)
	_save_music("music_auto", false)
	play_track(id)


## The next (1) or previous (-1) piece in the soundtrack's order; this also leaves Auto.
func step_track(direction: int) -> void:
	var list := tracks()
	if list.is_empty():
		return
	var at := 0
	for i in list.size():
		if list[i].id == _track:
			at = i
	choose_track(list[posmod(at + direction, list.size())].id)


func set_music_auto(on: bool) -> void:
	music_auto = on
	_save_music("music_auto", on)
	if on:
		_follow()
	music_changed.emit()


func set_music_repeat(on: bool) -> void:
	music_repeat = on
	_save_music("music_repeat", on)
	var stream := _players[_front].stream
	if stream != null and "loop" in stream:
		stream.loop = on
	music_changed.emit()


func set_music_paused(on: bool) -> void:
	music_paused = on
	_save_music("music_paused", on)
	for p in _players:
		p.stream_paused = on
	music_changed.emit()


func _save_music(key: String, value: Variant) -> void:
	var cfg := ConfigFile.new()
	cfg.load(UiSettings.path)
	cfg.set_value("audio", key, value)
	cfg.save(UiSettings.path)


## A piece ended (the one in front; one fading out is just stopped): the next of the list, or the same again.
func _on_music_finished(player: AudioStreamPlayer) -> void:
	if player != _players[_front] or music_paused:
		return
	if music_repeat:
		play_track(_track, false)
		return
	var list: Array = playlist() if music_auto else tracks().map(func(t: Dictionary) -> String: return t.id)
	if list.is_empty():
		return
	var at := list.find(_track)
	play_track(list[(at + 1) % list.size()])


## 1 when the player's nation is at war, else 0.
func war_target() -> float:
	var tag: String = GameState.player_tag
	for key: String in GameState.wars:
		if tag in key.split("|"):
			return 1.0
	return 0.0


func _process(delta: float) -> void:
	if music_cfg.is_empty():
		return
	if music_context == "game":
		var war := war_target() > 0.5
		if war != _at_war:
			_at_war = war
			if music_auto:
				_follow()
	if _fade < 1.0:
		_fade = minf(1.0, _fade + delta / maxf(float(music_cfg.get("fade_seconds", 3.0)), 0.1))
		_apply_music_volume()
		if _fade >= 1.0:
			var old := _players[1 - _front]
			old.stop()
			old.stream = null


func _apply_music_volume() -> void:
	var base := float(music_cfg.get("volume_db", 0.0))
	_players[_front].volume_db = base + linear_to_db(maxf(_fade, 0.0001))
	_players[1 - _front].volume_db = base + linear_to_db(maxf(1.0 - _fade, 0.0001)) if _fade < 1.0 else -80.0
