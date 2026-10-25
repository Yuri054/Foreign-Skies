extends SceneTree
## Headless test for the AI foundations: data, traits and plans, the stagger, quiet commands,
## the shared queries and determinism.
## Run: godot --headless --path . -s res://tests/ai_test.gd
## Class names are loaded at runtime because this script compiles before the autoloads exist.

var _failures := 0
var gs: Node
var clock: Node
var A
var Mil
var MoveC


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", msg)
	else:
		print("ok:   ", msg)


func _initialize() -> void:
	await process_frame
	gs = root.get_node("GameState")
	clock = root.get_node("Clock")
	A = load("res://scripts/ai/ai.gd")
	Mil = load("res://scripts/sim/military.gd")
	MoveC = load("res://scripts/sim/move_army.gd")

	_test_config()
	_test_traits_and_plans()
	_test_stagger()
	_test_issue_quiet()
	_test_queries()
	_test_determinism()

	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)


func _test_config() -> void:
	var c: Dictionary = A.cfg
	_check(int(c.think_days) >= 1, "ai.json gives a think interval")
	_check(c.temperament.default.has("aggression") and c.temperament.default.has("caution"), "the default temperament has aggression and caution")
	_check(float(c.odds.bold) < float(c.odds.cautious), "the bold want lower odds than the cautious")
	_check(float(c.unjustified_share_max) == 0.15, "unjustified wars are capped at 15%")
	_check(gs.ai_declarations == {"total": 0, "unjustified": 0}, "no AI declarations at the start")


func _test_traits_and_plans() -> void:
	gs.pressure_ai = false  # these check the AI's own constants, without tension's push
	gs.tension_bonus = 0.0
	_check(A.temperament(gs, "FRA") == A.cfg.temperament.default, "a nation without overrides has the default temperament")
	_check(A.province_named("Brussels") > 0 and A.province_named("Atlantis") == 0, "province names resolve, unknown ones give 0")
	# The shipped scenario has no overrides yet and its plans, if any, resolve.
	for plan: Dictionary in gs.ai_plans:
		_check(gs.nations.has(plan.nation) and gs.nations.has(plan.enemy), "plan %s against %s names real nations" % [plan.nation, plan.enemy])
		for o: Dictionary in plan.objectives:
			_check(o.province > 0 and o.province < gs.province_owner.size(), "plan objective %d is a real province" % o.province)
	# A scenario with overrides loads them. (It brings no plans: those are the AI's own.)
	var saved: Dictionary = gs.scenario.duplicate(true)
	gs.scenario["ai_traits"] = {"GER": {"aggression": 0.9}}
	gs.scenario["ai_plans"] = [{"nation": "GER", "enemy": "FRA", "posture": "offensive", "objectives": [{"province": "Paris"}]}]
	A.load_scenario(gs)
	var ger: Dictionary = A.temperament(gs, "GER")
	_check(ger.aggression == 0.9 and ger.caution == A.cfg.temperament.default.caution, "an override replaces one trait and keeps the other")
	_check(A.temperament(gs, "FRA") == A.cfg.temperament.default, "other nations keep the default")
	_check(gs.ai_plans.is_empty(), "a scenario cannot script a plan for a nation (the AI makes its own)")
	gs.scenario = saved
	A.load_scenario(gs)
	_check(gs.ai_traits.is_empty(), "reloading the scenario clears the overrides")


func _test_stagger() -> void:
	var interval: int = int(A.cfg.think_days)
	var seen := {}
	var start: int = clock.days_elapsed
	for d in interval:
		clock.days_elapsed = start + d
		for tag: String in A.due_nations(gs):
			seen[tag] = seen.get(tag, 0) + 1
	clock.days_elapsed = start
	var ai_count := 0
	var once := true
	for tag: String in gs.nations:
		if A.is_ai(gs, tag):
			ai_count += 1
			once = once and seen.get(tag, 0) == 1
	_check(ai_count > 0 and seen.size() == ai_count and once, "over one interval every AI nation thinks exactly once (%d nations)" % ai_count)
	_check(not A.is_ai(gs, gs.player_tag), "the player's nation is not played by the AI")
	var busiest := 0
	for d in interval:
		clock.days_elapsed = start + d
		busiest = maxi(busiest, A.due_nations(gs).size())
	clock.days_elapsed = start
	_check(busiest <= ceili(float(ai_count) / interval) + 1, "the work is spread evenly over the interval (busiest day %d)" % busiest)
	var tag0: String = gs.nations.keys()[0]
	_check(A.think_offset(gs, tag0) >= 0 and A.think_offset(gs, tag0) < interval, "a nation's offset lies within the interval")


