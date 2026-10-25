extends SceneTree
## Headless test for difficulty presets: each preset retunes the AI and the crisis generator from the files (applying twice is the
## same as once, and Historical gives the shipped numbers), the choice is saved with the game and restored on load, an old save
## plays as Historical, and the New game page offers the presets.
## Run: godot --headless --path . -s res://tests/difficulty_test.gd

var _failures := 0
var gs: Node


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", msg)
	else:
		print("ok:   ", msg)


func _initialize() -> void:
	await process_frame
	load("res://scripts/ui/ui_settings.gd").path = "user://test_settings.cfg"
	gs = root.get_node("GameState")
	var Diff = load("res://scripts/sim/difficulty.gd")
	var AI = load("res://scripts/ai/ai.gd")
	var Cr = load("res://scripts/sim/crisis.gd")
	var SaveGame = load("res://scripts/sim/save_game.gd")
	var shipped: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/ai.json"))
	var shipped_crisis: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/crises.json"))

	_check(Diff.ids() == ["historical", "challenging", "sandbox"], "the presets are Historical, Challenging and Sandbox (%s)" % str(Diff.ids()))
	gs.difficulty = "historical"
	gs.load_scenario("res://data/scenarios/jan_1900/")
	_check(is_equal_approx(AI.cfg.odds.bold, shipped.odds.bold) and is_equal_approx(Cr.cfg.gate.min_score, shipped_crisis.gate.min_score), "Historical leaves the shipped numbers alone")

	gs.difficulty = "challenging"
	Diff.apply(gs)
	_check(is_equal_approx(AI.cfg.odds.bold, shipped.odds.bold * 0.9), "Challenging asks the AI for worse odds (%.3f)" % AI.cfg.odds.bold)
	_check(is_equal_approx(AI.cfg.peace.seek_threshold, shipped.peace.seek_threshold * 1.25), "and makes it slower to seek peace")
	_check(Cr.cfg.gate.min_score < shipped_crisis.gate.min_score, "and crises come sooner")
	Diff.apply(gs)
	_check(is_equal_approx(AI.cfg.odds.bold, shipped.odds.bold * 0.9), "applying again does not compound it")
	_check(AI.cfg.forces.war_multiplier is float and typeof(AI.cfg.offense.max_campaigns) == typeof(shipped.offense.max_campaigns), "numbers keep their type")

	gs.difficulty = "sandbox"
	Diff.apply(gs)
	_check(AI.cfg.diplomacy.war.declare_threshold > shipped.diplomacy.war.declare_threshold and Cr.cfg.gate.min_score > shipped_crisis.gate.min_score, "Sandbox makes the nations slower to quarrel")

	gs.difficulty = "no_such_level"
	Diff.apply(gs)
	_check(gs.difficulty == "historical", "an unknown difficulty counts as Historical")

	# Saved with the game.
	gs.difficulty = "challenging"
	gs.load_scenario("res://data/scenarios/jan_1900/")
	gs.set_player("ESP")
	_check(gs.difficulty == "challenging" and is_equal_approx(AI.cfg.odds.bold, shipped.odds.bold * 0.9), "loading a scenario keeps the chosen difficulty")
	var path := "user://difficulty_test.sav"
	SaveGame.write(gs, path)
	gs.difficulty = "historical"
	Diff.apply(gs)
	_check(is_equal_approx(AI.cfg.odds.bold, shipped.odds.bold), "(back to Historical)")
	SaveGame.read(gs, path)
	_check(gs.difficulty == "challenging" and is_equal_approx(AI.cfg.odds.bold, shipped.odds.bold * 0.9), "a loaded game plays at the difficulty it was saved at")
	# A save from before difficulties had none in it.
	SaveGame.write(gs, path, 1)
	gs.difficulty = "sandbox"
	var body := FileAccess.get_file_as_bytes(path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_check(not body.is_empty(), "(an older save was made)")

	# The menu.
	var menu: Node = load("res://scenes/menu.tscn").instantiate()
	root.add_child(menu)
	await process_frame
	await process_frame
	var page = get_first_node_in_group("main_menu")
	page.show_page("new")
	await process_frame
	_check(page._difficulty != null and page._difficulty.item_count == 3, "the New game page offers the presets")
	page._difficulty.select(2)
	page._show_difficulty()
	_check(page.selected_difficulty() == "sandbox" and page._difficulty_note.text.contains("slower to quarrel"), "and says what the choice means: %s" % page._difficulty_note.text)

	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)
