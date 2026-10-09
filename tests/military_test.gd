extends SceneTree
## Headless test for the military: deployment, orders, combat, supply, occupation, recruiting.
## Run: godot --headless --path . -s res://tests/military_test.gd
## Class names are loaded at runtime because this script compiles before the autoloads exist.

var _failures := 0
var gs: Node
var map: Node
var Mil
var UnitC
var MoveC
var RaiseC
var MergeC
var SplitC
var WarC
var FrontC
var DeleteFrontC
var AssignC
var IconC


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", msg)
	else:
		print("ok:   ", msg)


func _initialize() -> void:
	await process_frame
	gs = root.get_node("GameState")
	map = root.get_node("MapData")
	Mil = load("res://scripts/sim/military.gd")
	UnitC = load("res://scripts/sim/unit.gd")
	MoveC = load("res://scripts/sim/move_army.gd")
	RaiseC = load("res://scripts/sim/raise_units.gd")
	MergeC = load("res://scripts/sim/merge_armies.gd")
	SplitC = load("res://scripts/sim/split_army.gd")
	WarC = load("res://scripts/sim/set_war.gd")
	FrontC = load("res://scripts/sim/designate_front.gd")
	DeleteFrontC = load("res://scripts/sim/delete_front.gd")
	AssignC = load("res://scripts/sim/assign_to_front.gd")
	IconC = load("res://scripts/sim/set_army_icon.gd")

	_test_data()
	_test_deployment()
	var pair := _find_border("plains", "plains")
	_check(pair.size() == 2, "found a plains border between France and Germany")
	_test_orders_and_war(pair)
	_test_combat(pair)
	_test_occupation(pair)
	_test_supply()
	_test_recruiting()
	_test_merge_split(pair)
	_test_fronts()
	_test_icons_and_etas(pair)
	_test_border_fronts(pair)
	_test_wars(pair)
	_test_collapse_and_cut_off(pair)
	_test_split_by_type(pair)
	_test_composition(pair)
	_test_battle_details(pair)

	print("FAILURES: ", _failures)
	quit(1 if _failures else 0)


func _fresh() -> void:
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	gs.join_calls.clear()  # the scenario starts a crisis; these tests want a quiet world
	gs.wars.clear()
	gs.armies.clear()
	for tag in gs.nations:
		gs.nations[tag].recruiting.clear()
	Mil.refresh_men(gs)


func _province(name: String, tag: String) -> int:
	for id in range(1, gs.province_owner.size()):
		if map.provinces[id].name == name and gs.province_owner[id] == tag:
			return id
	return 0


func _army(tag: String, province: int, infantry: int, artillery := 0):
	var a = Mil.new_army(gs, tag, "Test army", province)
	for i in infantry:
		a.units.append(UnitC.new("infantry"))
	for i in artillery:
		a.units.append(UnitC.new("artillery"))
	return a


## A French province and a German one that touch, of the given terrains.
func _find_border(french_terrain: String, german_terrain: String) -> Array:
	for a in range(1, gs.province_owner.size()):
		if gs.province_owner[a] != "FRA" or Mil.terrain[a] != french_terrain:
			continue
		for b in Mil.neighbors(a):
			if gs.province_owner[b] == "GER" and Mil.terrain[b] == german_terrain:
				return [a, b]
	return []


func _step(days: int) -> void:
	var clock: Node = root.get_node("Clock")
	for i in days:
		clock.days_elapsed += 1
		Mil.step_day(gs)


func _test_data() -> void:
	var seen := {}
	for id in range(1, map.provinces.size()):
		seen[Mil.terrain[id]] = seen.get(Mil.terrain[id], 0) + 1
	for t in Mil.cfg.terrain:
		_check(seen.get(t, 0) > 0, "terrain %s is used (%d provinces)" % [t, seen.get(t, 0)])
	for t in seen:
		_check(Mil.cfg.terrain.has(t), "terrain %s is defined" % t)
	_check(Mil.terrain[_province("Paris", "FRA")] == "urban", "Paris is urban")
	_check(Mil.terrain[_province("Tirol", "AUH")] == "mountains", "Tyrol is mountains")
	_check(Mil.neighbors(_province("Kent", "GBR")).has(_province("Pas-de-Calais", "FRA")), "the Channel strait is crossable")
	_check(not Mil.neighbors(_province("Pembrokeshire", "GBR")).has(_province("Wexford", "GBR")), "open sea links are not crossable")


