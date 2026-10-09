extends SceneTree
## Headless test for the AI's recruiting: when it raises units, where, what, and the limits.
## Run: godot --headless --path . -s res://tests/ai_forces_test.gd
## Class names are loaded at runtime because this script compiles before the autoloads exist.

var _failures := 0
var gs: Node
var clock: Node
var map: Node
var A
var Forces
var Def
var Mil
var UnitC


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
	map = root.get_node("MapData")
	A = load("res://scripts/ai/ai.gd")
	Forces = load("res://scripts/ai/ai_forces.gd")
	Def = load("res://scripts/ai/ai_defense.gd")
	Mil = load("res://scripts/sim/military.gd")
	UnitC = load("res://scripts/sim/unit.gd")

	_test_peace()
	_test_limits()
	_test_where_and_mix()
	_test_rebuild_and_stop()
	_test_no_spiral()

	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)


func _fresh() -> void:
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	gs.join_calls.clear()
	gs.wars.clear()
	for tag in gs.nations:
		gs.nations[tag].recruiting.clear()
	Mil.refresh_men(gs)
	gs.set_player("")


func _step(days: int) -> void:
	for i in days:
		clock.days_elapsed += 1
		A.step_day(gs)
		Mil.step_day(gs)


func _raises(tag: String) -> int:
	var n := 0
	for c in gs.command_log:
		if c.type == "RaiseUnits" and c.tag == tag:
			n += 1
	return n


## BEL at war with GER, a front drawn, and plenty of money and men unless a test says otherwise.
func _war() -> void:
	_fresh()
	gs.set_war("GER", "BEL", true)
	var n = gs.nations["BEL"]
	n.treasury = 100.0
	n.manpower = 500000
	Def.step(gs, "BEL")
	gs.economy_dirty = false
	Root_recompute()


func Root_recompute() -> void:
	load("res://scripts/sim/economy.gd").recompute(gs)


func _test_peace() -> void:
	_fresh()
	gs.nations["BEL"].treasury = 100.0
	_step(30)
	_check(_raises("BEL") == 0, "a nation at peace raises no units")
	gs.set_war("GER", "BEL", true)
	gs.set_war("GER", "BEL", false)
	_step(12)
	_check(_raises("BEL") == 0, "nor after the war is over")


func _test_limits() -> void:
	_war()
	Forces.step(gs, "BEL")
	_check(gs.nations["BEL"].recruiting.size() == int(A.cfg.forces.per_turn), "at war it starts per_turn units (%d)" % gs.nations["BEL"].recruiting.size())
	for i in 10:
		Forces.step(gs, "BEL")
	_check(gs.nations["BEL"].recruiting.size() <= int(A.cfg.forces.max_training), "units in training never exceed the cap")

	_war()
	gs.nations["BEL"].treasury = 2.0
	Forces.step(gs, "BEL")
	_check(gs.nations["BEL"].recruiting.is_empty(), "below the treasury floor it raises nothing")

	_war()
	gs.nations["BEL"].manpower = 100
	Forces.step(gs, "BEL")
	_check(gs.nations["BEL"].recruiting.is_empty(), "without recruits it raises nothing")

	_war()
	for i in 20:
		Forces.step(gs, "BEL")
		var spent := 0.0
		for job in gs.nations["BEL"].recruiting:
			spent += Mil.cfg.unit_types[job.type].cost
		var monthly: float = gs.nations["BEL"].budget.revenue / 12.0
		if spent > A.cfg.forces.income_share * monthly * A.cfg.forces.horizon_months + 0.0001:
			_check(false, "units in training cost more than the income share allows")
			break
	_check(true, "units in training stay within the income share")


func _test_where_and_mix() -> void:
	_war()
	gs.nations["BEL"].recruiting.clear()
	gs.nations["BEL"].treasury = 1000.0
	var cfg_cap: int = A.cfg.forces.max_training
	A.cfg.forces.max_training = 40
	A.cfg.forces.income_share = 100.0
	var raised := {}
	for i in 12:
		Forces.step(gs, "BEL")
	for job in gs.nations["BEL"].recruiting:
		raised[job.type] = raised.get(job.type, 0) + 1
		_check(gs.province_owner[job.province] == "BEL" and gs.province_controller[job.province] == "BEL", "units are raised on ground the nation holds")
	var men := {}
	var total := 0.0
	for army in Mil.armies_of(gs, "BEL"):
		for u in army.units:
			men[u.type] = men.get(u.type, 0.0) + u.men()
			total += u.men()
	for job in gs.nations["BEL"].recruiting:
		var size: float = Mil.cfg.unit_types[job.type].size
		men[job.type] = men.get(job.type, 0.0) + size
		total += size
	var art: float = men.get("artillery", 0.0) / total
	_check(men.get("infantry", 0.0) > men.get("artillery", 0.0) and art > 0.1 and art < 0.3, "the force moves toward the mix in ai.json (artillery %.0f%%)" % (art * 100.0))
	# Near the line: within train_hops of the most threatened border province.
	var line: Array = Mil.border_provinces(gs, "BEL", "GER")
	var near := false
	var jobs = gs.nations["BEL"].recruiting
	for p: int in line:
		if A.hops_from(p, int(A.cfg.forces.train_hops)).has(jobs[0].province):
			near = true
	_check(near, "units are raised close behind the line")
	A.cfg.forces.max_training = cfg_cap
	A.load_config()


func _test_rebuild_and_stop() -> void:
	_war()
	var n = gs.nations["BEL"]
	gs.armies.clear()
	Mil.refresh_men(gs)
	Forces.step(gs, "BEL")
	_check(not n.recruiting.is_empty(), "a nation whose army was destroyed raises troops again")

	_war()
	n = gs.nations["BEL"]
	n.peacetime_army = 1000
	Forces.step(gs, "BEL")
	_check(n.recruiting.is_empty(), "a nation at its war strength raises nothing")


func _test_no_spiral() -> void:
	_fresh()
	gs.set_war("GER", "BEL", true)
	gs.set_player("FRA")
	var floor_: float = A.cfg.forces.treasury_floor
	var lowest_after_raise := INF
	var seen := 0
	for d in 150:
		_step(1)
		var now := _raises("GER")
		if now > seen:
			seen = now
			lowest_after_raise = minf(lowest_after_raise, gs.nations["GER"].treasury)
	_check(seen > 0, "Germany at war raised units over five months (%d orders)" % seen)
	_check(lowest_after_raise >= floor_ - 0.0001, "no order took the treasury below the floor (lowest %.2f)" % lowest_after_raise)
