extends SceneTree
## Headless test of the rules behind the Battle Plan toolbar: a border front that holds only the stretch around a
## clicked province, reshaping a hand-drawn line and a plan's target line, an invasion that gathers in a port and sails,
## and warships on Shore support adding to an attack on the coast.
## Run: godot --headless --path . -s res://tests/battle_plan_rules_test.gd

var _failures := 0
var gs: Node
var clock: Node
var Mil
var FS
var Off


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
	Mil = load("res://scripts/sim/military.gd")
	FS = load("res://scripts/sim/front_solver.gd")
	Off = load("res://scripts/sim/offensives.gd")
	_test_stretch()
	_test_reshape()
	_test_invasion()
	_test_shore_support()
	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)


func _setup() -> void:
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	gs.set_player("GER")
	gs.ai_enabled = false
	for w in gs.wars.values().duplicate():
		gs.set_war(w.a, w.b, false)
	gs.pending_joins.clear()
	gs.set_war("GER", "RUS", true)
	gs.pending_joins.clear()


func _named(city: String) -> int:
	for c in gs.cities:
		if c.name == city:
			return c.province
	return 0


func _test_stretch() -> void:
	_setup()
	var whole: Array[int] = FS.order_line(Mil.border_provinces(gs, "GER", "RUS"))
	# Two runs of the border with a gap between them: the anchor picks the run it lies in, or the nearest.
	var north: Array[int] = whole.slice(0, 4)
	var south: Array[int] = whole.slice(whole.size() - 4)
	var cut: Array[int] = north + south
	_check(Mil.border_stretch(cut, south[1]) == south, "the stretch of a broken line is the run the clicked province is in")
	_check(Mil.border_stretch(cut, north[0]) == north, "and the other run for a province of it")
	_check(Mil.border_stretch(cut, 0) == cut, "with no anchor it is the whole line")
	var make = load("res://scripts/sim/designate_front.gd").new("GER", "", [] as Array[int], "RUS", "line", whole[2])
	_check(gs.issue(make) and gs.fronts[make.front_id].anchor == whole[2] and gs.fronts[make.front_id].provinces.size() == Mil.border_stretch(Mil.border_provinces(gs, "GER", "RUS"), whole[2]).size(), "a border front clicked at a province holds the stretch around it")


func _test_reshape() -> void:
	_setup()
	var berlin := _named("Berlin")
	var line: Array[int] = [berlin]
	for n: int in Mil.neighbors(berlin):
		if gs.province_controller[n] == "GER":
			line.append(n)
			break
	var make = load("res://scripts/sim/designate_front.gd").new("GER", "Reserve", line)
	gs.issue(make)
	var longer: Array[int] = line.duplicate()
	for n: int in Mil.neighbors(line[-1]):
		if gs.province_controller[n] == "GER" and not longer.has(n):
			longer.append(n)
			break
	var SFL = load("res://scripts/sim/set_front_line.gd")
	_check(gs.issue(SFL.new("GER", make.front_id, longer)) and gs.fronts[make.front_id].provinces == longer, "a drawn line can be reshaped (%d provinces)" % longer.size())
	var broken: Array[int] = [berlin, _named("Breslau")]
	_check(not gs.issue(SFL.new("GER", make.front_id, broken)), "but not into provinces that do not join")
	var border = load("res://scripts/sim/designate_front.gd").new("GER", "", [] as Array[int], "RUS")
	gs.issue(border)
	_check(SFL.problem(gs, "GER", border.front_id, longer).contains("follows the border"), "a border front cannot be reshaped")
	# A plan's target line.
	var army = Mil.new_army(gs, "GER", "Test Army", berlin)
	army.units.append(load("res://scripts/sim/unit.gd").new("infantry"))
	var ring: Array[int] = []
	for p in Mil.border_provinces(gs, "RUS", "GER"):
		ring.append(p)
	var plan = load("res://scripts/sim/plan_offensive.gd").new("GER", army.id, "broad", ring.slice(0, 3), "balanced")
	gs.issue(plan)
	var SO = load("res://scripts/sim/set_offensive.gd")
	_check(gs.issue(SO.new("GER", plan.offensive_id, "targets", ring.slice(0, 5))) and gs.offensives[plan.offensive_id].targets().size() == 5, "a push's target line can be redrawn")
	var spear = load("res://scripts/sim/plan_offensive.gd").new("GER", army.id, "spearhead", ring.slice(0, 1), "balanced")
	gs.issue(spear)
	_check(not gs.issue(SO.new("GER", spear.offensive_id, "targets", ring.slice(0, 2))) and gs.issue(SO.new("GER", spear.offensive_id, "targets", ring.slice(3, 4))), "a spearhead's target moves to one other province, never two")