func _test_deployment() -> void:
	for tag in gs.nations:
		var n = gs.nations[tag]
		if n.peacetime_army <= 0:
			continue
		var in_armies := 0.0
		for a in Mil.armies_of(gs, tag):
			in_armies += a.men()
			_check(gs.province_owner[a.province] == tag, "%s army %s starts on home soil" % [tag, a.display_name])
		_check(n.total_men() == n.peacetime_army, "%s keeps its peacetime army (%d)" % [tag, n.total_men()])
		_check(in_armies > 0.8 * n.peacetime_army, "%s fields most of it (%d of %d)" % [tag, in_armies, n.peacetime_army])
		_check(n.manpower >= 0, "%s reserve is not negative" % tag)
	var fra_armies: Array = Mil.armies_of(gs, "FRA")
	_check(fra_armies.size() == 10, "France starts with 10 stacks (got %d)" % fra_armies.size())
	_check(fra_armies[0].general_name == "Joseph Joffre", "first French army has its general")


func _test_orders_and_war(pair: Array) -> void:
	_fresh()
	var fra_army = _army("FRA", pair[0], 3)
	_check(Mil.find_path(gs, "FRA", 15.0, pair[0], pair[1]).is_empty(), "no path into neutral Germany")
	_check(not gs.issue(MoveC.new("FRA", fra_army.id, pair[1])), "move into a neutral nation is rejected")
	_check(not gs.issue(MoveC.new("GER", fra_army.id, pair[1])), "cannot order another nation's army")
	_check(gs.issue(WarC.new("FRA", "GER", true)) and gs.at_war("GER", "FRA"), "war can be declared")
	var path: Array = Mil.find_path(gs, "FRA", 15.0, pair[0], pair[1])
	_check(path == [pair[1]], "a neighbour is one step away")
	var own: int = _province("Paris", "FRA")
	var far: Array = Mil.find_path(gs, "FRA", 15.0, pair[0], own)
	_check(far.size() > 1 and Mil.neighbors(pair[0]).has(far[0]), "a longer route starts next door (%d steps)" % far.size())
	var step: int = pair[0]
	var contiguous := true
	for p in far:
		contiguous = contiguous and Mil.neighbors(step).has(p)
		step = p
	_check(contiguous and step == own, "the route is contiguous and ends at the target")
	# Movement takes days and the army arrives.
	var cmd = MoveC.new("FRA", fra_army.id, own)
	_check(gs.issue(cmd), "a legal move is accepted")
	var days := 0
	while fra_army.province != own and days < 80:
		_step(1)
		days += 1
	_check(fra_army.province == own and days > 3, "the army marches there and it takes time (%d days)" % days)
	_check(gs.command_log.back().type == "MoveArmy", "orders are logged")
	_check(Mil.move_days(gs, "FRA", 15.0, pair[0], pair[1]) < Mil.move_days(gs, "FRA", 12.0, pair[0], pair[1]) + 0.001, "slower units take longer")


func _test_combat(pair: Array) -> void:
	_fresh()
	gs.set_war("FRA", "GER", true)
	var attacker = _army("FRA", pair[0], 8, 2)
	var defender = _army("GER", pair[1], 8, 2)
	defender.still_days = 40
	_check(defender.entrenchment() == Mil.cfg.combat.max_entrenchment, "a long-standing army is fully dug in")
	var start_att: float = attacker.men()
	var start_def: float = defender.men()
	_check(gs.issue(MoveC.new("FRA", attacker.id, pair[1])), "attack order accepted")
	var fights := [0]
	gs.battle_fought.connect(func(_p: int, _t: Array) -> void: fights[0] += 1)
	var days := 0
	while attacker.province != pair[1] and days < 40:
		_step(1)
		days += 1
	_check(attacker.province == pair[1] and attacker.attacking, "the attacker marched in and is marked as attacking")
	_step(3)
	var att_loss: float = start_att - attacker.men()
	var def_loss: float = start_def - defender.men()
	_check(fights[0] >= 3 and attacker.fighting and defender.fighting, "a battle is fought every day (%d)" % fights[0])
	_check(att_loss > 0.0 and def_loss > 0.0, "both sides take casualties (%.0f vs %.0f)" % [att_loss, def_loss])
	_check(att_loss > def_loss * 1.4, "an entrenched defender wins the exchange (attacker lost %.0f, defender %.0f)" % [att_loss, def_loss])
	var loss_rate: float = att_loss / start_att / 3.0
	_check(loss_rate > 0.003 and loss_rate < 0.03, "daily losses are plausible (%.2f%% a day)" % (loss_rate * 100.0))
	_step(40)
	_check(not gs.armies.has(attacker.id) or attacker.province != pair[1], "the attacker is eventually thrown back")
	_check(defender.province == pair[1] and gs.armies.has(defender.id), "the defender holds the province")

	# Equal armies fighting on level terms, both in the open, are about even.
	_fresh()
	gs.set_war("FRA", "GER", true)
	var a2 = _army("FRA", pair[1], 6, 2)
	var b2 = _army("GER", pair[1], 6, 2)
	a2.attacking = true
	b2.attacking = true
	_step(4)
	var diff: float = absf(a2.men() - b2.men()) / (a2.men() + b2.men())
	_check(diff < 0.02, "equal armies lose about equally (%.2f%% apart)" % (diff * 100.0))

	# Strength wins: a large army beats a small one on level ground.
	_fresh()
	gs.set_war("FRA", "GER", true)
	var big = _army("FRA", pair[1], 12, 4)
	var small = _army("GER", pair[1], 4, 1)
	big.attacking = true
	_step(25)
	_check(not gs.armies.has(small.id) or small.province != pair[1], "the smaller army is beaten")
	_check(gs.armies.has(big.id) and big.province == pair[1], "the larger army holds the field")


