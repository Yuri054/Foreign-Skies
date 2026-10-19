extends SceneTree
## Headless test of economy laws: they start in peacetime, higher ones need a war or mobilization,
## a change has a wait, the consumer share sets construction points, output falls and war support
## weakens with the heavier laws, a law whose war is over is dropped, and the law survives a save.
## Run: godot --headless --path . -s res://tests/economy_laws_test.gd

var _failures := 0
var gs: Node
var Clock: Node
var Eco
var SetLaw
var Policy
var War


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
	Eco = load("res://scripts/sim/economy.gd")
	SetLaw = load("res://scripts/sim/set_economy_law.gd")
	Policy = load("res://scripts/sim/set_economy_policy.gd")
	_fresh()
	_test_start_and_gates()
	_test_effects()
	_test_cooldown()
	_test_weariness()
	_test_dropped()
	_test_mobilization()
	_test_save_and_ui()
	await _test_panel()
	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)


func _fresh() -> void:
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	gs.join_calls.clear()
	gs.wars.clear()
	gs.ai_enabled = false


func _war(a: String, b: String) -> void:
	gs.set_war(a, b, true)


func _test_start_and_gates() -> void:
	var fra = gs.nations["FRA"]
	_check(Eco.law_ids() == ["civilian", "early_mobilization", "war_economy", "total_mobilization"], "four laws, from peace to total war")
	_check(fra.economy_law == "civilian" and fra.budget.law == "civilian", "a nation starts on the civilian economy")
	_check(is_equal_approx(fra.budget.consumer_share, 0.35), "with 35% of the factories' work on consumer goods")
	var cmd = SetLaw.new("FRA", "war_economy")
	_check(not gs.issue(cmd) and cmd.reason == "Needs a war.", "a war economy needs a war: " + cmd.reason)
	cmd = SetLaw.new("FRA", "early_mobilization")
	_check(not gs.issue(cmd) and "mobilization" in cmd.reason, "early mobilization needs a war or mobilization: " + cmd.reason)
	gs.issue(Policy.new("FRA", "mobilization", 0.25))
	_check(gs.issue(SetLaw.new("FRA", "early_mobilization")) and fra.economy_law == "early_mobilization", "with a quarter mobilized it is allowed")
	_check(not gs.issue(SetLaw.new("FRA", "early_mobilization")), "taking the law already in force does nothing")
	_check(not gs.issue(SetLaw.new("FRA", "bogus")) and not gs.issue(SetLaw.new("XXX", "civilian")), "unknown laws and nations are refused")
	_war("FRA", "GER")
	fra.law_changed_day = -1000
	cmd = SetLaw.new("FRA", "total_mobilization")
	_check(not gs.issue(cmd) and "50%" in cmd.reason, "total mobilization needs half the nation mobilized: " + cmd.reason)
	gs.issue(Policy.new("FRA", "mobilization", 0.6))
	_check(gs.issue(SetLaw.new("FRA", "total_mobilization")), "and at war with 60% it is allowed")
	_check(gs.issue(SetLaw.new("FRA", "civilian")), "going back down is always allowed")


func _test_effects() -> void:
	_fresh()
	var ger = gs.nations["GER"]
	_war("GER", "FRA")
	var pool0: float = ger.budget.construction_points
	var gdp0: float = ger.budget.gdp
	ger.law_changed_day = -1000
	_check(gs.issue(SetLaw.new("GER", "war_economy")), "Germany goes to a war economy")
	var civ: float = ger.budget.factories
	_check(is_equal_approx(ger.budget.construction_points, Eco.construction_points(ger, civ, ger.budget.trade_lock)), "20%% on consumer goods leaves more construction points (%.1f from %.1f)" % [ger.budget.construction_points, pool0])
	_check(ger.budget.construction_points > pool0, "so there are more points a day")
	_check(absf(ger.budget.gdp / gdp0 - Eco.cfg.laws.war_economy.gdp) < 0.002, "and national output falls to %d%%" % roundi(100.0 * ger.budget.gdp / gdp0))
	_check(Eco.law_of(ger).military == 1.25, "military factories will make 25 percent more")


func _test_cooldown() -> void:
	_fresh()
	var ger = gs.nations["GER"]
	_war("GER", "FRA")
	_check(gs.issue(SetLaw.new("GER", "early_mobilization")), "a first change is allowed")
	var cmd = SetLaw.new("GER", "war_economy")
	_check(not gs.issue(cmd) and "Wait" in cmd.reason, "a higher law at once is refused: " + cmd.reason)
	_check(gs.issue(SetLaw.new("GER", "civilian")), "but a lower one is not held up")
	for i in int(Eco.cfg.laws.cooldown_days):
		Clock.advance_day()
	_check(gs.issue(SetLaw.new("GER", "war_economy")), "after the wait the higher law can be taken")


func _test_weariness() -> void:
	_fresh()
	var ger = gs.nations["GER"]
	var fra = gs.nations["FRA"]
	_war("GER", "FRA")
	ger.law_changed_day = -1000
	gs.issue(SetLaw.new("GER", "war_economy"))
	var WarSupport = load("res://scripts/sim/war_support.gd")
	var g0: float = ger.war_support
	var f0: float = fra.war_support
	WarSupport.step_month(gs)
	var lost_ger: float = g0 - ger.war_support
	var lost_fra: float = f0 - fra.war_support
	_check(lost_ger > lost_fra and absf((lost_ger - lost_fra) - Eco.cfg.laws.war_economy.weariness) < 0.01, "a war economy costs %.1f war support more a month than the civilian one" % (lost_ger - lost_fra))