func _test_issue_quiet() -> void:
	var tag := "FRA"
	var army = Mil.armies_of(gs, tag)[0]
	var dest := 0
	for n: int in Mil.neighbors(army.province):
		if Mil.can_enter(gs, tag, n):
			dest = n
			break
	var before: int = gs.command_log.size()
	gs.economy_dirty = false
	var ok: bool = gs.issue_quiet(MoveC.new(tag, army.id, dest))
	_check(ok and gs.command_log.size() == before + 1, "issue_quiet runs and logs the command")
	_check(not gs.economy_dirty, "an order to an army does not touch the economy")
	gs.issue_quiet(load("res://scripts/sim/set_economy_policy.gd").new(tag, "tax_rate", 0.2))
	_check(gs.economy_dirty, "a change of policy is left to the day's step to recompute")
	_check(not gs.issue_quiet(MoveC.new(tag, 99999, dest)) and gs.command_log.size() == before + 2, "a rejected quiet command is not logged")
	gs.load_scenario(gs.DEFAULT_SCENARIO)


func _test_queries() -> void:
	var cap: int = gs.nations["BEL"].capital
	var other: int = 0
	for id: int in gs.nations["BEL"].provinces:
		if id != cap:
			other = id
			break
	_check(A.value(gs, cap) > A.value(gs, other), "a capital is worth more than another province of similar size or less")
	var total := 0.0
	for id: int in gs.nations["BEL"].provinces:
		total += A.value(gs, id)
	_check(is_equal_approx(total, float(A.cfg.value.people) + float(A.cfg.value.output) + float(A.cfg.value.capital_bonus)),
			"a nation's provinces add up to its whole worth (%.3f)" % total)

	var fra = Mil.armies_of(gs, "FRA")[0]
	var fra_power: float = fra.power()
	_check(A.local_power(gs, "FRA", fra.province, 0) >= fra_power, "local power counts the armies standing in the province")
	_check(A.local_power(gs, "FRA", fra.province, 3) >= A.local_power(gs, "FRA", fra.province, 0), "a wider radius counts at least as much")
	_check(A.local_power(gs, "BEL", fra.province, 0) == 0.0, "another nation's armies are not counted")
	_check(A.supplied(gs, "FRA", fra.province), "an army on its own ground is supplied")

	# Threat: none at peace; with a war, it comes from the enemy's armies, falling with distance.
	_check(A.threat(gs, "FRA", fra.province) == 0.0, "no threat while at peace")
	gs.set_war("GER", "FRA", true)
	var here: float = A.threat(gs, "GER", fra.province)
	_check(here > 0.0, "an enemy army in the province is a threat to it")
	var next_door: int = Mil.neighbors(fra.province)[0]
	_check(A.threat(gs, "GER", next_door) > 0.0, "an enemy army next door still threatens")
	_check(A.threat(gs, "GER", gs.nations["GER"].capital) == 0.0, "an enemy far beyond reach does not")
	_check(A.threat(gs, "BEL", fra.province) == 0.0, "only the nations at war with it threaten")
	var raw: float = fra.power() * (1.0 + float(A.cfg.threat.stakes) * A.value(gs, fra.province))
	_check(here >= raw - 0.001, "threat is the enemy's power weighted by what is at stake")
	gs.load_scenario(gs.DEFAULT_SCENARIO)


func _test_determinism() -> void:
	var first := _run(30)
	var second := _run(30)
	_check(first == second, "the same scenario run twice gives the same command log and territory")


## Reloads the scenario, plays the days and returns a fingerprint of the result.
func _run(days: int) -> String:
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	for i in days:
		clock.advance_day()
	var owners := ",".join(gs.province_owner)
	var controllers := ",".join(gs.province_controller)
	return "%s|%s|%s" % [JSON.stringify(gs.command_log), owners, controllers]