func _test_occupation(pair: Array) -> void:
	_fresh()
	var ger = gs.nations["GER"]
	var fra = gs.nations["FRA"]
	var gdp_before: float = ger.budget.gdp
	var fra_gdp: float = fra.budget.gdp
	_check(gs.issue(WarC.new("FRA", "GER", true)), "declare war")
	var army = _army("FRA", pair[0], 3)
	_check(gs.issue(MoveC.new("FRA", army.id, pair[1])), "march on an undefended province")
	var days := 0
	while gs.province_controller[pair[1]] != "FRA" and days < 60:
		_step(1)
		days += 1
	_check(gs.province_controller[pair[1]] == "FRA", "France takes control after a siege (%d days in all)" % days)
	_check(gs.province_owner[pair[1]] == "GER", "ownership does not change")
	_check(ger.budget.gdp < gdp_before, "Germany loses the province's output")
	_check(fra.budget.gdp > fra_gdp, "France collects a share")
	_check(gs.occupation.is_empty(), "occupation progress is cleared")
	# Liberation: with the French gone, a German army retakes its own province.
	gs.armies.erase(army.id)
	var back = _army("GER", pair[1], 3)
	_check(Mil.can_enter(gs, "GER", pair[1]), "Germany may enter its own occupied province")
	_step(Mil.terrain_of(pair[1]).occupy_days)
	_check(gs.province_controller[pair[1]] == "GER", "a German army in the province takes it back")
	_check(absf(ger.budget.gdp - gdp_before) < 0.01, "Germany's output returns")
	# An army that does not move accumulates days to take territory, and a contested province does not fall.
	_fresh()
	gs.set_war("FRA", "GER", true)
	var holder = _army("GER", pair[1], 2)
	var raider = _army("FRA", pair[1], 2)
	raider.attacking = true
	_step(3)
	_check(gs.occupation.is_empty(), "no occupation while a battle is on")


func _test_supply() -> void:
	_fresh()
	gs.set_war("FRA", "GER", true)
	var berlin := _province("Berlin", "GER")
	_check(Mil.supply_cost(gs, "FRA", berlin) == INF, "Berlin is far beyond French supply")
	var lost = _army("FRA", berlin, 3)
	var home = _army("FRA", _province("Paris", "FRA"), 3)
	_check(Mil.supply_cost(gs, "FRA", home.province) == 0.0, "home provinces are always supplied")
	_step(10)
	_check(not lost.supplied and lost.units[0].strength < 0.97, "an army out of supply wastes away (%.2f)" % lost.units[0].strength)
	_check(home.supplied and home.units[0].strength == 1.0, "a supplied army does not")
	# Railways stretch supply.
	var near := _province("Moselle", "GER")
	var cost: float = Mil.supply_cost(gs, "FRA", near)
	_check(cost > 0.0 and cost < INF, "a province next to the border is within supply (cost %.1f)" % cost)


func _test_recruiting() -> void:
	_fresh()
	var fra = gs.nations["FRA"]
	var paris := _province("Paris", "FRA")
	var def: Dictionary = Mil.cfg.unit_types["infantry"]
	_check(not gs.issue(RaiseC.new("FRA", _province("Moselle", "GER"), "infantry", 1)), "cannot raise units in a foreign province")
	_check(not gs.issue(RaiseC.new("FRA", paris, "bogus", 1)), "unknown unit type rejected")
	fra.manpower = 5000
	_check(not gs.issue(RaiseC.new("FRA", paris, "infantry", 1)), "too few recruits rejected")
	fra.manpower = 100000
	fra.treasury = 0.1
	_check(not gs.issue(RaiseC.new("FRA", paris, "infantry", 1)), "no money rejected")
	fra.treasury = 10.0
	var men_before: int = fra.total_men()
	_check(gs.issue(RaiseC.new("FRA", paris, "infantry", 2)), "raising two divisions works")
	_check(fra.manpower == 100000 - 2 * def.size and absf(fra.treasury - (10.0 - 2 * def.cost)) < 0.001, "recruits and money are paid up front")
	_check(fra.total_men() == men_before, "trainees still count as men in service")
	var before: int = Mil.armies_at(gs, paris).size()
	_step(def.train_days - 1)
	_check(fra.recruiting.size() == 2, "still training the day before")
	var trained := [0]
	gs.unit_trained.connect(func(_t: String, _p: int, _ty: String) -> void: trained[0] += 1)
	_step(1)
	_check(fra.recruiting.is_empty() and trained[0] == 2, "both divisions are ready on the day")
	var units := 0
	for a in Mil.armies_at(gs, paris):
		if a.tag == "FRA":
			units += a.units.size()
	_check(units >= 2 and Mil.armies_at(gs, paris).size() >= before, "the new divisions stand in Paris")

	# Reinforcement pulls wounded units back up from the reserve.
	var a = _army("FRA", paris, 1)
	a.units[0].strength = 0.5
	fra.manpower = 50000
	_step(20)
	_check(a.units[0].strength > 0.6 and fra.manpower < 50000, "units refill from the reserve (%.2f)" % a.units[0].strength)


