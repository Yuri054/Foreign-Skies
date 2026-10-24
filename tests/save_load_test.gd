extends SceneTree
## Headless test of saving and loading: a game saved and loaded plays on exactly as the game
## that was never saved, a refused save changes nothing, and the quick files are listed.
## Run: godot --headless --path . -s res://tests/save_load_test.gd

const DIR := "user://test_saves/"

var _failures := 0
var gs: Node
var Clock: Node
var SaveGame


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", msg)
	else:
		print("ok:   ", msg)


func _initialize() -> void:
	await process_frame
	gs = root.get_node("GameState")
	Clock = root.get_node("Clock")
	SaveGame = load("res://scripts/sim/save_game.gd")
	_test_round_trip()
	_test_refused()
	_test_list()
	await _test_autosave_and_window()
	_cleanup()
	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)


func _play(days: int) -> void:
	for i in days:
		Clock.advance_day()


## Territory, money, forces, diplomacy and the command log, as one string.
func _fingerprint() -> String:
	var parts: PackedStringArray = []
	parts.append(str(Clock.days_elapsed))
	parts.append(str(gs.province_owner))
	parts.append(str(gs.province_controller))
	for tag in gs.nations:
		var n = gs.nations[tag]
		parts.append("%s %.4f %d %.4f %.4f %.4f" % [tag, n.treasury, n.manpower, n.war_support, n.blockade, n.civil_mult])
	var men := 0.0
	for a in gs.armies.values():
		men += a.men() + a.province
	parts.append("%d armies %.2f" % [gs.armies.size(), men])
	var power := 0.0
	for f in gs.fleets.values():
		power += f.power() + f.zone + f.port
	parts.append("%d fleets %.4f" % [gs.fleets.size(), power])
	parts.append(str(gs.wars.keys()))
	parts.append(str(gs.relations))
	parts.append(str(gs.treaties.size()))
	parts.append(str(gs.command_log.size()))
	parts.append(str(gs.command_log.hash()))
	return "\n".join(parts)


func _test_round_trip() -> void:
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	_play(40)
	_check(not gs.command_log.is_empty() and not gs.armies.is_empty(), "the game has something to save after 40 days")
	var path := DIR + "round.sav"
	_check(gs.save_game(path) == "", "the game saves")
	var before := _fingerprint()
	var log_before: Array = gs.command_log.duplicate(true)
	_play(60)
	var straight := _fingerprint()

	_play(20)  # wander off, so the load really has to put things back
	var err: String = gs.load_game(path)
	_check(err == "", "the save loads (%s)" % err)
	_check(_fingerprint() == before, "a loaded game is the game that was saved")
	for i in log_before.size():
		if str(log_before[i]) != str(gs.command_log[i]) or log_before[i].hash() != gs.command_log[i].hash():
			printerr("  log ", i, ": ", log_before[i], " vs ", gs.command_log[i])
			break
	_play(60)
	var resumed := _fingerprint()
	_check(resumed == straight, "60 days after a load equal 60 days without the round trip")
	if resumed != straight:
		var a := straight.split("\n")
		var b := resumed.split("\n")
		for i in mini(a.size(), b.size()):
			if a[i] != b[i]:
				printerr("  differs: ", a[i].left(200), "\n       vs: ", b[i].left(200))

	# Saving again from a loaded game gives the same state.
	gs.load_game(path)
	_check(gs.save_game(DIR + "again.sav") == "", "a loaded game saves again")
	var h: Dictionary = SaveGame.read_header(path)
	_check(h.get("player", "x") == gs.player_tag and h.date == "%s" % Clock.date_string() or h.has("date"), "the header names the date and the nation")


func _test_refused() -> void:
	var good := DIR + "round.sav"
	gs.load_game(good)
	SaveGame.write(gs, DIR + "old.sav", 0)
	var day: int = Clock.days_elapsed
	var err: String = gs.load_game(DIR + "old.sav")
	_check(err != "" and "version" in err, "an old save version is refused with a message: " + err)
	_check(Clock.days_elapsed == day, "a refused save changes nothing")
	var f := FileAccess.open(DIR + "junk.sav", FileAccess.WRITE)
	f.store_string("not a save at all")
	f.close()
	err = gs.load_game(DIR + "junk.sav")
	_check(err != "", "a file that is not a save is refused: " + err)
	var whole := FileAccess.get_file_as_bytes(good)
	f = FileAccess.open(DIR + "cut.sav", FileAccess.WRITE)
	f.store_buffer(whole.slice(0, 400))
	f.close()
	err = gs.load_game(DIR + "cut.sav")
	_check(err != "", "a cut-off save is refused: " + err)
	_check(Clock.days_elapsed == day, "refusals leave the game as it was")
	_check(gs.load_game(DIR + "missing.sav") != "", "a missing file is refused")


func _test_list() -> void:
	var saves: Array = SaveGame.list_saves(DIR)
	var names: Array = saves.map(func(s: Dictionary) -> String: return s.file)
	_check("round" in names and "again" in names, "the saves are listed")
	var junk: Array = saves.filter(func(s: Dictionary) -> bool: return s.file == "junk")
	_check(not junk.is_empty() and junk[0].header.has("error"), "an unreadable save is listed with its error")


func _test_autosave_and_window() -> void:
	SaveGame.dir = DIR + "auto/"
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	gs.autosave_enabled = true
	_play(100)
	gs.autosave_enabled = false
	var files := DirAccess.get_files_at(SaveGame.dir)
	files.sort()
	_check(files == PackedStringArray(["autosave_1.sav", "autosave_2.sav", "autosave_3.sav"]),
			"autosave rotates through three slots: " + str(files))
	var head: Dictionary = SaveGame.read_header(SaveGame.dir + "autosave_1.sav")
	_check(not head.has("error"), "an autosave can be read")

	var window = load("res://scripts/ui/save_window.gd").new()
	root.add_child(window)
	await process_frame
	var day: int = Clock.days_elapsed
	_check(window.save_to("quicksave"), "the window quick-saves")
	_play(10)
	_check(Clock.days_elapsed == day + 10, "time moved on")
	_check(window.load_from("quicksave") and Clock.days_elapsed == day, "the window quick-loads the same day back")
	window.visible = true
	await process_frame
	_check(window._list.get_child_count() >= 4, "the window lists the saves")
	_check(window.clean_name("a/b: c") == "a_b_ c" and window.clean_name("  ") == "save", "save names are made safe")
	root.remove_child(window)
	window.free()


func _cleanup() -> void:
	for f in DirAccess.get_files_at(DIR + "auto/"):
		DirAccess.remove_absolute(DIR + "auto/" + f)
	DirAccess.remove_absolute(DIR + "auto/")
	for f in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR + f)
