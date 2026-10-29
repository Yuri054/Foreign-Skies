extends SceneTree
## Headless test of the front solver (docs/FRONTLINES.md, stage F1): the line in order, divisions dealt by weight, an
## army spreading along its front as detachments, regrouping when released, and a hand order pinning a stack.
## Run: godot --headless --path . -s res://tests/front_solver_test.gd

var _failures := 0
var gs: Node
var clock: Node
var FS
var Mil


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", msg)
	else:
		print("ok:   ", msg)


func _days(n: int) -> void:
	for i in n:
		clock.advance_day()


func _initialize() -> void:
	await process_frame
	gs = root.get_node("GameState")
	clock = root.get_node("Clock")
	FS = load("res://scripts/sim/front_solver.gd")
	Mil = load("res://scripts/sim/military.gd")
	_test_line()
	_test_spread()
	_test_broad()
	_test_cohesion()
	_test_fallback_and_garrison()
	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)


func _test_line() -> void:
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	var border: Array[int] = Mil.border_provinces(gs, "GER", "FRA")
	var line: Array[int] = FS.order_line(border)
	var sorted_border := border.duplicate()
	sorted_border.sort()
	var sorted_line := line.duplicate()
	sorted_line.sort()
	_check(sorted_line == sorted_border, "the ordered line has every province of the border once (%d)" % line.size())
	var linked := 0
	for i in range(1, line.size()):
		if Mil.neighbors(line[i - 1]).has(line[i]):
			linked += 1
	_check(linked >= line.size() - 2, "and walks it neighbour to neighbour (%d of %d steps)" % [linked, line.size() - 1])
	var w: Array[float] = [1.0, 2.0, 1.0]
	var dealt: Array[int] = FS.deal(7, w)
	_check(dealt[0] + dealt[1] + dealt[2] == 7 and dealt[1] >= dealt[0], "divisions are dealt by weight and add up (%s)" % str(dealt))
	_check(FS.deal(2, [1.0, 1.0, 1.0, 1.0] as Array[float]).reduce(func(a: int, b: int) -> int: return a + b, 0) == 2, "fewer divisions than provinces still add up")


func _test_spread() -> void:
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	gs.set_player("GER")
	gs.ai_enabled = false
	for w in gs.wars.values().duplicate():
		gs.set_war(w.a, w.b, false)
	gs.pending_joins.clear()
	var border: Array[int] = Mil.border_provinces(gs, "GER", "RUS")
	# One army of 20 divisions standing behind the middle of the border, nothing else German near it.
	var army = Mil.new_army(gs, "GER", "Test Army", border[border.size() / 2])
	var UnitC = load("res://scripts/sim/unit.gd")
	for i in 20:
		army.units.append(UnitC.new("infantry"))
	var Designate = load("res://scripts/sim/designate_front.gd")
	var make = Designate.new("GER", "East", [] as Array[int], "RUS")
	_check(gs.issue(make), "a front facing Russia is drawn")
	var front = gs.fronts[make.front_id]
	_check(front.spread, "the player's front spreads its armies' divisions")
	gs.issue(load("res://scripts/sim/assign_to_front.gd").new("GER", front.id, [army.id] as Array[int]))
	_days(40)
	var stacks: Array = FS.stacks_of(gs, army)
	var units := 0
	var on_line := 0
	var held := {}
	for s in stacks:
		units += s.units.size()
		if front.provinces.has(s.province) and s.path.is_empty():
			on_line += 1
			held[s.province] = true
	var want: int = mini(20, front.provinces.size())
	_check(units == 20, "no division is lost or doubled (%d)" % units)
	_check(stacks.size() > 1 and held.size() >= want - 1, "the army spreads as detachments over the line (%d provinces of %d)" % [held.size(), front.provinces.size()])
	_check(stacks.all(func(s) -> bool: return s == army or s.parent_id == army.id), "every stack is the army or one of its detachments")
	_check(stacks.all(func(s) -> bool: return s.general_skill == army.general_skill and s.group_id == army.group_id), "detachments keep the army's general and group")
	# A hand order pins a detachment: it stays on the front and is left alone until it stops.
	var det = null
	for s in stacks:
		if s != army:
			det = s
			break
	var rear: int = 0
	for n: int in Mil.neighbors(det.province):
		if gs.province_controller[n] == "GER" and not front.provinces.has(n):
			rear = n
			break
	if rear > 0:
		_check(gs.issue(load("res://scripts/sim/move_army.gd").new("GER", det.id, rear)), "a detachment is sent behind the line by hand")
		_check(det.pin == rear and army.front_id == front.id, "it is pinned there and its army stays on the front")
		var stuck := true
		for i in 30:
			_days(1)
			if not gs.armies.has(det.id):
				break
			if det.province != rear and det.path.is_empty() and det.pin != 0:
				stuck = false
		_check(stuck, "the front does not move it while it is pinned")
	# Released, the detachments march back and merge into the army.
	gs.issue(load("res://scripts/sim/assign_to_front.gd").new("GER", 0, [army.id] as Array[int]))
	_days(40)
	var left: Array = FS.stacks_of(gs, army)
	_check(left.size() == 1 and army.units.size() == 20, "released from the front, the army gathers into one stack again (%d stacks, %d divisions)" % [left.size(), army.units.size()])
	# The army itself destroyed, a detachment takes its place.
	gs.issue(load("res://scripts/sim/assign_to_front.gd").new("GER", front.id, [army.id] as Array[int]))
	_days(30)
	var survivors: Array = FS.stacks_of(gs, army)
	if survivors.size() > 1:
		gs.armies.erase(army.id)
		_days(1)
		var heir = null
		for a in gs.armies.values():
			if a.tag == "GER" and front.army_ids.has(a.id):
				heir = a
		_check(heir != null and heir.parent_id == 0, "when the army is destroyed, a detachment takes its place on the front")