func _test_merge_split(pair: Array) -> void:
	_fresh()
	var a = _army("FRA", pair[0], 3, 1)
	var b = _army("FRA", pair[0], 2)
	var far = _army("FRA", _province("Paris", "FRA"), 1)
	var ids: Array[int] = [a.id, far.id]
	_check(not gs.issue(MergeC.new("FRA", ids)), "armies in different provinces cannot merge")
	var ids2: Array[int] = [a.id, b.id]
	_check(gs.issue(MergeC.new("FRA", ids2)) and a.units.size() == 6 and not gs.armies.has(b.id), "merging pools the units")
	var idx: Array[int] = [0, 1]
	var split = SplitC.new("FRA", a.id, idx)
	_check(gs.issue(split) and a.units.size() == 4 and gs.armies[split.new_army_id].units.size() == 2, "splitting detaches units")
	var all: Array[int] = [0, 1, 2, 3]
	_check(not gs.issue(SplitC.new("FRA", a.id, all)), "cannot split off everything")
	var bad: Array[int] = [9]
	_check(not gs.issue(SplitC.new("FRA", a.id, bad)), "bad unit index rejected")


func _test_fronts() -> void:
	_fresh()
	# A line of three connected French provinces.
	var a := _province("Meurthe-et-Moselle", "FRA")
	var line: Array[int] = [a]
	while line.size() < 3:
		for n in Mil.neighbors(line.back()):
			if gs.province_owner[n] == "FRA" and not line.has(n):
				line.append(n)
				break
	var broken: Array[int] = [line[0], _province("Bretagne", "FRA") if _province("Bretagne", "FRA") > 0 else _province("Finistère", "FRA")]
	_check(not gs.issue(FrontC.new("FRA", "Bad", broken)), "a front must be a chain of bordering provinces")
	var empty: Array[int] = []
	_check(not gs.issue(FrontC.new("FRA", "Empty", empty)), "an empty front is rejected")
	var cmd = FrontC.new("FRA", "Lorraine Front", line)
	_check(gs.issue(cmd) and gs.fronts.has(cmd.front_id), "a front can be drawn")
	_check(gs.fronts[cmd.front_id].display_name == "Lorraine Front", "it keeps its name")
	var unnamed = FrontC.new("FRA", "", line)
	gs.issue(unnamed)
	_check(gs.fronts[unnamed.front_id].display_name.begins_with("Front "), "unnamed fronts get a default name")
	gs.issue(DeleteFrontC.new("FRA", unnamed.front_id))
	_check(not gs.fronts.has(unnamed.front_id), "a front can be deleted")

	# Armies spread along the line and walk to their provinces.
	var far := _province("Paris", "FRA")
	var big = _army("FRA", far, 6)
	var mid = _army("FRA", far, 4)
	var small = _army("FRA", far, 2)
	var ids: Array[int] = [big.id, mid.id, small.id]
	_check(not gs.issue(AssignC.new("GER", cmd.front_id, ids)), "another nation cannot assign your armies")
	_check(gs.issue(AssignC.new("FRA", cmd.front_id, ids)), "armies can be assigned to a front")
	_check(big.front_id == cmd.front_id and gs.fronts[cmd.front_id].army_ids.size() == 3, "the assignment is recorded")
	_step(1)
	var f = gs.fronts[cmd.front_id]
	var slots := {}
	for id in ids:
		slots[f.slots[id]] = true
	_check(slots.size() == 3, "three armies take three different provinces of the line")
	_check(not big.path.is_empty() and not mid.path.is_empty(), "idle armies are sent to their provinces")
	var days := 0
	while days < 120 and (big.province != f.slots[big.id] or mid.province != f.slots[mid.id] or small.province != f.slots[small.id]):
		_step(1)
		days += 1
	_check(big.province == f.slots[big.id] and mid.province == f.slots[mid.id] and small.province == f.slots[small.id], "every army reaches its place on the line (%d days)" % days)
	_step(10)
	_check(big.path.is_empty() and big.entrenchment() >= 2, "armies on the line stay put and dig in")

	# A hand-given order releases an army from the front.
	var other: int = line[0] if big.province != line[0] else line[1]
	_check(gs.issue(MoveC.new("FRA", big.id, other)), "a manual order is accepted")
	_check(big.front_id == 0 and not f.army_ids.has(big.id), "which takes the army off its front")
	var rel: Array[int] = [mid.id]
	gs.issue(AssignC.new("FRA", 0, rel))
	_check(mid.front_id == 0 and not f.army_ids.has(mid.id), "armies can be released")
	gs.armies.erase(small.id)
	_step(1)
	_check(f.army_ids.is_empty(), "destroyed armies leave the front")
	var all: Array[int] = [mid.id]
	gs.issue(AssignC.new("FRA", cmd.front_id, all))
	gs.issue(DeleteFrontC.new("FRA", cmd.front_id))
	_check(mid.front_id == 0, "deleting a front frees its armies")


