extends SceneTree
## Headless test of the sound: every manifest entry resolves to a file, an event plays at most
## once per cooldown, a muted or silent bus is silent, the game's signals play their sounds, the
## music follows the menus, peace and war and answers its controls, and the settings are saved.
## Run: godot --headless --path . -s res://tests/audio_test.gd

var _failures := 0


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", msg)
	else:
		print("ok:   ", msg)


func _initialize() -> void:
	await process_frame
	var audio: Node = root.get_node("Audio")
	var gs: Node = root.get_node("GameState")
	var UiSettings = load("res://scripts/ui/ui_settings.gd")
	UiSettings.path = "user://test_audio_settings.cfg"
	DirAccess.remove_absolute(UiSettings.path)

	for bus in ["Master", "Music", "Effects", "Interface"]:
		_check(AudioServer.get_bus_index(bus) >= 0, "the %s bus exists" % bus)

	var missing := 0
	for e in audio.events:
		var ev: Dictionary = audio.events[e]
		if audio.stream_of(e) == null or AudioServer.get_bus_index(ev.bus) < 0:
			missing += 1
			printerr("  unresolved: ", e)
	_check(not audio.events.is_empty() and missing == 0, "every manifest entry resolves to a file and a bus (%d events)" % audio.events.size())
	_check(audio.tracks().size() == 3, "the soundtrack has three pieces")
	var every_file := true
	for t in audio.tracks():
		every_file = every_file and ResourceLoader.exists("res://data/audio/" + t.file)
	_check(every_file, "every piece of the soundtrack is a file in the project")
	var lists_ok := true
	for key in ["menu", "peace", "war"]:
		for id in audio.music_cfg[key]:
			lists_ok = lists_ok and not audio.track_info(id).is_empty()
	_check(lists_ok and audio.music_cfg.menu[0] == "diplomatic_silence", "the menu, peace and war lists name real pieces, and the menu plays Diplomatic Silence")

	audio.fake_time = 100.0
	audio.played.clear()
	_check(audio.play("battle"), "an event plays")
	_check(not audio.play("battle"), "it does not play again inside its cooldown")
	audio.fake_time = 100.0 + audio.events.battle.cooldown + 0.1
	_check(audio.play("battle"), "it plays again once the cooldown has passed")
	_check(not audio.play("no_such_event"), "an unknown event is ignored")

	audio.fake_time = 500.0
	audio.set_muted("Effects", true)
	_check(not audio.play("battle"), "a muted bus is silent")
	audio.set_muted("Effects", false)
	audio.set_volume("Effects", 0.0)
	_check(not audio.play("battle"), "a bus turned right down is silent")
	audio.set_volume("Effects", 1.0)
	audio.set_muted("Master", true)
	_check(not audio.play("battle"), "a muted master silences every bus")
	audio.set_muted("Master", false)

	# Settings are saved and read back.
	audio.set_volume("Music", 0.5)
	audio.set_muted("Interface", true)
	audio.set_volume("Music", 1.0)
	audio.set_muted("Interface", false)
	var cfg := ConfigFile.new()
	cfg.load(UiSettings.path)
	_check(cfg.get_value("audio", "interface_mute", false) == false and cfg.has_section_key("audio", "music_volume"), "the settings are saved")
	audio.set_volume("Music", 0.25)
	audio.set_muted("Interface", true)
	audio.set_volume("Music", 1.0)
	audio.set_muted("Interface", false)
	cfg.load(UiSettings.path)
	cfg.set_value("audio", "music_volume", 0.25)
	cfg.set_value("audio", "interface_mute", true)
	cfg.save(UiSettings.path)
	audio.load_settings()
	_check(absf(audio.volume("Music") - 0.25) < 0.01 and audio.is_muted("Interface"), "saved settings are loaded")
	audio.set_volume("Music", 1.0)
	audio.set_muted("Interface", false)

	# The game's signals.
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	var player: String = gs.player_tag
	var other := "GER" if player != "GER" else "FRA"
	var step := 0.0
	var fire := func(event: String, action: Callable) -> bool:
		step += 1000.0
		audio.fake_time = 1000.0 + step
		audio.played.clear()
		action.call()
		return event in audio.played
	_check(fire.call("battle", func(): gs.battle_fought.emit(1, [player, other])), "a battle of the player's plays")
	_check(not fire.call("battle", func(): gs.battle_fought.emit(1, [other, "ITA"])), "a battle of other nations does not")
	_check(fire.call("war_declared", func(): gs.war_changed.emit(other, "ITA", true)), "a war declared plays")
	_check(fire.call("peace_signed", func(): gs.war_changed.emit(other, "ITA", false)), "peace plays")
	_check(fire.call("building_completed", func(): gs.building_completed.emit(player, 1, "farm")), "the player's building plays")
	_check(not fire.call("building_completed", func(): gs.building_completed.emit(other, 1, "farm")), "another nation's building does not")
	_check(fire.call("unit_trained", func(): gs.unit_trained.emit(player, 1, "infantry")), "a unit trained plays")
	_check(fire.call("nation_collapse", func(): gs.nation_collapsed.emit(other, 1000)), "a collapse plays")
	_check(fire.call("ship_sunk", func(): gs.ship_sunk.emit(other, 1, "cruiser")), "a ship sunk plays")
	_check(fire.call("join_request", func(): gs.join_requested.emit({})), "a join request plays")
	_check(fire.call("blockade_begins", func(): gs.blockade_changed.emit(other, 0.3)), "a blockade beginning plays")
	_check(not fire.call("blockade_begins", func(): gs.blockade_changed.emit(other, 0.4)), "a blockade that goes on does not")
	var button := Button.new()
	root.add_child(button)
	_check(fire.call("click", func(): button.pressed.emit()), "a button clicks")
	button.queue_free()

	# The music.
	audio.set_music_context("menu")
	_check(audio.current_track() == "diplomatic_silence", "the menus play Diplomatic Silence (%s)" % audio.current_track())
	audio.set_music_context("game")
	gs.wars.clear()
	audio._process(1.0)
	_check(audio.current_track() == "diplomatic_silence", "at peace the game plays from the peace list (%s)" % audio.current_track())
	gs.wars[player + "|" + other] = true
	audio._process(1.0)
	_check(audio.current_track() == "diplomacy_of_steel", "when the player goes to war the music crossfades to the war list (%s)" % audio.current_track())
	audio._process(10.0)
	_check(audio._fade == 1.0 and not audio._players[1 - audio._front].playing, "and the crossfade finishes, the old piece stopped")
	gs.wars.clear()
	audio._process(1.0)
	_check(audio.current_track() == "diplomatic_silence", "at peace again it goes back")
	audio._on_music_finished(audio._players[audio._front])
	_check(audio.current_track() == "marche_imperiale", "when a piece ends the next of the list follows")
	audio.step_track(1)
	_check(audio.current_track() == "diplomacy_of_steel" and not audio.music_auto, "Next goes on through the soundtrack and leaves Auto")
	audio.step_track(-1)
	_check(audio.current_track() == "marche_imperiale", "and Previous goes back")
	gs.wars[player + "|" + other] = true
	audio._process(1.0)
	_check(audio.current_track() == "marche_imperiale", "out of Auto the music no longer follows the war")
	audio.set_music_repeat(true)
	audio._on_music_finished(audio._players[audio._front])
	_check(audio.current_track() == "marche_imperiale", "with Repeat a piece starts over")
	audio.set_music_repeat(false)
	audio.set_music_paused(true)
	_check(audio._players[audio._front].stream_paused, "Pause holds the music")
	audio.set_music_paused(false)
	audio.choose_track("diplomatic_silence")
	audio.set_music_auto(true)
	_check(audio.current_track() == "diplomacy_of_steel", "Follow the game takes it to the war list from a piece outside it (%s)" % audio.current_track())
	gs.wars.clear()
	audio.choose_track("marche_imperiale")
	cfg.load(UiSettings.path)
	_check(cfg.get_value("audio", "music_track", "") == "marche_imperiale" and cfg.get_value("audio", "music_auto", true) == false, "the chosen piece and Auto are saved")
	audio.set_music_auto(true)
	audio.set_music_context("menu")

	DirAccess.remove_absolute(UiSettings.path)
	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)