## Which army's sector each province of the front's ordered line is in, from where the stacks stand: [army id per
## index], 0 for none, -1 for a province where two armies' divisions stand.
func _holders(front, roots: Array) -> Array:
	var out: Array = []
	for p in front.order:
		var who := 0
		for r in roots:
			for st in FS.stacks_of(gs, r):
				if st.province == p and st.path.is_empty():
					who = r.id if who == 0 or who == r.id else -1
		out.append(who)
	return out


func _test_broad() -> void:
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	gs.set_player("GER")
	gs.ai_enabled = false
	for w in gs.wars.values().duplicate():
		gs.set_war(w.a, w.b, false)
	gs.pending_joins.clear()
	var make = load("res://scripts/sim/designate_front.gd").new("GER", "East", [] as Array[int], "RUS")
	gs.issue(make)
	var front = gs.fronts[make.front_id]
	var UnitC = load("res://scripts/sim/unit.gd")
	var border: Array[int] = FS.order_line(Mil.border_provinces(gs, "GER", "RUS"))
	var roots: Array = []
	# Three armies of 12, 8 and 6 divisions, standing at the north end, the middle and the south end.
	for spec in [[12, 0], [8, border.size() / 2], [6, border.size() - 1]]:
		var a = Mil.new_army(gs, "GER", "Army %d" % (roots.size() + 1), border[spec[1]])
		for i in spec[0]:
			a.units.append(UnitC.new("infantry"))
		roots.append(a)
	var ids: Array[int] = []
	for r in roots:
		ids.append(r.id)
	gs.issue(load("res://scripts/sim/assign_to_front.gd").new("GER", front.id, ids))
	_days(50)
	var who := _holders(front, roots)
	_check(not who.has(-1), "no province holds the divisions of two armies (%s)" % str(who))
	# Each army's provinces are one stretch: along the line the holder changes at most once per army boundary.
	var runs := 0
	var last := 0
	for h in who:
		if h != 0 and h != last:
			runs += 1
			last = h
	_check(runs == 3, "the three armies hold three stretches side by side (%s)" % str(who))
	var first_ok: bool = who[0] == roots[0].id and who[who.size() - 1] == roots[2].id
	_check(first_ok, "each takes the stretch nearest to where it stood, so none crosses another")
	var spans: Array = [front.sectors[roots[0].id], front.sectors[roots[1].id], front.sectors[roots[2].id]]
	_check(spans[0].y <= spans[1].x and spans[1].y <= spans[2].x and spans[2].y == front.order.size() and spans[0].x == 0, "the sectors cover the line end to end without overlap (%s)" % str(spans))
	_check(spans[0].y - spans[0].x >= spans[2].y - spans[2].x, "the bigger army holds the longer stretch")
	# A fourth army joins at the south end: it takes a stretch there, and the others keep their order.
	var fourth = Mil.new_army(gs, "GER", "Army 4", border[border.size() - 1])
	for i in 10:
		fourth.units.append(UnitC.new("infantry"))
	roots.append(fourth)
	gs.issue(load("res://scripts/sim/assign_to_front.gd").new("GER", front.id, [fourth.id] as Array[int]))
	_days(60)
	who = _holders(front, roots)
	var order: Array = []
	for h in who:
		if h > 0 and not order.has(h):
			order.append(h)
	_check(not who.has(-1) and order.size() == 4 and order.find(roots[0].id) < order.find(roots[1].id) and order.find(roots[1].id) < order.find(roots[2].id), "with a fourth army the front holds four stretches, the first three still in order (%s)" % str(who))