func _test_icons_and_etas(pair: Array) -> void:
	_fresh()
	var a = _army("FRA", pair[0], 3)
	_check(a.shown_icon() == "infantry", "an infantry army shows the infantry symbol")
	var guns = _army("FRA", pair[0], 1, 3)
	_check(guns.shown_icon() == "artillery", "a gun-heavy army shows the artillery symbol")
	var cav = Mil.new_army(gs, "FRA", "Horse", pair[0])
	cav.units.append(UnitC.new("cavalry"))
	_check(cav.shown_icon() == "cavalry", "cavalry army shows the cavalry symbol")
	var ids: Array[int] = [a.id, guns.id]
	_check(gs.issue(IconC.new("FRA", ids, "guard")) and a.shown_icon() == "guard" and guns.icon == "guard", "the symbol can be chosen")
	_check(not gs.issue(IconC.new("FRA", ids, "bogus")), "an unknown symbol is rejected")
	_check(not gs.issue(IconC.new("GER", ids, "reserve")), "another nation cannot change your symbols")
	gs.issue(IconC.new("FRA", ids, "auto"))
	_check(a.shown_icon() == "infantry", "auto returns to the automatic choice")

	# Path times: one entry per province, rising, and the last equals the sum of the legs.
	gs.set_war("FRA", "GER", true)
	var own: int = _province("Paris", "FRA")
	var route: Array[int] = Mil.find_path(gs, "FRA", 15.0, pair[0], own)
	var a2 = _army("FRA", pair[0], 2)
	_check(gs.issue(MoveC.new("FRA", a2.id, own)), "order a march")
	var etas: Array[float] = Mil.army_etas(gs, a2)
	_check(etas.size() == route.size(), "one time per province on the route (%d)" % etas.size())
	var rising := true
	for i in range(1, etas.size()):
		rising = rising and etas[i] > etas[i - 1]
	_check(rising and etas[0] >= 1.0, "times rise along the route (%s)" % str(etas))
	var walked := 0
	while a2.province != own and walked < 200:
		_step(1)
		walked += 1
	_check(absf(walked - etas.back()) <= 1.0, "the army arrives when the last time says (%d days, predicted %d)" % [walked, roundi(etas.back())])
	var clock: Node = root.get_node("Clock")
	var today: String = clock.date_after(0)
	_check(today == clock.date_string(), "date_after(0) is today")
	_check(clock.date_after(5) != today and clock.date_after(400).ends_with("1915") or clock.date_after(400).ends_with("1916"), "date_after rolls over months and years")


