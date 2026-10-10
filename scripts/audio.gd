extends Node
## Sound. Buses: Master, Music, Effects, Interface (default_bus_layout.tres). Events come from
## data/audio.json (name -> file, bus, volume, cooldown) and are played on the game's signals, so
## nothing in the simulation knows about sound. Fights, buildings and units of other nations are
## left out: only what concerns the player's nation, plus wars, peace and collapses anywhere.
## Music has a calm layer and a war layer that fade into each other as the player's nation goes
## to war and makes peace. Volumes and mutes are saved with the other settings (UiSettings.path,
## section "audio").

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
var _calm := AudioStreamPlayer.new()
var _war := AudioStreamPlayer.new()
var _war_level := 0.0
var _blockaded: Dictionary = {}


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
	for pair in [[_calm, "calm"], [_war, "war"]]:
		var p: AudioStreamPlayer = pair[0]
		var stream: AudioStream = load("res://data/audio/" + str(music_cfg.get(pair[1], "")))
		if stream is AudioStreamWAV:
			stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
			stream.loop_end = stream.data.size() / 2
		p.stream = stream
		p.bus = music_cfg.get("bus", "Music")
		add_child(p)
		if stream != null:
			p.play()
	_apply_layers()


## 1 when the player's nation is at war, else 0: where the layers are heading.
func war_target() -> float:
	var tag: String = GameState.player_tag
	for key: String in GameState.wars:
		if tag in key.split("|"):
			return 1.0
	return 0.0


## The war layer's share of the music now.
func war_level() -> float:
	return _war_level


func _process(delta: float) -> void:
	var fade := maxf(float(music_cfg.get("fade_seconds", 3.0)), 0.1)
	_war_level = move_toward(_war_level, war_target(), delta / fade)
	_apply_layers()


func _apply_layers() -> void:
	var base := float(music_cfg.get("volume_db", 0.0))
	_calm.volume_db = base + linear_to_db(maxf(1.0 - _war_level, 0.0001))
	_war.volume_db = base + linear_to_db(maxf(_war_level, 0.0001))
