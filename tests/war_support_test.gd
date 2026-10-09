extends SceneTree
## Headless test for war support: starting values, what moves it, what it scales, and how
## weary nations are forced to terms.
## Run: godot --headless --path . -s res://tests/war_support_test.gd
## Class names are loaded at runtime because this script compiles before the autoloads exist.

var _failures := 0
var gs: Node
var clock: Node
var W
var P
var D
var Mil
var Eco
var UnitC
var DeclareC


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
	W = load("res://scripts/sim/war_support.gd")
	P = load("res://scripts/sim/peace.gd")
	D = load("res://scripts/sim/diplomacy.gd")
	Mil = load("res://scripts/sim/military.gd")
	Eco = load("res://scripts/sim/economy.gd")
	UnitC = load("res://scripts/sim/unit.gd")
	DeclareC = load("res://scripts/sim/declare_war.gd")

	_test_start_and_curves()
	_test_effects()
	_test_combat()
	_test_dynamics()
	_test_declaring()
	_test_forced_peace()
	_test_terms()

	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)


## A quiet world with France and Germany at war and the player in neutral Spain.
func _war() -> Object:
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	gs.join_calls.clear()
	gs.scenario["war_plans"] = []
	gs.wars.clear()
	gs.armies.clear()
	gs.set_player("ESP")
	gs.set_war("FRA", "GER", true)
	return gs.war_between("FRA", "GER")


func _occupy(owner: String, by: String, count: int) -> Array:
	var ids: Array = []
	for id: int in gs.nations[owner].provinces:
		if ids.size() >= count:
			break
		if id != gs.nations[owner].capital:
			gs.set_controller(id, by)
			ids.append(id)
	return ids


func _test_start_and_curves() -> void:
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	_check(gs.nations["GER"].war_support == 70.0 and gs.nations["GER"].war_support_base == 70.0, "the scenario sets Germany's mood (70)")
	_check(gs.nations["ESP"].war_support == 60.0, "a constitutional monarchy without its own figure starts at 60")
	_check(W.start_value("republic") == 55.0 and W.start_value("anarchy") == 55.0, "a republic 55, an unknown government the default")
	_war()
	var ger = gs.nations["GER"]
	ger.war_support = 0.0
	_check(is_equal_approx(W.economy_mult(gs, "GER"), 0.7) and is_equal_approx(W.morale_mult(gs, "GER"), 0.75), "at zero support: 70% economy, 75% fighting power")
	ger.war_support = 25.0
	_check(is_equal_approx(W.economy_mult(gs, "GER"), 0.85) and is_equal_approx(W.morale_mult(gs, "GER"), 0.875), "the curve is linear below 50")
	ger.war_support = 50.0
	_check(W.economy_mult(gs, "GER") == 1.0 and W.morale_mult(gs, "GER") == 1.0, "neutral at 50")
	ger.war_support = 100.0
	_check(W.economy_mult(gs, "GER") == 1.0 and is_equal_approx(W.morale_mult(gs, "GER"), 1.1), "full support adds 10% to fighting power but nothing to the economy")
	ger.war_support = 0.0
	_check(W.economy_mult(gs, "ESP") == 1.0 and W.morale_mult(gs, "ITA") == 1.0, "peaceful nations are unaffected")
	gs.set_war("FRA", "GER", false)
	_check(W.economy_mult(gs, "GER") == 1.0 and W.morale_mult(gs, "GER") == 1.0, "and so is a nation once its war is over, whatever its mood")


func _test_effects() -> void:
	_war()
	var ger = gs.nations["GER"]
	ger.war_support = 50.0
	Eco.recompute(gs)
	var rev50: float = ger.budget.revenue
	ger.war_support = 0.0
	Eco.recompute(gs)
	var rev0: float = ger.budget.revenue
	_check(rev0 < rev50 * 0.9 and rev0 > rev50 * 0.6, "tax revenue falls with war support (%.1f at 50, %.1f at 0)" % [rev50, rev0])
	gs.set_war("FRA", "GER", false)
	Eco.recompute(gs)
	_check(is_equal_approx(ger.budget.revenue, rev50), "and returns in peace")
	gs.set_war("FRA", "GER", true)

	ger.mobilization = 1.0  # a roomy cap, so one month's recruiting does not fill it
	Eco.recompute(gs)
	ger.war_support = 50.0
	ger.manpower = 0
	Eco.step_month(gs)
	var recruits50: int = ger.manpower
	ger.war_support = 0.0
	ger.manpower = 0
	Eco.step_month(gs)
	_check(recruits50 > 0 and ger.manpower < recruits50 * 0.8, "recruitment falls too (%d at 50, %d at 0)" % [recruits50, ger.manpower])