func _test_border_fronts(pair: Array) -> void:
	_fresh()
	var line: Array[int] = Mil.border_provinces(gs, "FRA", "GER")
	_check(line.size() >= 3, "France has several provinces bordering Germany (%d)" % line.size())
	var ok := true
	for id in line:
		var touches := false
		for n in Mil.neighbors(id):
			touches = touches or gs.province_controller[n] == "GER"
		ok = ok and gs.province_controller[id] == "FRA" and touches
	_check(ok, "each one is French-held and touches German ground")
	_check(not line.has(_province("Paris", "FRA")), "interior provinces are not on the border")
	_check(Mil.border_provinces(gs, "FRA", "POR").is_empty(), "France has no border with Portugal")
	var none: Array[int] = []
	_check(not gs.issue(FrontC.new("FRA", "", none, "POR")), "a front against a nation with no border is rejected")
	_check(not gs.issue(FrontC.new("FRA", "", none, "FRA")), "a nation cannot face itself")
	_check(not gs.issue(FrontC.new("FRA", "", none, "XXX")), "an unknown nation is rejected")
	var cmd = FrontC.new("FRA", "", none, "GER")
	_check(gs.issue(cmd), "a front can be drawn by naming the nation")
	var f = gs.fronts[cmd.front_id]
	_check(f.display_name == "Front vs German Empire" and f.against == "GER", "it is named after the nation")
	_check(f.provinces == line, "its line is the whole border")

	# Armies assigned to it spread over the border provinces.
	var home := _province("Paris", "FRA")
	var ids: Array[int] = []
	for i in 4:
		ids.append(_army("FRA", home, 3).id)
	gs.issue(AssignC.new("FRA", f.id, ids))
	_step(1)
	var used := {}
	for id in ids:
		used[f.slots[id]] = true
		_check(line.has(f.slots[id]), "army %d is posted on a border province" % id)
	_check(used.size() == mini(4, line.size()), "armies spread over as many border provinces as there are (%d of %d)" % [used.size(), line.size()])

	# The line follows the war: take a German province and the border moves.
	gs.set_war("FRA", "GER", true)
	var target: int = pair[1]
	_check(not line.has(target), "the German province is not on the French line yet")
	gs.set_controller(target, "FRA")
	_step(1)
	_check(f.provinces.has(target) and f.provinces != line, "after taking it, the line includes it")
	var ok2 := true
	for id in f.provinces:
		var touches := false
		for n in Mil.neighbors(id):
			touches = touches or gs.province_controller[n] == "GER"
		ok2 = ok2 and touches
	_check(ok2, "and every province on the new line still touches Germany")
	# Losing all contact empties the line without breaking anything.
	for id in range(1, gs.province_controller.size()):
		if gs.province_owner[id] == "GER":
			gs.set_controller(id, "FRA")
	_step(2)
	_check(f.provinces.is_empty(), "with no German-held ground left the line is empty")


func _test_wars(pair: Array) -> void:
	_fresh()
	var clock: Node = root.get_node("Clock")
	_check(gs.wars.is_empty() and gs.war_history.is_empty(), "no wars at the start")
	gs.set_war("FRA", "GER", true)
	var war = gs.war_between("GER", "FRA")
	_check(war != null and war.a == "FRA" and war.b == "GER" and war.active(), "the war records who started it")
	_check(war.start_date == clock.date_string() and war.log.size() == 1, "and when, with a first log entry")
	_check(gs.wars_of("FRA").size() == 1 and gs.wars_of("ITA").is_empty(), "wars are listed per nation")

	var attacker = _army("FRA", pair[0], 8, 2)
	var defender = _army("GER", pair[1], 8, 2)
	defender.still_days = 40
	var a0: float = attacker.men()
	var d0: float = defender.men()
	gs.issue(MoveC.new("FRA", attacker.id, pair[1]))
	var days := 0
	while days < 150 and war.battles.is_empty():
		_step(1)
		days += 1
	_check(war.battles.size() == 1, "a battle is written into the war when it ends (%d days in)" % days)
	var rec: Dictionary = war.battles[0]
	_check(rec.winner == "GER" and rec.attacker == "FRA" and rec.province == pair[1], "it names the attacker, the winner and the place")
	_check(rec.days >= 2, "and how long it lasted (%d days)" % rec.days)
	_check(absf(rec.strength["FRA"] - a0) < a0 * 0.01 and absf(rec.strength["GER"] - d0) < d0 * 0.01, "starting strengths are recorded")
	_check(rec.lost["FRA"] > rec.lost["GER"] and rec.lost["GER"] > 0.0, "so are losses (%dk vs %dk)" % [rec.lost["FRA"] / 1000.0, rec.lost["GER"] / 1000.0])
	_check(war.losses["FRA"] >= rec.lost["FRA"] - 1.0 and war.losses["FRA"] <= rec.lost["FRA"] + a0 * 0.15, "the war's loss tally includes them (and the rout)")
	_check(war.battle_count("GER", "won") == 1 and war.battle_count("FRA", "lost") == 1 and war.battle_count("FRA", "won") == 0, "wins and defeats are counted")
	_check(gs.engagements.is_empty(), "no battle is left open")
	var last: Dictionary = war.log.back()
	_check(last.kind == "battle" and last.text.begins_with("Battle of") and last.province == pair[1], "the log has a battle line pointing at the province")
	var held_men: float = attacker.men() + defender.men()
	_check(held_men < a0 + d0, "the armies are smaller afterwards")

	# Taking ground is recorded as gains.
	_fresh()
	gs.set_war("FRA", "GER", true)
	war = gs.war_between("FRA", "GER")
	var raider = _army("FRA", pair[0], 3)
	gs.issue(MoveC.new("FRA", raider.id, pair[1]))
	days = 0
	while gs.province_controller[pair[1]] != "FRA" and days < 100:
		_step(1)
		days += 1
	_check(war.captured["FRA"].provinces == 1 and war.captured["FRA"].population == gs.province_population[pair[1]], "occupying a province is recorded with its people")
	_check(war.captured["GER"].provinces == 0, "the other side has taken nothing")
	var cap: Dictionary = war.log.back()
	_check(cap.kind == "capture" and cap.province == pair[1], "the log notes the capture")

	# Attrition is charged to the war.
	var berlin := _province("Berlin", "GER")
	var lost = _army("FRA", berlin, 3)
	var before: float = lost.men()
	_step(10)
	_check(war.attrition["FRA"] > 0.0 and absf(war.attrition["FRA"] - (before - lost.men())) < 1.0, "attrition away from supply is counted (%dk)" % (war.attrition["FRA"] / 1000.0))

	# Peace closes the war and files it.
	gs.set_war("GER", "FRA", false)
	_check(not gs.at_war("FRA", "GER") and gs.war_history.size() == 1 and not war.active(), "peace ends the war and moves it to the history")
	_check(war.end_date == clock.date_string() and war.log.back().kind == "peace", "with an end date and a closing entry")
	gs.set_war("GER", "ITA", true)
	var order: Array = gs.all_wars()
	_check(order.size() == 2 and order[0].active() and not order[1].active(), "active wars are listed before past ones")
	_check(order[0].a == "GER", "and the aggressor is whoever declared")


