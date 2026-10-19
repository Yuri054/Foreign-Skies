extends SceneTree
## Headless test of the AI's grasp of the new economy: a nation that buys nitrates abroad builds
## one Haber-Bosch plant (and only one), a nation with no need for them builds none, and the
## shell stock counts in what the army lacks so the lines lean toward shells when it runs low.
## Run: godot --headless --path . -s res://tests/ai_nitrate_test.gd

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
	gs.ai_enabled = false
	var B = load("res://scripts/ai/ai_budget.gd")
	var P = load("res://scripts/sim/production.gd")
	var ger = gs.nations["GER"]
	_check(float(ger.budget.resources.nitrates.need) > 0.0, "Germany buys its nitrates abroad at the start")
	_check(B._nitrate_plant(gs, "GER"), "so its AI starts a Haber-Bosch plant")
	var job = ger.construction.back()
	_check(job.type == "haber_bosch" and gs.province_owner[job.province] == "GER", "in one of its own provinces")
	_check(not B._nitrate_plant(gs, "GER"), "and does not start a second while one is being built")
	var srb = gs.nations["SRB"]
	_check(float(srb.budget.resources.nitrates.need) == 0.0 and not B._nitrate_plant(gs, "SRB"), "a nation with no need for nitrates builds none")
	# Shells and the army's lack.
	var short: Dictionary = P.deficit(gs, "GER")
	_check(short.has("shells") and short.shells == 0.0, "with a good stock the army lacks no shells")
	ger.equipment["shells"] = 0.0
	short = P.deficit(gs, "GER")
	_check(is_equal_approx(short.shells, 1.0), "with none it lacks them entirely")
	var AIP = load("res://scripts/ai/ai_production.gd")
	var wanted: Dictionary = AIP.wanted_lines(ger, {"shells": 1.0, "arms": 0.0, "artillery": 0.0})
	var plain: Dictionary = AIP.wanted_lines(ger, {})
	_check(wanted.shells > plain.shells, "and the AI moves factories to the shell line (%d against %d)" % [wanted.shells, plain.shells])
	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)
