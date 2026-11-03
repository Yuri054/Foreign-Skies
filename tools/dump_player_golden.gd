extends SceneTree
## Writes whole games with a player who plays, for the Rust port (rust/fs_sim) to reproduce: the AI plays every other nation, as it does in the
## shipped game, and the player's nation is given a rotation of about twenty kinds of command (policies, works, units, marches, a declaration
## of war, treaties, gifts, demands, peace offers, ships and fleets, a focus) and answers every question put to it. Each command is made through
## `GameState.issue` and logged with its arguments and whether it was carried out; the port replays the same commands. The world is written
## down every few days. Floats are the bits of their 64-bit value.
##   godot --headless --path . -s res://tools/dump_player_golden.gd -- rust/fs_sim/tests/golden/player.json
##   gzip -9 -f rust/fs_sim/tests/golden/player.json    # the test reads player.json.gz

var gs: Node
var clock: Node
var Mil: GDScript
var Dip: GDScript
var Pea: GDScript
var Press: GDScript
var Foc: GDScript
var Nav: GDScript
var Eco: GDScript
var snap_script: GDScript
var C_SetEconomyPolicy: GDScript
var C_ConstructBuilding: GDScript
var C_RaiseUnits: GDScript
var C_MoveArmy: GDScript
var C_DeclareWar: GDScript
var C_ProposeTreaty: GDScript
var C_ImproveRelations: GDScript
var C_BuyPoints: GDScript
var C_BuyMunitions: GDScript
var C_SetFocus: GDScript
var C_PressDemand: GDScript
var C_ProposePeace: GDScript
var C_Gift: GDScript
var C_RaiseShips: GDScript
var C_MoveFleet: GDScript
var C_CrisisAction: GDScript
var C_DemobilizeUnits: GDScript
var C_CancelTreaty: GDScript
var C_AnswerJoin: GDScript
var C_AnswerPeace: GDScript
var C_MergeFleets: GDScript
var C_SplitFleet: GDScript


func B(x: float) -> String:
	return str(PackedFloat64Array([x]).to_byte_array().decode_s64(0))


func _initialize() -> void:
	await process_frame
	var out_path: String = OS.get_cmdline_user_args()[0]
	gs = root.get_node("GameState")
	clock = root.get_node("Clock")
	Mil = load("res://scripts/sim/military.gd")
	Dip = load("res://scripts/sim/diplomacy.gd")
	Pea = load("res://scripts/sim/peace.gd")
	Press = load("res://scripts/sim/pressure.gd")
	Foc = load("res://scripts/sim/focus.gd")
	Nav = load("res://scripts/sim/navy.gd")
	Eco = load("res://scripts/sim/economy.gd")
	C_SetEconomyPolicy = load("res://scripts/sim/set_economy_policy.gd")
	C_ConstructBuilding = load("res://scripts/sim/construct_building.gd")
	C_RaiseUnits = load("res://scripts/sim/raise_units.gd")
	C_MoveArmy = load("res://scripts/sim/move_army.gd")
	C_DeclareWar = load("res://scripts/sim/declare_war.gd")
	C_ProposeTreaty = load("res://scripts/sim/propose_treaty.gd")
	C_ImproveRelations = load("res://scripts/sim/improve_relations.gd")
	C_BuyPoints = load("res://scripts/sim/buy_points.gd")
	C_BuyMunitions = load("res://scripts/sim/buy_munitions.gd")
	C_SetFocus = load("res://scripts/sim/set_focus.gd")
	C_PressDemand = load("res://scripts/sim/press_demand.gd")
	C_ProposePeace = load("res://scripts/sim/propose_peace.gd")
	C_Gift = load("res://scripts/sim/gift.gd")
	C_RaiseShips = load("res://scripts/sim/raise_ships.gd")
	C_MoveFleet = load("res://scripts/sim/move_fleet.gd")
	C_CrisisAction = load("res://scripts/sim/crisis_action.gd")
	C_DemobilizeUnits = load("res://scripts/sim/demobilize_units.gd")
	C_CancelTreaty = load("res://scripts/sim/cancel_treaty.gd")
	C_AnswerJoin = load("res://scripts/sim/answer_join.gd")
	C_AnswerPeace = load("res://scripts/sim/answer_peace.gd")
	C_MergeFleets = load("res://scripts/sim/merge_fleets.gd")
	C_SplitFleet = load("res://scripts/sim/split_fleet.gd")
	var runs := [
		{"name": "july_1914", "dir": "res://data/scenarios/july_1914/", "days": 700, "every": 10, "player": "GBR"},
		{"name": "july_1914", "dir": "res://data/scenarios/july_1914/", "days": 700, "every": 10, "player": "SRB"},
		{"name": "july_1914", "dir": "res://data/scenarios/july_1914/", "days": 700, "every": 10, "player": "GER"},
		{"name": "july_1914", "dir": "res://data/scenarios/july_1914/", "days": 700, "every": 10, "player": "ITA"},
		{"name": "jan_1900", "dir": "res://data/scenarios/jan_1900/", "days": 1200, "every": 20, "player": "FRA"},
		{"name": "jan_1900", "dir": "res://data/scenarios/jan_1900/", "days": 1200, "every": 20, "player": "RUS"},
	]
	var result := []
	for run in runs:
		gs.player_tag = ""
		gs.difficulty = "historical"
		gs.load_scenario(run.dir)
		gs.ai_enabled = true
		gs.set_player(run.player)
		var log := []
		var snaps := [_snapshot()]
		var k := 0
		for d in run.days:
			_answer_all(d, log)
			if d % 2 == 0:
				_play(d, k, run.player, log)
				k += 1
			clock.advance_day()
			if d % run.every == run.every - 1:
				snaps.append(_snapshot())
		result.append({"name": run.name, "player": run.player, "every": run.every, "days": run.days, "pressure": gs.pressure_ai, "log": log, "snaps": snaps})
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(result))
	f.close()
	print("wrote ", out_path)
	quit(0)