## Deploys one army of 20 along the Russian border, wipes out what holds the southern end, and returns
## [front, army, the farthest index along the line any stack from the northern four provinces is heading to].
func _gap_after(cohesion: String) -> Array:
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	gs.set_player("GER")
	gs.ai_enabled = false
	for w in gs.wars.values().duplicate():
		gs.set_war(w.a, w.b, false)
	gs.pending_joins.clear()
	var make = load("res://scripts/sim/designate_front.gd").new("GER", "East", [] as Array[int], "RUS")
	gs.issue(make)
	var front = gs.fronts[make.front_id]
	var border: Array[int] = FS.order_line(Mil.border_provinces(gs, "GER", "RUS"))
	var army = Mil.new_army(gs, "GER", "Army", border[0])
	var UnitC = load("res://scripts/sim/unit.gd")
	for i in 20:
		army.units.append(UnitC.new("infantry"))
	gs.issue(load("res://scripts/sim/assign_to_front.gd").new("GER", front.id, [army.id] as Array[int]))
	_days(50)
	_check(not front.deploying.has(army.id), "%s: once every province has its share the army counts as in place" % cohesion)
	_check(gs.issue(load("res://scripts/sim/set_front_policy.gd").new("GER", front.id, "cohesion", cohesion)) and front.cohesion == cohesion, "the front is set to %s" % cohesion)
	var n: int = front.order.size()
	for st in FS.stacks_of(gs, army):
		var i: int = front.order.find(st.province)
		if i >= n - 3 and st != army:
			gs.armies.erase(st.id)
	var farthest := -1
	for d in 4:
		_days(1)
		for st in FS.stacks_of(gs, army):
			var from: int = front.order.find(st.province)
			if from >= 0 and from <= 3 and not st.path.is_empty():
				farthest = maxi(farthest, front.order.find(st.path.back()))
	return [front, army, farthest]


func _test_cohesion() -> void:
	var rigid := _gap_after("rigid")
	var n: int = rigid[0].order.size()
	_check(rigid[2] < n - 3, "rigid: the northern end does not march to fill a gap at the southern end (farthest %d of %d)" % [rigid[2], n])
	var flexible := _gap_after("flexible")
	_check(not gs.issue(load("res://scripts/sim/set_front_policy.gd").new("GER", flexible[0].id, "cohesion", "loose")), "an unknown cohesion is refused")


func _test_fallback_and_garrison() -> void:
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	gs.set_player("GER")
	gs.ai_enabled = false
	for w in gs.wars.values().duplicate():
		gs.set_war(w.a, w.b, false)
	gs.pending_joins.clear()
	var UnitC = load("res://scripts/sim/unit.gd")
	var Designate = load("res://scripts/sim/designate_front.gd")
	var Assign = load("res://scripts/sim/assign_to_front.gd")
	# A fallback line: a chain of three German provinces from the capital inland.
	var capital: int = gs.nations["GER"].capital
	var chain: Array[int] = [capital]
	while chain.size() < 3:
		var next := 0
		for n: int in Mil.neighbors(chain.back()):
			if gs.province_controller[n] == "GER" and not chain.has(n):
				next = n
				break
		if next == 0:
			break
		chain.append(next)
	var line_cmd = Designate.new("GER", "Berlin line", chain)
	_check(gs.issue(line_cmd), "a line is drawn round Berlin")
	var line_front = gs.fronts[line_cmd.front_id]
	_check(line_front.is_fallback(gs), "touching no enemy, it is a fallback line")
	var army = Mil.new_army(gs, "GER", "Reserve Army", capital)
	for i in 6:
		army.units.append(UnitC.new("infantry"))
	gs.issue(Assign.new("GER", line_front.id, [army.id] as Array[int]))
	_days(60)
	var top: int = Mil.cfg.combat.max_entrenchment
	var deepest := 0
	for st in FS.stacks_of(gs, army):
		deepest = maxi(deepest, st.entrenchment())
	_check(deepest > top, "on the fallback line the army digs in deeper than anywhere else (%d, against %d)" % [deepest, top])
	# A garrison of three ports far apart.
	var ports: Array[int] = []
	for p in gs.nations["GER"].provinces:
		if root.get_node("MapData").port_zones.has(p) and ports.size() < 3:
			if ports.all(func(q: int) -> bool: return (root.get_node("MapData").provinces[q].center as Vector2).distance_to(root.get_node("MapData").provinces[p].center) > 150.0):
				ports.append(p)
	_check(not gs.issue(Designate.new("GER", "", [gs.nations["FRA"].provinces[0]] as Array[int], "", "garrison")), "a garrison guards only provinces the nation holds")
	var g_cmd = Designate.new("GER", "Ports", ports, "", "garrison")
	_check(gs.issue(g_cmd) and gs.fronts[g_cmd.front_id].kind == "garrison" and not gs.fronts[g_cmd.front_id].is_fallback(gs), "a garrison of %d ports is set up" % ports.size())
	var guard = Mil.new_army(gs, "GER", "Coast Guard", capital)
	for i in 6:
		guard.units.append(UnitC.new("infantry"))
	gs.issue(Assign.new("GER", g_cmd.front_id, [guard.id] as Array[int]))
	_days(90)
	var guarded := 0
	for p in ports:
		for st in FS.stacks_of(gs, guard):
			if st.province == p and st.path.is_empty():
				guarded += 1
				break
	_check(guarded == ports.size(), "each port keeps some of the army's divisions (%d of %d)" % [guarded, ports.size()])
