extends SceneTree
## Headless test for named alliances: generated names, joining a named group, renaming,
## historic blocs, saves.
## Run: godot --headless --path . -s res://tests/alliance_names_test.gd

var _failures := 0


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", msg)
	else:
		print("ok:   ", msg)


func _initialize() -> void:
	await process_frame
	var gs: Node = root.get_node("GameState")
	var D = load("res://scripts/sim/diplomacy.gd")
	var Rename = load("res://scripts/sim/rename_alliance.gd")
	var Propose = load("res://scripts/sim/propose_treaty.gd")
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	gs.set_player("ESP")
	_check(D.bloc_name(gs, "FRA") != "" and D.is_historic_bloc(gs, "FRA"), "France stands in a historic bloc (%s)" % D.bloc_name(gs, "FRA"))
	_check(D.bloc_name(gs, "SUI") == "" and D.bloc_name(gs, "NED") == "", "Switzerland and the Netherlands stand alone")
	for t in ["SUI", "NED"]:
		gs.nations[t].diplomacy_points = 100.0
	D.set_relation(gs, "NED", "SUI", 60.0)
	gs.nations["SUI"].diplomacy_points = 100.0
	_check(gs.issue(Propose.new("SUI", "NED", "alliance")), "Switzerland proposes an alliance to the Netherlands")
	_check(D.are_allied(gs, "SUI", "NED"), "it is signed")
	var name: String = D.bloc_name(gs, "SUI")
	_check(name != "" and name == D.bloc_name(gs, "NED") and not D.is_historic_bloc(gs, "SUI"), "both stand in a new, named alliance (%s)" % name)
	# A third nation joining takes the same name.
	D.set_relation(gs, "DEN", "NED", 60.0)
	gs.nations["DEN"].diplomacy_points = 100.0
	_check(gs.issue(Propose.new("DEN", "NED", "alliance")), "Denmark joins")
	_check(D.bloc_name(gs, "DEN") == name and D.bloc_name(gs, "SUI") == name, "and the group keeps its name")
	# Renaming.
	_check(gs.issue(Rename.new("DEN", "Northern League")), "a member renames it")
	_check(D.bloc_name(gs, "SUI") == "Northern League" and D.bloc_name(gs, "NED") == "Northern League", "everyone in the group sees the new name")
	_check(not gs.issue(Rename.new("DEN", "   ")), "an empty name is refused")
	_check(not gs.issue(Rename.new("FRA", "Mine now")), "a historic bloc cannot be renamed")
	# Saves keep names.
	var save = load("res://scripts/sim/save_game.gd")
	var path := "user://test_alliance_names.sav"
	save.write(gs, path)
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	_check(D.bloc_name(gs, "SUI") == "", "a fresh game has no such alliance")
	save.read(gs, path)
	_check(D.bloc_name(gs, "SUI") == "Northern League", "a loaded save keeps the name")
	DirAccess.remove_absolute(path)
	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)