func _test_collapse_and_cut_off(pair: Array) -> void:
	# A nation with no land left loses its army.
	_fresh()
	gs.set_war("FRA", "GER", true)
	var war = gs.war_between("FRA", "GER")
	var germans = _army("GER", _province("Berlin", "GER"), 5, 1)
	var men: float = germans.men()
	var collapsed := []
	gs.nation_collapsed.connect(func(tag: String, m: int) -> void: collapsed.append([tag, m]))
	for id in range(1, gs.province_owner.size()):
		if gs.province_owner[id] == "GER":
			gs.set_controller(id, "FRA")
	_step(1)
	_check(Mil.armies_of(gs, "GER").is_empty(), "a fully occupied nation's armies disband")
	_check(collapsed.size() == 1 and collapsed[0][0] == "GER" and absf(collapsed[0][1] - men) < men * 0.02, "the collapse is announced with the men lost")
	_check(war.surrendered["GER"] >= men * 0.98 and war.log.back().kind == "collapse", "and written into the war")
	var again = _army("GER", _province("Berlin", "GER"), 2)
	_step(1)
	_check(not gs.armies.has(again.id), "new armies of a landless nation vanish too")
	gs.issue(RaiseC.new("GER", _province("Berlin", "GER"), "infantry", 1))
	_check(gs.nations["GER"].recruiting.is_empty(), "and nothing can be raised")
	_step(1)

	# A routed army with no friendly province to fall back on is lost, not teleported onto
	# land the enemy holds.
	_fresh()
	gs.set_war("FRA", "GER", true)
	war = gs.war_between("FRA", "GER")
	var stand: int = pair[1]
	var berlin := _province("Berlin", "GER")
	for id in range(1, gs.province_owner.size()):
		if gs.province_owner[id] == "GER" and id != stand and id != berlin:
			gs.set_controller(id, "FRA")
	var weak = _army("GER", stand, 2)
	var strong = _army("FRA", stand, 12, 4)
	strong.attacking = true
	_step(30)
	_check(not gs.armies.has(weak.id), "the beaten army is gone")
	_check(Mil.armies_of(gs, "GER").is_empty(), "it did not slip into a neighbouring province")
	_check(war.surrendered["GER"] > 0.0, "the men are counted as cut off (%dk)" % (war.surrendered["GER"] / 1000.0))
	_check(war.battles.size() == 1 and war.battles[0].winner == "FRA", "the battle went to France")
	_check(gs.province_controller[stand] != "GER", "and the province is not retaken for free")


func _test_split_by_type(pair: Array) -> void:
	_fresh()
	var a = _army("FRA", pair[0], 5, 3)
	var cav = UnitC.new("cavalry")
	a.units.append(cav)
	var idx: Array[int] = SplitC.indices_of_type(a, "artillery", 2)
	_check(idx.size() == 2 and a.units[idx[0]].type == "artillery" and a.units[idx[1]].type == "artillery", "indices_of_type finds the requested units")
	_check(SplitC.indices_of_type(a, "artillery", 99).size() == 3, "and never more than exist")
	_check(SplitC.indices_of_type(a, "infantry", 0).is_empty(), "a count of zero finds none")
	var cmd = SplitC.new("FRA", a.id, idx)
	_check(gs.issue(cmd), "splitting off two artillery brigades works")
	var gun_army = gs.armies[cmd.new_army_id]
	_check(gun_army.units.size() == 2 and gun_army.count_of("artillery") == 2 and a.count_of("artillery") == 1, "they form their own army")
	_check(gun_army.province == a.province and a.units.size() == 7, "in the same province, the rest stays")
	var cav_idx: Array[int] = SplitC.indices_of_type(a, "cavalry", 1)
	var cmd2 = SplitC.new("FRA", a.id, cav_idx)
	_check(gs.issue(cmd2) and gs.armies[cmd2.new_army_id].shown_icon() == "cavalry", "the cavalry can be detached on its own")
	var all_inf: Array[int] = SplitC.indices_of_type(a, "infantry", 99)
	var left: int = a.units.size() - all_inf.size()
	_check(left == 1, "one gun brigade is left with the infantry")
	_check(gs.issue(SplitC.new("FRA", a.id, all_inf)) and a.units.size() == 1 and a.units[0].type == "artillery", "all the infantry can be taken off, leaving the guns")
	var everything: Array[int] = SplitC.indices_of_type(a, "artillery", 99)
	_check(not gs.issue(SplitC.new("FRA", a.id, everything)), "detaching every unit is still refused")