## The player answers whatever waits for an answer, by turns yes and no.
func _answer_all(d: int, log: Array) -> void:
	for ev in gs.pending_events.duplicate():
		var opt: int = (d / 2 + ev.id) % ev.options.size()
		var ok: bool = Press.answer(gs, ev.id, opt)
		log.append([d, "answer_event", [ev.id, opt], ok])
	for j in gs.pending_joins.duplicate():
		var yes: bool = (d / 2 + j.id) % 3 != 0
		var cmd = C_AnswerJoin.new(j.id, yes)
		var ok: bool = gs.issue(cmd)
		log.append([d, "answer_join", [j.id, yes], ok])
	for o in gs.pending_offers.duplicate():
		var yes2: bool = (d / 2 + o.id) % 2 == 0
		var cmd2 = C_AnswerPeace.new(o.id, yes2)
		var ok2: bool = gs.issue(cmd2)
		log.append([d, "answer_peace", [o.id, yes2], ok2])


func _tags() -> Array:
	var t: Array = gs.nations.keys()
	t.sort()
	return t


func _other(me: String, k: int) -> String:
	var t := _tags()
	var o: String = t[k % t.size()]
	return o if o != me and not gs.nations[o].provinces.is_empty() else t[(k + 1) % t.size()]


func _play(d: int, k: int, me: String, log: Array) -> void:
	var n = gs.nations[me]
	if n.provinces.is_empty():
		return
	var kind := k % 24
	var cmd = null
	var args: Array = []
	var name := ""
	match kind:
		0:
			name = "policy"
			args = ["tax_rate", 0.08 + 0.04 * (k % 7)]
			cmd = C_SetEconomyPolicy.new(me, args[0], args[1])
		1:
			name = "policy"
			args = ["arms_share", 0.05 * (k % 9)]
			cmd = C_SetEconomyPolicy.new(me, args[0], args[1])
		2:
			name = "policy"
			args = ["mobilization", 0.15 * (k % 5)]
			cmd = C_SetEconomyPolicy.new(me, args[0], args[1])
		3:
			name = "policy"
			args = ["investment", 0.3 * (k % 4)]
			cmd = C_SetEconomyPolicy.new(me, args[0], args[1])
		4:
			name = "build"
			var types: Array = Eco.building_ids()
			var type: String = types[k % types.size()]
			var provs: Array = Array(n.provinces)
			var pick := 0
			for i in provs.size():
				var id: int = provs[(i + k) % provs.size()]
				if Eco.build_problem(gs, me, id, type, true).is_empty():
					pick = id
					break
			if pick == 0:
				return
			args = [pick, type]
			cmd = C_ConstructBuilding.new(me, pick, type)
		5:
			name = "raise"
			var ut: Array = ["infantry", "cavalry", "artillery"]
			args = [n.capital, ut[k % 3], 1 + k % 2]
			cmd = C_RaiseUnits.new(me, n.capital, args[1], args[2])
		6, 7:
			name = "move"
			var list: Array = Mil.armies_of(gs, me)
			if list.is_empty():
				return
			var a = list[(k * 7) % list.size()]
			var dest := 0
			var enemies: Array = []
			for w in gs.wars_of(me):
				enemies.append(w.other(me))
			if not enemies.is_empty():
				dest = _border_target(enemies[k % enemies.size()], a.province, k % 3)
			if dest == 0:
				var nb: Array = Mil.neighbors(a.province)
				if nb.is_empty():
					return
				dest = nb[k % nb.size()]
			args = [a.id, dest]
			cmd = C_MoveArmy.new(me, a.id, dest)
		8:
			name = "declare"
			var targets: Array = Dip.neighbor_nations(gs, me)
			if targets.is_empty():
				return
			var t: String = targets[k % targets.size()]
			var opts: Array = Dip.casus_belli_options(gs, me, t)
			args = [t, opts[0]]
			cmd = C_DeclareWar.new(me, t, opts[0])
		9:
			name = "treaty"
			var kinds: Array = ["alliance", "guarantee", "nap", "passage"]
			args = [_other(me, k * 3), kinds[(k / 24) % 4]]
			cmd = C_ProposeTreaty.new(me, args[0], args[1])
		10:
			name = "improve"
			args = [_other(me, k * 5)]
			cmd = C_ImproveRelations.new(me, args[0])
		11:
			name = "points"
			cmd = C_BuyPoints.new(me)
		12:
			name = "munitions"
			args = [5.0 + k % 4]
			cmd = C_BuyMunitions.new(me, args[0])
		13:
			name = "focus"
			var tree: Array = Foc.tree_of(me)
			var chosen := ""
			for i in tree.size():
				var f2: Dictionary = tree[(i + k) % tree.size()]
				if Foc.block(gs, me, f2.id) == "":
					chosen = f2.id
					break
			if chosen == "":
				return
			args = [chosen]
			cmd = C_SetFocus.new(me, chosen)
		14:
			name = "press"
			var pk: Array = ["claim", "border", "indemnity", "revanche", "disarm", "naval"]
			var targets2: Array = Dip.neighbor_nations(gs, me)
			if targets2.is_empty():
				return
			args = [targets2[k % targets2.size()], pk[(k / 24) % 6]]
			cmd = C_PressDemand.new(me, args[0], args[1])
		15:
			name = "peace"
			var ws: Array = gs.wars_of(me)
			if ws.is_empty():
				return
			var w = ws[k % ws.size()]
			var foe: String = w.other(me)
			var mode: String = "offer" if k % 2 == 0 else "demand"
			var demands: Array = []
			if (k / 24) % 3 == 1:
				demands = [{"kind": "indemnity", "share": 0.1, "months": 12}]
			elif (k / 24) % 3 == 2:
				var held: Array = []
				for id2 in gs.nations[me if mode == "offer" else foe].provinces:
					if gs.province_controller[id2] == (foe if mode == "offer" else me):
						held.append(id2)
				if not held.is_empty():
					demands = [{"kind": "province", "ids": held.slice(0, 1)}]
			args = [foe, mode, demands]
			cmd = C_ProposePeace.new(me, foe, mode, demands)
		16:
			name = "gift"
			args = [_other(me, k * 2), 2.0 + k % 3]
			cmd = C_Gift.new(me, args[0], args[1])
		17:
			name = "ships"
			var ports: Array = []
			for id3 in n.provinces:
				if not MapData_zones(id3).is_empty():
					ports.append(id3)
			if ports.is_empty():
				return
			var st: Array = ["destroyer", "cruiser", "submarine", "transport", "dreadnought"]
			args = [ports[k % ports.size()], st[(k / 24) % 5], 1]
			cmd = C_RaiseShips.new(me, args[0], args[1], 1)
		18:
			name = "fleet"
			var fl: Array = Nav.fleets_of(gs, me)
			if fl.is_empty():
				return
			var f3 = fl[k % fl.size()]
			var zones: Array = []
			var ml := load("res://scripts/sim/map_data.gd") if false else null
			var zc: int = gs.sea_control.size()
			var z := 1 + (k * 13) % 30
			args = [f3.id, z, 0]
			cmd = C_MoveFleet.new(me, f3.id, z, 0)
		19:
			name = "crisis"
			if gs.crises.is_empty():
				return
			var c = gs.crises[k % gs.crises.size()]
			var acts: Array = ["yield", "refuse", "mobilize", "appeal"] if c.b == me else ["mediate", "back_a", "back_b"]
			args = [c.id, acts[(k / 24) % acts.size()]]
			cmd = C_CrisisAction.new(me, c.id, args[1])
		20:
			name = "demobilize"
			args = [0, 1 + k % 3]
			cmd = C_DemobilizeUnits.new(me, 0, args[1])
		23:
			name = "split"
			var big: Array = []
			for fs in Nav.fleets_of(gs, me):
				if fs.ships.size() >= 2:
					big.append(fs.id)
			if big.is_empty():
				return
			args = [big[k % big.size()], [0]]
			cmd = C_SplitFleet.new(me, args[0], [0] as Array[int])
		22:
			name = "merge"
			var by_place := {}
			for fm in Nav.fleets_of(gs, me):
				var key := "%d:%d" % [fm.port, fm.zone]
				if not by_place.has(key):
					by_place[key] = []
				by_place[key].append(fm.id)
			var groups: Array = []
			for key in by_place:
				if by_place[key].size() >= 2:
					groups.append(by_place[key])
			if groups.is_empty():
				return
			var picked: Array[int] = []
			picked.assign(groups[k % groups.size()])
			args = [picked]
			cmd = C_MergeFleets.new(me, picked)
		21:
			name = "cancel"
			var mine: Array = []
			for t2 in gs.treaties:
				if t2.a == me or t2.b == me:
					mine.append(t2.id)
			if mine.is_empty():
				return
			args = [mine[k % mine.size()]]
			cmd = C_CancelTreaty.new(me, args[0])
	if cmd == null:
		return
	var ok: bool = gs.issue(cmd)
	if name == "policy":
		args = [args[0], B(args[1])]
	log.append([d, name, args, ok])
	# a fleet just split is put together again (one time out of two), and once with a wrong order
	if name == "split" and ok:
		var pair: Array[int] = []
		if k % 2 == 0:
			pair.append(args[0])
			pair.append(cmd.new_fleet_id)
		else:
			pair.append(cmd.new_fleet_id)
			pair.append(args[0])
		var back = C_MergeFleets.new(me, pair)
		var ok2: bool = gs.issue(back)
		log.append([d, "merge", [pair.duplicate()], ok2])
		var twice: Array[int] = []
		twice.append(args[0])
		twice.append(args[0])
		var bad = C_MergeFleets.new(me, twice)
		var ok3: bool = gs.issue(bad)
		log.append([d, "merge", [twice.duplicate()], ok3])


