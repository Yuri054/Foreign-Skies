extends SceneTree
## Headless test for munitions: making them by the arms share, what the share costs in output, ageing and storage,
## burning them in battle and on a line facing the enemy, guns short of shells fighting weaker, buying abroad and the
## blockade's cut, the AI's arms share, and a save keeping the stockpile (and an older save migrating).
## Run: godot --headless --path . -s res://tests/munitions_test.gd

const DIR := "user://test_saves/"

var _failures := 0
var gs: Node
var clock: Node
var M
var E
var Mil
var UnitC


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", msg)
	else:
		print("ok:   ", msg)


func _fresh() -> void:
	gs.load_scenario("res://data/scenarios/jan_1900/")
	gs.join_calls.clear()
	gs.wars.clear()
	gs.set_player("ESP")
	gs.ai_enabled = false


func _army(tag: String, province: int, infantry: int, artillery: int):
	var a = Mil.new_army(gs, tag, "Test %s" % tag, province)
	for i in infantry:
		a.units.append(UnitC.new("infantry"))
	for i in artillery:
		a.units.append(UnitC.new("artillery"))
	return a


func _initialize() -> void:
	await process_frame
	gs = root.get_node("GameState")
	clock = root.get_node("Clock")
	M = load("res://scripts/sim/munitions.gd")
	E = load("res://scripts/sim/economy.gd")
	Mil = load("res://scripts/sim/military.gd")
	UnitC = load("res://scripts/sim/unit.gd")
	var Policy = load("res://scripts/sim/set_economy_policy.gd")
	var Buy = load("res://scripts/sim/buy_munitions.gd")
	var AB = load("res://scripts/ai/ai_budget.gd")
	var SaveGame = load("res://scripts/sim/save_game.gd")
	var c: Dictionary = M.cfg()

	# --- A scenario's start ------------------------------------------------------------------
	_fresh()
	var ger = gs.nations["GER"]
	_check(is_equal_approx(ger.arms_share, float(gs.scenario.munitions.share)), "nations start at the scenario's arms share (%.2f)" % ger.arms_share)
	_check(ger.munitions > 0.0 and absf(M.days_left(gs, "GER") - float(gs.scenario.munitions.days)) < 1.0, "with a stockpile for %d days of war" % roundi(M.days_left(gs, "GER")))

	# --- Making them, and what it costs ------------------------------------------------------
	_fresh()
	ger = gs.nations["GER"]
	gs.issue(Policy.new("GER", "arms_share", 0.0))
	E.recompute(gs)
	var gdp0: float = ger.budget.gdp
	var stock0: float = ger.munitions
	clock.advance_day()
	_check(is_equal_approx(ger.munitions, stock0), "at an arms share of 0 nothing is made")
	_check(gs.issue(Policy.new("GER", "arms_share", 0.2)) and is_equal_approx(ger.arms_share, 0.2), "the arms share is a policy, set by command")
	_check(not gs.issue(Policy.new("GER", "nonsense", 0.2)), "an unknown policy is refused")
	E.recompute(gs)
	_check(ger.budget.gdp < gdp0 * (1.0 - 0.2 * float(c.output_penalty)) + 0.01 and ger.budget.gdp > gdp0 * 0.9, "a fifth of the industry on arms costs %d%% of output" % roundi((1.0 - ger.budget.gdp / gdp0) * 100.0))
	var pool: float = ger.budget.construction_points
	stock0 = ger.munitions
	clock.advance_day()
	_check(absf(ger.munitions - stock0 - pool * 0.2) < pool * 0.05, "a day makes a fifth of the IC into munitions (%.0f of %.0f)" % [ger.munitions - stock0, pool])
	_check(ger.construction_used >= pool * 0.2 - 0.01, "and that share is not there for building")
	var storage: float = ger.budget.munitions_storage
	_check(storage > 0.0 and is_equal_approx(storage, ger.munitions * float(c.storage_cost)) or absf(storage - ger.munitions * float(c.storage_cost)) < 0.01, "a stockpile costs money to keep (£%.2fM a year)" % storage)
	var before: float = ger.munitions
	gs.issue(Policy.new("GER", "arms_share", 0.0))
	M.step_month(gs)
	_check(is_equal_approx(ger.munitions, before * (1.0 - float(c.decay_per_year) / 12.0)), "and it ages: %.1f%% a month" % (float(c.decay_per_year) / 12.0 * 100.0))

	# --- Burning them --------------------------------------------------------------------------
	_fresh()
	gs.set_war("FRA", "GER", true)
	var place: int = gs.nations["GER"].provinces[0]
	gs.armies.clear()
	var g = _army("GER", place, 4, 4)
	var f = _army("FRA", place, 4, 4)
	ger = gs.nations["GER"]
	var fra = gs.nations["FRA"]
	ger.munitions = 1.0e6
	fra.munitions = 1.0e6
	gs.issue(Policy.new("GER", "arms_share", 0.0))
	gs.issue(Policy.new("FRA", "arms_share", 0.0))
	var guns: float = M.gun_power(g)
	_check(guns > 0.0 and is_equal_approx(guns, g.power() * g.shelling_share()), "an army's guns have power of their own (%.1f)" % guns)
	clock.advance_day()
	_check(1.0e6 - ger.munitions >= guns * float(c.per_gun_power) * 0.9, "a day of battle burns the guns' need (%.0f)" % (1.0e6 - ger.munitions))
	_check(is_equal_approx(ger.shell_ratio, 1.0), "and with a full stockpile the guns get all of it")
	ger.munitions = 0.0
	clock.advance_day()
	_check(ger.shell_ratio < 0.01, "with none left the guns get nothing")
	_check(is_equal_approx(M.power_factor(g, 0.0), 1.0 - g.shelling_share() * float(Mil.cfg.combat.shell_penalty)), "and fight with their share of the army's power cut by the shell penalty (x%.2f)" % M.power_factor(g, 0.0))
	_check(is_equal_approx(M.power_factor(g, 1.0), 1.0), "while guns with their shells fight in full")
	var plain = _army("GER", gs.nations["GER"].provinces[1], 6, 0)
	_check(is_equal_approx(M.power_factor(plain, 0.0), 1.0), "an army with no guns needs no shells")

	# A line facing the enemy burns a share even with no battle.
	_fresh()
	gs.set_war("FRA", "GER", true)
	gs.armies.clear()
	var front := 0
	var across := 0
	for id: int in gs.nations["GER"].provinces:
		for n: int in Mil.neighbors(id):
			if gs.province_owner[n] == "FRA":
				front = id
				across = n
	g = _army("GER", front, 4, 4)
	f = _army("FRA", across, 4, 4)
	ger = gs.nations["GER"]
	ger.munitions = 1.0e6
	gs.issue(Policy.new("GER", "arms_share", 0.0))
	var line_burn: Dictionary = M.burn(gs, {}, {front: [g], across: [f]})
	_check(1.0e6 - ger.munitions > 0.0 and absf((1.0e6 - ger.munitions) - M.gun_power(g) * float(c.per_gun_power) * float(c.idle_share)) < 0.01, "an army facing an enemy across the line burns %d%% of a battle's need" % roundi(float(c.idle_share) * 100.0))
	_check(line_burn.GER == 1.0, "and gets it")

	# --- Buying abroad --------------------------------------------------------------------------
	_fresh()
	var esp = gs.nations["ESP"]
	esp.treasury = 50.0
	var s0: float = esp.munitions
	var buy = Buy.new("ESP", 10.0)
	_check(gs.issue(buy) and is_equal_approx(esp.treasury, 40.0) and is_equal_approx(esp.munitions - s0, 10.0 / float(c.import_price)), "£10M buys %d IC of munitions abroad" % roundi(buy.bought))
	esp.blockade = 0.5
	s0 = esp.munitions
	gs.issue(Buy.new("ESP", 10.0))
	_check(is_equal_approx(esp.munitions - s0, 0.5 * 10.0 / float(c.import_price)), "a blockade cuts what arrives")
	esp.treasury = 1.0
	_check(not gs.issue(Buy.new("ESP", 10.0)), "and nothing is bought on credit")

	# --- The AI ---------------------------------------------------------------------------------
	_fresh()
	var ai: Dictionary = load("res://scripts/ai/ai.gd").cfg.munitions
	gs.tension = 20.0
	var calm: float = AB.wanted_arms_share(gs, "ITA")
	gs.tension = 80.0
	_check(AB.wanted_arms_share(gs, "ITA") > calm, "the AI arms more as tension rises (%.2f to %.2f)" % [calm, AB.wanted_arms_share(gs, "ITA")])
	gs.nations["ITA"].mobilization = 0.5
	_check(is_equal_approx(AB.wanted_arms_share(gs, "ITA"), float(ai.crisis_share)), "a good deal when mobilized")
	gs.set_war("ITA", "AUH", true)
	_check(is_equal_approx(AB.wanted_arms_share(gs, "ITA"), float(ai.war_share)), "most at war")
	gs.nations["ITA"].munitions = 0.0
	gs.nations["ITA"].treasury = 100.0
	var t0: float = gs.nations["ITA"].treasury
	AB._arms(gs, "ITA")
	_check(gs.nations["ITA"].treasury < t0 and gs.nations["ITA"].munitions > 0.0, "and buys abroad when its stockpile runs low")

	# --- A save keeps it ------------------------------------------------------------------------
	_fresh()
	ger = gs.nations["GER"]
	ger.munitions = 12345.0
	ger.arms_share = 0.33
	DirAccess.make_dir_recursive_absolute(DIR)
	_check(SaveGame.write(gs, DIR + "munitions.sav") == "" and SaveGame.read(gs, DIR + "munitions.sav") == "", "a game with munitions saves and loads")
	ger = gs.nations["GER"]
	_check(is_equal_approx(ger.munitions, 12345.0) and is_equal_approx(ger.arms_share, 0.33), "and keeps the stockpile and the arms share")
	# A version 2 save (before munitions) starts at the usual share.
	var snap: Dictionary = SaveGame.snapshot(gs)
	var flat: Array = snap.state.nations["@m"]
	for i in range(1, flat.size(), 2):
		flat[i].p.erase("arms_share")
		flat[i].p.erase("munitions")
	SaveGame._migrate(snap.state, 2)
	_check(flat[1].p.get("arms_share", -1.0) == float(c.default_share), "an older save is brought up to date with the usual arms share")

	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)
