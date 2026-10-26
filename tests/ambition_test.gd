extends SceneTree
## Headless test for ambitions (step 5 of PLAN.md): which are offered to whom, choosing and giving one up, how each one
## stands, and the History book's account of it.
## Run: godot --headless --path . -s res://tests/ambition_test.gd

var _failures := 0
var gs: Node
var A


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", msg)
	else:
		print("ok:   ", msg)


func _notes() -> Array:
	return gs.history_log.filter(func(e: Dictionary) -> bool: return e.kind == "ambition")


func _initialize() -> void:
	await process_frame
	gs = root.get_node("GameState")
	A = load("res://scripts/sim/ambition.gd")
	var Set = load("res://scripts/sim/set_ambition.gd")
	gs.load_scenario("res://data/scenarios/jan_1900/")
	gs.ai_enabled = false
	gs.set_player("SRB")
	_check(Array(A.offered(gs, "SRB")) == ["keep_out", "unify", "great_power"], "Serbia may keep out, unify the nation or rise (%s)" % str(A.offered(gs, "SRB")))
	_check(not ("great_power" in A.offered(gs, "GER")), "a great power is not offered to become one")
	_check(not ("unify" in A.offered(gs, "SUI")), "and a nation with no claim has nothing to unify")
	_check(not gs.issue(Set.new("GER", "keep_out")), "only the player sets an ambition")
	_check(gs.issue(Set.new("SRB", "unify")) and gs.ambition.id == "unify", "Serbia sets out to unify the nation")
	_check(_notes().size() == 1, "and the History book notes it")
	var s: Dictionary = A.status(gs)
	_check(s.state == "on course" and s.text.contains("claimed provinces"), "it stands on course: %s" % s.text)
	for claim: Dictionary in gs.scenario.claims:
		if claim.holder == "SRB":
			for id: int in load("res://scripts/sim/diplomacy.gd").claim_provinces(claim):
				gs.transfer_province(id, "SRB")
	A.step_month(gs)
	_check(gs.ambition.state == "achieved" and _notes().size() == 2, "with every claimed province won it is achieved, in the book: %s" % _notes().back().text)
	_check(gs.issue(Set.new("SRB", "keep_out")) and _notes().size() == 4, "a new one replaces it, and both are noted")
	gs.set_war("SRB", "AUH", true)
	A.step_month(gs)
	_check(gs.ambition.state == "lost", "a war with a great power ends 'keep out': %s" % A.status(gs).text)
	gs.set_war("SRB", "AUH", false)
	A.step_month(gs)
	_check(gs.ambition.state == "lost", "and it stays lost after the peace")
	_check(gs.issue(Set.new("SRB", "")) and gs.ambition.is_empty(), "an ambition can be given up")
	var SG = load("res://scripts/sim/save_game.gd")
	gs.issue(Set.new("SRB", "great_power"))
	var snap: Dictionary = SG.snapshot(gs)
	_check(snap.state.has("ambition"), "and it is saved with the game")
	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)