func _loss_ratio(ger_support: float, fra_support: float) -> float:
	var war = _war()
	var home := 0
	for id: int in gs.nations["FRA"].provinces:
		home = id
		break
	var a = Mil.new_army(gs, "FRA", "French", home)
	var b = Mil.new_army(gs, "GER", "German", home)
	for i in 5:
		a.units.append(UnitC.new("infantry"))
		b.units.append(UnitC.new("infantry"))
	gs.nations["GER"].war_support = ger_support
	gs.nations["FRA"].war_support = fra_support
	for i in 4:
		clock.days_elapsed += 1
		Mil.step_day(gs)
	return war.losses["GER"] / maxf(war.losses["FRA"], 1.0)


func _test_combat() -> void:
	var even := _loss_ratio(50.0, 50.0)
	var weak := _loss_ratio(0.0, 100.0)
	_check(even > 0.0 and weak > even * 1.3, "a nation with no support loses more men than its enemy (%.2f against %.2f)" % [weak, even])
	var strong := _loss_ratio(100.0, 0.0)
	_check(strong < even * 0.8, "and one with full support loses fewer (%.2f)" % strong)


func _test_dynamics() -> void:
	var war = _war()
	var ger = gs.nations["GER"]
	var ita = gs.nations["ITA"]
	ita.war_support = 20.0
	W.step_month(gs)
	_check(is_equal_approx(ita.war_support, 23.0), "in peace support climbs back to its base, 3 a month (%.1f)" % ita.war_support)
	ita.war_support = 39.0
	W.step_month(gs)
	_check(ita.war_support == 40.0, "without overshooting it")
	ger.war_support = 60.0
	W.step_month(gs)
	_check(is_equal_approx(ger.war_support, 59.5), "at war it loses half a point a month to weariness")
	ger.war_support = 60.0
	ger.manpower = 1000000
	ger.men_lost_month = 0.1 * ger.total_men() / 0.9
	W.step_month(gs)
	_check(absf(ger.war_support - (60.0 - 0.5 - 15.0)) < 0.05, "losing a tenth of its men in a month costs 15 (%.2f)" % ger.war_support)
	_check(ger.men_lost_month == 0.0, "the monthly tally is reset")
	ger.war_support = 60.0
	ger.blockade = 1.0
	W.step_month(gs)
	_check(is_equal_approx(ger.war_support, 49.5), "a full blockade costs 10")
	ger.blockade = 0.0
	ger.war_support = 60.0
	_occupy("GER", "FRA", 20)
	var share: float = W.occupied_share(gs, "GER")
	W.step_month(gs)
	_check(share > 0.0 and is_equal_approx(ger.war_support, 60.0 - 0.5 - 20.0 * share), "enemy-held ground costs 20 times the share of people under it (%.1f%% held)" % (share * 100.0))
	for id: int in gs.nations["GER"].provinces:
		gs.set_controller(id, "GER")

	var fra_home := 0
	for id: int in gs.nations["FRA"].provinces:
		fra_home = id
		break
	var ger_home: int = gs.nations["GER"].provinces[0]
	gs.nations["FRA"].war_support = 50.0
	gs.nations["GER"].war_support = 50.0
	W.on_battle(gs, {"winner": "FRA", "loser": "GER", "province": fra_home})
	_check(gs.nations["FRA"].war_support == 53.0 and gs.nations["GER"].war_support == 48.5, "a victory at home lifts the winner by 3 and lowers the loser by 1.5")
	W.on_battle(gs, {"winner": "FRA", "loser": "GER", "province": ger_home})
	_check(gs.nations["FRA"].war_support == 55.0, "a victory abroad lifts it by 2")
	W.on_battle(gs, {"winner": "", "loser": "", "province": ger_home})
	_check(gs.nations["FRA"].war_support == 55.0, "a drawn battle changes nothing")
	var seen := []
	gs.war_support_changed.connect(func(tag: String, v: float) -> void: seen.append(tag))
	W.change(gs, "FRA", 500.0)
	_check(gs.nations["FRA"].war_support == 100.0 and seen == ["FRA"], "support is capped at 100 and a signal says so")
	W.change(gs, "FRA", 5.0)
	_check(seen == ["FRA"], "no signal when nothing moved")
	_check(war != null, "the war stood throughout")


