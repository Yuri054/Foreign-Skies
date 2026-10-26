extends SceneTree
## Headless test for step 5's public stand: one stand at a time for any nation; a call for calm weighs as much as the
## nation making it (a great power's at high tension about as strong as the old conference of the powers), a rattled
## sabre costs the goodwill of the neighbours; the conference and "on the brink" events are gone.
## Run: godot --headless --path . -s res://tests/public_stand_test.gd

var _failures := 0
var gs: Node
var P


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", msg)
	else:
		print("ok:   ", msg)


func _initialize() -> void:
	await process_frame
	gs = root.get_node("GameState")
	P = load("res://scripts/sim/pressure.gd")
	var AppealC = load("res://scripts/sim/appeal.gd")
	var D = load("res://scripts/sim/diplomacy.gd")
	gs.load_scenario("res://data/scenarios/jan_1900/")
	gs.ai_enabled = false
	gs.set_player("BEL")
	var calm: Dictionary = P.cfg.appeals.calm
	gs.tension = 75.0
	gs.nations["GBR"].prestige = 40.0
	var great: float = -P.appeal_tension(gs, "GBR", "calm")
	var small: float = -P.appeal_tension(gs, "BEL", "calm")
	_check(great >= 10.0 and great <= float(calm.tension_max), "a great power's call for calm at high tension is about as strong as a conference of the powers (%.1f)" % great)
	_check(small > 0.0 and small < great / 2.0, "a small nation's carries less weight (%.1f)" % small)
	gs.tension = 25.0
	_check(-P.appeal_tension(gs, "GBR", "calm") < great, "and calm in a calm Europe matters less (%.1f)" % -P.appeal_tension(gs, "GBR", "calm"))
	# Rattling the sabre.
	gs.nations["BEL"].diplomacy_points = 100.0
	var near: Array = D.neighbor_nations(gs, "BEL")
	var before := {}
	for t: String in near:
		before[t] = D.relation(gs, t, "BEL")
	_check(gs.issue(AppealC.new("BEL", "rattle")), "Belgium rattles the sabre")
	var worse := true
	for t: String in near:
		worse = worse and D.relation(gs, t, "BEL") < before[t]
	_check(not near.is_empty() and worse, "and every neighbour thinks less of it (%s)" % ", ".join(near))
	_check(not gs.issue(AppealC.new("BEL", "calm")), "one stand at a time")
	# The old events are gone.
	var ids: Array = P.events.map(func(e: Dictionary) -> String: return e.id)
	_check(not ("concert" in ids) and not ("brink" in ids), "the conference and 'on the brink' events are gone")
	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)
