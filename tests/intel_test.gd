extends SceneTree
## Headless test of what the player can see of other armies (Intel): their own and their allies'
## exactly, enemies and bordering armies as estimates, the rest not at all.
## Run: godot --headless --path . -s res://tests/intel_test.gd

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
	var Intel = load("res://scripts/sim/intel.gd")
	var Mil = load("res://scripts/sim/military.gd")
	var Dip = load("res://scripts/sim/diplomacy.gd")
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	gs.join_calls.clear()
	gs.wars.clear()
	gs.set_player("FRA")

	var counts := {Intel.HIDDEN: 0, Intel.ESTIMATE: 0, Intel.EXACT: 0}
	var by_level := {Intel.HIDDEN: [], Intel.ESTIMATE: [], Intel.EXACT: []}
	for a in gs.armies.values():
		var l: int = Intel.level(gs, a)
		counts[l] += 1
		by_level[l].append(a)
	_check(counts[Intel.EXACT] > 0 and counts[Intel.ESTIMATE] > 0 and counts[Intel.HIDDEN] > 0, "a French player sees some armies exactly, some roughly and some not at all (%d, %d, %d)" % [counts[Intel.EXACT], counts[Intel.ESTIMATE], counts[Intel.HIDDEN]])
	for a in by_level[Intel.EXACT]:
		if a.tag != "FRA" and not Dip.are_allied(gs, "FRA", a.tag):
			_check(false, "%s armies are shown exactly but are not French or allied" % a.tag)
	for a in gs.armies.values():
		if a.tag == "FRA":
			if Intel.level(gs, a) != Intel.EXACT:
				_check(false, "a French army is not shown exactly")
	_check(true, "every French army is seen exactly")
	var ally = null
	for a in by_level[Intel.EXACT]:
		if a.tag != "FRA":
			ally = a
	_check(ally != null and Intel.men_seen(gs, ally) == ally.men(), "an allied army is seen exactly (%s)" % (ally.tag if ally != null else "none"))

	# Estimates: rounded, close to the truth, steady, and different for different armies.
	var guess = by_level[Intel.ESTIMATE][0]
	var shown: float = Intel.men_seen(gs, guess)
	_check(shown > 0.0 and absf(shown - guess.men()) <= guess.men() * Intel.ERROR + 5000.0, "an estimate is near the truth (%d of %d)" % [shown, guess.men()])
	_check(Intel.men_seen(gs, guess) == shown, "and is the same each time it is asked")
	_check(fmod(shown, 1000.0) == 0.0, "and is rounded")
	var unique := {}
	for a in by_level[Intel.ESTIMATE]:
		unique[snappedf(Intel.men_seen(gs, a) / maxf(a.men(), 1.0), 0.01)] = true
	_check(unique.size() > 1, "the error differs from army to army")
	var hidden = by_level[Intel.HIDDEN][0]
	_check(Intel.men_seen(gs, hidden) == 0.0, "a hidden army adds nothing to what is known")
	_check(Intel.estimate_text(120000.0).begins_with("~"), "estimate text starts with a tilde")

	# An enemy is seen as an estimate even far away.
	var far = hidden
	_check(not gs.at_war("FRA", far.tag), "the hidden army belongs to a nation France is not at war with (%s)" % far.tag)
	gs.set_war(far.tag, "FRA", true)
	await process_frame
	_check(Intel.level(gs, far) == Intel.ESTIMATE, "once at war its armies are seen as estimates wherever they stand")
	gs.set_war(far.tag, "FRA", false)
	_check(Intel.level(gs, far) == Intel.HIDDEN, "and hidden again at peace")

	# An ally's enemy is the player's enemy too.
	var ally_tag: String = ally.tag
	var foe = null
	for a in by_level[Intel.HIDDEN]:
		if a.tag != far.tag and not Dip.are_allied(gs, "FRA", a.tag) and a.tag != ally_tag:
			foe = a
			break
	if foe != null:
		gs.set_war(ally_tag, foe.tag, true)
		_check(Intel.level(gs, foe) == Intel.ESTIMATE, "an ally's enemy is seen as an estimate (%s)" % foe.tag)
		gs.set_war(ally_tag, foe.tag, false)

	# Next to ground the player holds an unknown army shows; far from it, it does not.
	var border := 0
	for id in range(1, gs.province_owner.size()):
		if gs.province_controller[id] == "FRA":
			for n in Mil.neighbors(id):
				if gs.province_controller[n] != "FRA" and not Dip.are_allied(gs, "FRA", gs.province_controller[n]):
					border = n
					break
		if border != 0:
			break
	_check(border != 0 and Intel.sees_province(gs, border), "a province next to French ground is watched")
	var faraway := 0
	for id in range(1, gs.province_owner.size()):
		if not Intel.sees_province(gs, id):
			faraway = id
			break
	_check(faraway != 0, "and one far from every friend is not")

	# With nobody playing everything is shown.
	gs.player_tag = ""
	_check(Intel.level(gs, hidden) == Intel.EXACT, "with no player yet every army is shown")

	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)