func _test_composition(pair: Array) -> void:
	_fresh()
	var a = _army("FRA", pair[0], 5, 3)
	var comp: Dictionary = a.composition()
	_check(comp == {"infantry": 5, "artillery": 3}, "composition counts the units by type (%s)" % str(comp))
	_check(comp.keys() == ["infantry", "artillery"], "types are in the order of the data file, empty ones left out")
	a.units.append(UnitC.new("cavalry"))
	_check(a.composition() == {"infantry": 5, "cavalry": 1, "artillery": 3}, "cavalry shows up once present")
	_check(Mil.new_army(gs, "FRA", "Empty", pair[0]).composition().is_empty(), "an empty army has no composition")



func _test_battle_details(pair: Array) -> void:
	_fresh()
	gs.set_war("FRA", "GER", true)
	var war = gs.war_between("FRA", "GER")
	var attacker = _army("FRA", pair[0], 8, 2)
	attacker.general_name = "Test General"
	var defender = _army("GER", pair[1], 8, 2)
	defender.still_days = 40
	gs.issue(MoveC.new("FRA", attacker.id, pair[1]))
	var days := 0
	while gs.battle_at(pair[1]).is_empty() and days < 100:
		_step(1)
		days += 1
	var live: Dictionary = gs.battle_at(pair[1])
	_check(not live.is_empty() and live.active and live.id > 0, "a battle in progress can be looked up by province")
	_check(gs.battle_by_id(live.id) == live, "and by id")
	_check(live.timeline.size() == 1 and live.timeline[0].day == 1, "the first day is on the timeline")
	_check(live.events.size() >= 1 and live.events[0].begins_with("Day 1: France attacks German Empire at"), "the first event says who attacked (%s)" % live.events[0])
	_check(live.terrain == Mil.terrain[pair[1]] and live.attacker == "FRA", "terrain and attacker are recorded")
	_check(live.sides["FRA"].comp_start == {"infantry": 8, "artillery": 2} and live.sides["GER"].comp_start == {"infantry": 8, "artillery": 2}, "each side's starting composition is recorded")
	_check(live.sides["FRA"].generals == ["Test General"], "generals are recorded")
	_check(live.sides["FRA"].armies.has(attacker.id), "so are the armies")
	var id: int = live.id
	var men0: float = live.sides["FRA"].men_now
	_step(2)
	_check(live.timeline.size() == 3 and live.sides["FRA"].men_now < men0, "the timeline grows each day and strength falls")
	_check(live.timeline[2].men["FRA"] < live.timeline[0].men["FRA"] and live.timeline[2].lost["FRA"] > 0.0, "with each day's men and losses")
	_check(live.timeline[2].morale["FRA"] < live.timeline[0].morale["FRA"], "and morale")
	_check(live.sides["GER"].defense > 1.0 and live.sides["FRA"].defense == 1.0, "the defender's advantage is recorded")
	_check(gs.battle_archive.is_empty(), "nothing is archived until the battle ends")
	days = 0
	while not gs.engagements.is_empty() and days < 100:
		_step(1)
		days += 1
	var full: Dictionary = gs.battle_by_id(id)
	_check(not full.is_empty() and not full.active and gs.battle_archive.has(id), "a finished battle is archived")
	_check(full.winner == "GER" and full.days == full.timeline.size() and full.end_date != "", "with its winner, length and end date")
	var routed := false
	var held := false
	for line: String in full.events:
		routed = routed or line.contains("routed")
		held = held or line.contains("holds the field")
	_check(routed and held, "events note the rout and who held the field")
	_check(full.sides["FRA"].men_end == 0.0 and full.sides["GER"].men_end > 0.0, "who is left on the field is recorded")
	_check(full.sides["GER"].comp_end.has("infantry") and full.sides["FRA"].comp_end.is_empty(), "and what is left of them")
	_check(war.battles[0].id == id and war.log.back().battle == id, "the war record points at the full account")
	_check(gs.battle_by_id(99999).is_empty(), "an unknown battle is an empty record")