func _test_declaring() -> void:
	_war()
	gs.set_war("FRA", "GER", false)
	var ger = gs.nations["GER"]
	var fra = gs.nations["FRA"]
	var before: float = fra.war_support
	_check(gs.issue(DeclareC.new("FRA", "GER", "reconquest")), "France declares to reconquer Alsace-Lorraine")
	_check(fra.war_support == before + 5.0, "a just cause raises support by 5 (%.1f)" % fra.war_support)
	_war()
	gs.set_war("FRA", "GER", false)
	ger = gs.nations["GER"]
	ger.mobilization = 0.5
	var g_before: float = ger.war_support
	_check(gs.issue(DeclareC.new("GER", "BEL", "none")), "Germany declares on Belgium without a cause")
	_check(ger.war_support == g_before - 10.0, "which costs it 10")
	_check(gs.nations["BEL"].war_support == 70.0, "the victim's support is untouched")


func _test_forced_peace() -> void:
	var war = _war()
	gs.nations["GER"].war_support = 10.0
	gs.nations["FRA"].war_support = 60.0
	W.step_month(gs)
	_check(not gs.at_war("FRA", "GER") and war.peace.white, "a nation whose support has collapsed is forced into a white peace")
	_check(war.log.back().kind == "peace" or war.log[war.log.size() - 2].kind == "peace", "with a record of it")
	_check(war.peace.terms.is_empty() and "fight on" in war.log.back().text + war.log[war.log.size() - 2].text, "that says why")

	# Clearly losing nations are not let off: the enemy dictates.
	war = _war()
	_occupy("GER", "FRA", 200)
	gs.nations["GER"].war_support = 10.0
	gs.nations["FRA"].war_support = 60.0
	W.step_month(gs)
	_check(P.war_score(gs, war, "GER") < -20.0 and gs.at_war("FRA", "GER"), "one that is also clearly losing stays at war (%.1f)" % P.war_score(gs, war, "GER"))

	# Even a winning nation is forced if its people will not fight on.
	war = _war()
	_occupy("GER", "FRA", 30)
	gs.nations["GER"].war_support = 60.0
	gs.nations["FRA"].war_support = 10.0
	var lead: float = P.war_score(gs, war, "FRA")
	W.step_month(gs)
	_check(lead > 0.0 and not gs.at_war("FRA", "GER"), "and so is a winner whose people have had enough (lead %.1f)" % lead)


func _test_terms() -> void:
	# At zero support a nation can be made to give anything.
	var war = _war()
	_occupy("GER", "FRA", 1)
	var dear: Array = [{"kind": "indemnity", "share": 0.5, "months": 60}]
	var c: Dictionary = P.check(gs, "FRA", "GER", "demand", dear)
	_check(not c.ok and c.reason == "too_expensive", "a modest lead does not pay for a heavy indemnity")
	gs.nations["GER"].war_support = 0.0
	c = P.check(gs, "FRA", "GER", "demand", dear)
	_check(c.ok and c.forced, "but a nation with no support left must pay it anyway")

	# At the floor an AI takes terms it can afford even when it is not losing.
	war = _war()
	var cheap := 0
	for id: int in gs.nations["GER"].provinces:
		if id != gs.nations["GER"].capital and (cheap == 0 or P.province_share(gs, id, "GER") < P.province_share(gs, cheap, "GER")):
			cheap = id
	gs.set_controller(cheap, "FRA")
	var terms: Array = [{"kind": "province", "ids": [cheap]}]
	gs.nations["GER"].war_support = 40.0
	var r: Dictionary = P.propose(gs, "FRA", "GER", "demand", terms)
	_check(r.ok and r.accepted == false, "with support at 40 Germany refuses a small loss")
	gs.peace_cooldown.clear()
	gs.nations["GER"].war_support = 25.0
	r = P.propose(gs, "FRA", "GER", "demand", terms)
	_check(r.accepted == true and not gs.at_war("FRA", "GER"), "at the floor (25) it takes the terms")

	# A weary AI asks for peace on its own.
	war = _war()
	gs.nations["GER"].war_support = 22.0
	D.step_month(gs)
	_check(not gs.at_war("FRA", "GER") and war.peace.white, "an AI nation near the floor sues for a white peace")