func MapData_zones(id: int) -> Array:
	var md = load("res://scripts/sim/map_data.gd") if false else null
	return root.get_node("MapData").zones_of_port(id) if root.has_node("MapData") else []


func _border_target(enemy: String, from: int, index: int) -> int:
	var seen := {from: 0}
	var queue := [from]
	var found := []
	while not queue.is_empty() and found.size() <= index + 1:
		var cur: int = queue.pop_front()
		if gs.province_owner[cur] == enemy and gs.province_controller[cur] == enemy:
			found.append(cur)
		for nb in Mil.neighbors(cur):
			if not seen.has(nb):
				seen[nb] = seen[cur] + 1
				queue.append(nb)
	return found[index] if found.size() > index else (found[0] if not found.is_empty() else 0)


func _snapshot() -> Dictionary:
	var nations := []
	for tag in gs.nations:
		var n = gs.nations[tag]
		nations.append([B(n.treasury), B(n.prestige), B(n.war_support), B(n.mobilization), B(n.diplomacy_points), n.provinces.size(), n.capital, B(n.tax_rate), B(n.investment),
				B(n.arms_share), B(n.munitions), n.population, n.manpower, n.men_in_units, n.focus.get("id", "") if not n.focus.is_empty() else "", n.construction.size(), n.recruiting.size(), n.shipbuilding.size()])
	var owners := []
	var controllers := []
	for id in range(1, gs.province_owner.size()):
		owners.append(gs.province_owner[id])
		controllers.append(gs.province_controller[id])
	var armies := []
	for a in gs.armies.values():
		armies.append([a.id, a.tag, a.province, B(a.men()), a.units.size(), a.path.duplicate(), a.front_id, a.fleet_id])
	var fleets := []
	for f in gs.fleets.values():
		fleets.append([f.id, f.tag, f.port, f.zone, f.ships.size(), f.path.duplicate(), f.mission])
	var wars := []
	for w in gs.wars.values():
		wars.append([w.id, w.a, w.b, w.war_group])
	var treaties := []
	for t in gs.treaties:
		treaties.append([t.id, t.kind, t.a, t.b])
	var rel := {}
	for k in gs.relations:
		rel[k] = B(gs.relations[k])
	return {"day": clock.days_elapsed, "date": clock.date_string(), "nations": nations, "owners": owners, "controllers": controllers, "armies": armies, "fleets": fleets, "wars": wars,
			"treaties": treaties, "relations": rel, "tension": B(gs.tension), "crises": gs.crises.map(func(c): return [c.id, c.kind, c.a, c.b]), "pending": [gs.pending_events.size(), gs.pending_joins.size(), gs.pending_offers.size()],
			"chronicle": gs.chronicle.size()}