func _test_dropped() -> void:
	_fresh()
	var ger = gs.nations["GER"]
	_war("GER", "FRA")
	ger.law_changed_day = -1000
	gs.issue(SetLaw.new("GER", "war_economy"))
	gs.set_war("GER", "FRA", false)
	Eco.enforce_laws(gs)
	_check(ger.economy_law != "war_economy" and ger.economy_law != "total_mobilization", "when the war ends the war economy is dropped")
	ger.mobilization = 0.0
	Eco.enforce_laws(gs)
	_check(ger.economy_law == "civilian", "and with no mobilization either, back to the civilian economy")


func _test_mobilization() -> void:
	_fresh()
	var fra = gs.nations["FRA"]
	var civil: Dictionary = Eco.cfg.laws.civilian
	_check(Eco.mobilization_range(fra) == Vector2(0.0, 0.4), "the civilian economy allows up to 40% mobilization")
	gs.issue(Policy.new("FRA", "mobilization", 1.0))
	_check(is_equal_approx(fra.mobilization, 0.4), "the slider stops at the law's ceiling (%.2f)" % fra.mobilization)
	fra.mobilization = 0.9
	var D = load("res://scripts/sim/diplomacy.gd")
	D.step_day(gs)
	_check(is_equal_approx(fra.mobilization, 0.4), "and a nation above it is brought down at once")
	# At war the war floor lifts the ceiling.
	_war("FRA", "GER")
	_check(is_equal_approx(Eco.mobilization_cap(gs, fra), 0.5), "at war a nation may always reach the war floor")
	gs.issue(Policy.new("FRA", "mobilization", 1.0))
	_check(is_equal_approx(fra.mobilization, 0.5), "but no higher under the civilian economy (%.2f)" % fra.mobilization)
	# A higher law lifts the ceiling and sets a floor.
	fra.law_changed_day = -1000
	gs.issue(SetLaw.new("FRA", "early_mobilization"))
	gs.issue(Policy.new("FRA", "mobilization", 1.0))
	_check(is_equal_approx(fra.mobilization, 0.7), "early mobilization allows 70%% (%.2f)" % fra.mobilization)
	fra.law_changed_day = -1000
	fra.mobilization = 0.6
	gs.issue(SetLaw.new("FRA", "war_economy"))
	fra.mobilization = 0.1
	for i in 6:
		D.step_day(gs)
	_check(fra.mobilization >= 0.3, "a law's floor raises mobilization a step a day (%.2f)" % fra.mobilization)
	# Called-up workers cost the factories' output.
	_fresh()
	fra = gs.nations["FRA"]
	var Prod = load("res://scripts/sim/production.gd")
	var line = fra.production_lines[0]
	var full: float = Prod.capacity(fra, line)
	var points: float = Eco.construction_points(fra, 50.0)
	fra.men_in_units = int(fra.population * 0.2)
	_check(is_equal_approx(Eco.worker_share(fra), 1.0 - Eco.cfg.labor.penalty * 0.2), "workers called up leave the factories (%.2f)" % Eco.worker_share(fra))
	_check(Prod.capacity(fra, line) < full and Eco.construction_points(fra, 50.0) < points, "so production and construction slow")


func _test_save_and_ui() -> void:
	var SaveGame = load("res://scripts/sim/save_game.gd")
	SaveGame.dir = "user://test_law_saves/"
	_fresh()
	var ger = gs.nations["GER"]
	_war("GER", "FRA")
	ger.law_changed_day = -1000
	gs.issue(SetLaw.new("GER", "war_economy"))
	var path: String = SaveGame.dir + "law.sav"
	_check(gs.save_game(path) == "", "a game under a war economy saves")
	_fresh()
	_check(gs.load_game(path) == "" and gs.nations["GER"].economy_law == "war_economy", "and loads with the law in force")
	DirAccess.remove_absolute(path)


func _test_panel() -> void:
	_fresh()
	gs.set_player("GER")
	gs.pending_joins.clear()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	for p in get_nodes_in_group("nation_picker"):
		p.queue_free()
	var eco: Node = get_first_node_in_group("economy_panel")
	eco.toggle()
	await process_frame
	_check(eco._law.item_count == 4, "the Economy window has a law selector with four laws")
	_check(eco._law.get_item_text(eco._law.selected) == "Civilian economy", "showing the law in force")
	_check(eco._law.is_item_disabled(2) and "war" in eco._law.get_item_tooltip(2).to_lower(), "a war economy is greyed in peace, with the reason: " + eco._law.get_item_tooltip(2).replace("
", " "))
	_check(not eco._law.is_item_disabled(0), "the current law is not greyed")
	_war("GER", "FRA")
	eco._refresh()
	_check(not eco._law.is_item_disabled(2) and eco._law.is_item_disabled(3), "at war the war economy opens, total mobilization still needs mobilizing")
	gs.nations["GER"].law_changed_day = -1000
	eco._law.item_selected.emit(2)
	_check(gs.nations["GER"].economy_law == "war_economy" and eco._law_note.text.contains("20%"), "choosing it puts it in force and the note says what it does: " + eco._law_note.text)
	main.queue_free()