func _test_invasion() -> void:
	_setup()
	# The German port nearest Danzig that ships can lie in.
	var danzig := 0
	for id in range(1, gs.province_controller.size()):
		if gs.province_controller[id] == "GER" and load("res://scripts/sim/navy.gd").can_dock(gs, "GER", id):
			if danzig == 0 or (root.get_node("MapData").provinces[id].center as Vector2).distance_to(root.get_node("MapData").provinces[_named("Danzig")].center) < (root.get_node("MapData").provinces[danzig].center as Vector2).distance_to(root.get_node("MapData").provinces[_named("Danzig")].center):
				danzig = id
	# The nearest Russian coast to Danzig.
	var target := 0
	for id in range(1, gs.province_controller.size()):
		if gs.province_controller[id] == "RUS" and not root.get_node("MapData").zones_of_port(id).is_empty():
			if target == 0 or (root.get_node("MapData").provinces[id].center as Vector2).distance_to(root.get_node("MapData").provinces[danzig].center) < (root.get_node("MapData").provinces[target].center as Vector2).distance_to(root.get_node("MapData").provinces[danzig].center):
				target = id
	var start := 0
	for n: int in Mil.neighbors(danzig):
		if gs.province_controller[n] == "GER":
			start = n
			break
	var army = Mil.new_army(gs, "GER", "Landing Corps", start)
	for i in 3:
		army.units.append(load("res://scripts/sim/unit.gd").new("infantry"))
	var PO = load("res://scripts/sim/plan_offensive.gd")
	_check(PO.problem(gs, "GER", army.id, "invasion", [target] as Array[int], "balanced", start if root.get_node("MapData").zones_of_port(start).is_empty() else 0) != "", "an invasion needs a port of one's own to sail from")
	var plan = PO.new("GER", army.id, "invasion", [target] as Array[int], "balanced", danzig)
	_check(gs.issue(plan), "an invasion of %s from the Baltic coast is planned" % root.get_node("MapData").provinces[target].name)
	gs.issue(load("res://scripts/sim/set_offensive.gd").new("GER", plan.offensive_id, "launch", true))
	var o = gs.offensives[plan.offensive_id]
	for d in 20:
		clock.advance_day()
	_check(army.province == danzig and not o.done and Off.invasion_wait(gs, o).contains("transports"), "the army gathers in the port and waits for transports (%s)" % Off.invasion_wait(gs, o))
	var fleet = load("res://scripts/sim/navy.gd").new_fleet(gs, "GER", "Transport Flotilla", danzig)
	for i in 3:
		fleet.ships.append(load("res://scripts/sim/ship.gd").new("transport"))
	clock.advance_day()
	_check(o.done and army.fleet_id == fleet.id, "with transports in port it sails")
	var landed := false
	for d in 40:
		clock.advance_day()
		if gs.armies.has(army.id) and not army.embarked() and army.province != danzig:
			landed = true
			break
	_check(landed, "and lands on the coast it aimed at")


func _test_shore_support() -> void:
	_setup()
	var coast := 0
	for id in range(1, gs.province_controller.size()):
		if gs.province_controller[id] == "RUS" and not root.get_node("MapData").zones_of_port(id).is_empty():
			coast = id
			break
	_check(Mil.naval_support(gs, "GER", coast) == 0.0, "with no warships off the coast there is no shore support")
	var zone: int = root.get_node("MapData").zones_of_port(coast)[0]
	var fleet = load("res://scripts/sim/navy.gd").new_fleet(gs, "GER", "Bombardment Squadron", 0)
	fleet.zone = zone
	for i in 3:
		fleet.ships.append(load("res://scripts/sim/ship.gd").new("dreadnought"))
	fleet.ships.append(load("res://scripts/sim/ship.gd").new("transport"))
	_check(Mil.naval_support(gs, "GER", coast) == 0.0, "warships stationed there give none until ordered to Shore support")
	gs.issue(load("res://scripts/sim/set_fleet_mission.gd").new("GER", fleet.id, "support"))
	_check(is_equal_approx(Mil.naval_support(gs, "GER", coast), 0.15), "three warship squadrons on Shore support add 15%% to an attack there (%.2f)" % Mil.naval_support(gs, "GER", coast))
