extends SceneTree
## Writes the whole game as it ships, for the Rust port (rust/fs_sim) to reproduce end to end with the AI playing: a scenario loaded, the AI
## switched on (`ai_enabled`, and the scenario's own `pressure_ai`), and the clock driven day by day through the game's own stages, in
## which the AI's turn runs where the game puts it. The nations, the ground, the armies and fleets, the fronts, the wars and treaties,
## the AI's campaigns, landings and plans are written down every few days. Floats are the bits of their 64-bit value.
##   godot --headless --path . -s res://tools/dump_ai_game_golden.gd -- rust/fs_sim/tests/golden/ai_game.json
##   gzip -9 -f rust/fs_sim/tests/golden/ai_game.json    # the test reads ai_game.json.gz

var gs: Node
var clock: Node
var Eco: GDScript
var Foc: GDScript
var Nav: GDScript
var Mil: GDScript
var Dip: GDScript
var Cri: GDScript
var AIc: GDScript
var AIB: GDScript
var AIF: GDScript
var AIFo: GDScript
var AIAm: GDScript
var AID: GDScript
var AIDip: GDScript
var AIO: GDScript
var AIN: GDScript
var AIL: GDScript
var parts: Array = []


func B(x: float) -> String:
	return str(PackedFloat64Array([x]).to_byte_array().decode_s64(0))


func _initialize() -> void:
	await process_frame
	var out_path: String = OS.get_cmdline_user_args()[0]
	gs = root.get_node("GameState")
	clock = root.get_node("Clock")
	Eco = load("res://scripts/sim/economy.gd")
	Foc = load("res://scripts/sim/focus.gd")
	Nav = load("res://scripts/sim/navy.gd")
	Mil = load("res://scripts/sim/military.gd")
	Dip = load("res://scripts/sim/diplomacy.gd")
	Cri = load("res://scripts/sim/crisis.gd")
	AIc = load("res://scripts/ai/ai.gd")
	AIB = load("res://scripts/ai/ai_budget.gd")
	AIF = load("res://scripts/ai/ai_focus.gd")
	AIFo = load("res://scripts/ai/ai_forces.gd")
	AIAm = load("res://scripts/ai/ai_ambition.gd")
	AID = load("res://scripts/ai/ai_defense.gd")
	AIDip = load("res://scripts/ai/ai_diplomacy.gd")
	AIO = load("res://scripts/ai/ai_offense.gd")
	AIN = load("res://scripts/ai/ai_navy.gd")
	AIL = load("res://scripts/ai/ai_landing.gd")
	var Design: GDScript = load("res://scripts/sim/designate_front.gd")
	var runs := [
		{"name": "july_1914", "dir": "res://data/scenarios/july_1914/", "days": 900, "every": 10, "player": "SRB", "wars": []},
		{"name": "july_1914", "dir": "res://data/scenarios/july_1914/", "days": 900, "every": 10, "player": "GBR", "wars": []},
		{"name": "jan_1900", "dir": "res://data/scenarios/jan_1900/", "days": 1800, "every": 10, "player": "GER", "wars": []},
		{"name": "jan_1900", "dir": "res://data/scenarios/jan_1900/", "days": 1800, "every": 10, "player": "USA", "wars": []},
	]
	var result := []
	for run in runs:
		gs.player_tag = ""
		gs.load_scenario(run.dir)
		gs.ai_enabled = true
		gs.set_player(run.player)
		AIc.load_config()
		for section in run.get("ai_cfg", {}):
			_merge(AIc.cfg[section], run.ai_cfg[section])
		var setup := []
		var purse: Array = run.get("purse", [])
		if not purse.is_empty():
			var tags: Array = gs.nations.keys()
			tags.sort()
			for i in tags.size():
				gs.nations[tags[i]].treasury *= purse[i % purse.size()]
		for w in run.wars:
			Dip.start_war(gs, w[0], w[1], true)
			for pair in ([] if run.get("nofronts", false) else [[w[0], w[1]], [w[1], w[0]]]):
				var cmd = Design.new(pair[0], "Front " + pair[1], [] as Array[int], pair[1], "line", 0)
				var ok: bool = cmd.execute(gs)
				setup.append([pair[0], pair[1], ok])
		var orders_log := []
		var MoveCmd: GDScript = load("res://scripts/sim/move_army.gd")
		for o in run.get("orders", []):
			var sent := 0
			for a in Mil.armies_of(gs, o[0]):
				if sent >= o[2]:
					break
				var target := _border_target(o[1], a.province, sent)
				if target == 0:
					continue
				var cmd = MoveCmd.new(o[0], a.id, target)
				var ok: bool = cmd.execute(gs)
				orders_log.append([o[0], a.id, target, ok])
				if ok:
					sent += 1
		var groups_log := []
		var MkGroup: GDScript = load("res://scripts/sim/create_army_group.gd")
		var MkLine: GDScript = load("res://scripts/sim/create_attack_line.gd")
		var SetLine: GDScript = load("res://scripts/sim/set_attack_line.gd")
		for g in run.get("groups", []):
			var list: Array = Mil.armies_of(gs, g[0])
			var gids: Array[int] = []
			for i in mini(g[2], list.size()):
				gids.append(list[i].id)
			var mk = MkGroup.new(g[0], g[1], gids)
			var ok1: bool = mk.execute(gs)
			var fid := 0
			for f in gs.fronts.values():
				if f.tag == g[0] and f.against == g[3]:
					fid = f.id
			var ml = MkLine.new(g[0], mk.group_id, g[3], fid if g[4] else 0)
			var ok2: bool = ml.execute(gs)
			var sl = SetLine.new(g[0], ml.line_id, true)
			var ok3: bool = sl.execute(gs)
			groups_log.append([g[0], g[1], gids, ok1, mk.group_id, ok2, ml.line_id, ok3, fid if g[4] else 0, g[3]])
		var snaps := [_snapshot()]
		for d in run.days:
			clock.advance_day()
			if d % run.every == run.every - 1:
				snaps.append(_snapshot())
		result.append({"name": run.name, "player": run.player, "wars": run.wars, "pressure": gs.pressure_ai, "ai_cfg": run.get("ai_cfg", {}), "setup": setup, "orders": orders_log, "groups": groups_log, "every": run.every, "snaps": snaps})
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(result))
	f.close()
	print("wrote ", out_path)
	quit(0)


func _snapshot() -> Dictionary:
	var nations := []
	for tag in gs.nations:
		var n = gs.nations[tag]
		var jobs := []
		for j in n.construction:
			jobs.append([j.province, j.type, j.days_left, B(j.points_left)])
		nations.append([B(n.treasury), B(n.tax_rate), B(n.investment), B(n.arms_share), B(n.munitions), B(n.diplomacy_points), B(n.prestige),
				B(n.mobilization), B(n.budget.get("net", 0.0)), jobs, n.focus.get("id", "") if not n.focus.is_empty() else "", n.focus_done.duplicate(),
				JSON.stringify(n.focus_count), gs.ai_budget_stamp.get(tag, 0), n.provinces.size()])
	var owners := []
	for id in range(1, gs.province_owner.size()):
		owners.append(gs.province_owner[id])
	var armies := []
	for a in gs.armies.values():
		armies.append([a.id, a.tag, a.province, B(a.men()), a.units.size(), a.path.size(), a.front_id, a.pin, a.parent_id, a.path.duplicate(), B(a.move_days_left), a.fleet_id])
	var recruiting := []
	for tag in gs.nations:
		recruiting.append(gs.nations[tag].recruiting.map(func(j): return [j.type, j.province, j.days_left]))
	var manpower := []
	for tag in gs.nations:
		manpower.append([gs.nations[tag].manpower, gs.nations[tag].men_in_units])
	var wars := []
	for w in gs.wars.values():
		wars.append([w.id, w.a, w.b])
	var fronts := []
	for f in gs.fronts.values():
		fronts.append([f.id, f.tag, f.against, f.provinces.duplicate(), f.anchors.duplicate(), f.army_ids.duplicate()])
	var controllers := []
	for id in range(1, gs.province_controller.size()):
		controllers.append(gs.province_controller[id])
	var camps := []
	for tag in gs.ai_campaign:
		var c: Dictionary = gs.ai_campaign[tag]
		camps.append([tag, "main", c.enemy, c.target, c.staging, c.armies.duplicate(), c.phase, c.started])
	for tag in gs.ai_campaign_extra:
		for c in gs.ai_campaign_extra[tag]:
			camps.append([tag, "extra", c.enemy, c.target, c.staging, c.armies.duplicate(), c.phase, c.started])
	var lines := []
	for l in gs.attack_lines.values():
		var lc: Dictionary = l.campaign
		lines.append([l.id, l.active, l.wait, [lc.enemy, lc.target, lc.staging, lc.armies.duplicate(), lc.phase, lc.started, lc.get("done", false)] if not lc.is_empty() else []])
	var fleets := []
	for f in gs.fleets.values():
		fleets.append([f.id, f.tag, f.display_name, f.port, f.zone, f.ships.map(func(sh): return [sh.type, B(sh.strength), B(sh.morale)]), f.path.duplicate(), f.dest_port, f.mission, f.landing, f.days_out, f.entering, f.fighting, f.retreating, B(f.move_days_left)])
	var navy_mem := {}
	for tag in gs.ai_navy:
		navy_mem[tag] = gs.ai_navy[tag].assign.duplicate()
	var landings := {}
	for tag in gs.ai_landing:
		var l: Dictionary = gs.ai_landing[tag]
		landings[tag] = [l.enemy, l.target, l.port, l.fleet, l.armies.duplicate(), l.phase, l.started, l.zone]
	var yards := []
	for tag in gs.nations:
		yards.append(gs.nations[tag].shipbuilding.map(func(j): return [j.type, j.province, j.days_left]))
	var treaties := []
	for t in gs.treaties:
		treaties.append([t.id, t.kind, t.a, t.b, t.start_day, t.end_day])
	var crises := []
	for c in gs.crises:
		crises.append([c.id, c.kind, c.a, c.b])
	var cbs := []
	for c in gs.casus_belli:
		cbs.append([c.holder, c.target, c.kind])
	var rel := {}
	for k in gs.relations:
		rel[k] = B(gs.relations[k])
	var grv := {}
	for k in gs.grievance:
		grv[k] = B(gs.grievance[k])
	return {"fleets_ai": fleets, "navy_mem": navy_mem, "landings": landings, "landing_wait": gs.ai_landing_wait.duplicate(), "navy_need": gs.ai_navy_need.duplicate(), "yards": yards, "controllers": controllers, "campaigns": camps, "campaign_wait": gs.ai_campaign_wait.duplicate(), "lines": lines, "treaties": treaties, "crises": crises, "cbs": cbs, "relations": rel, "grievance": grv, "declarations": [gs.ai_declarations.total, gs.ai_declarations.unjustified], "fronts": fronts, "reserve": gs.ai_reserve.duplicate(), "anchor_stamp": gs.ai_anchor_stamp.duplicate(), "day": clock.days_elapsed, "date": clock.date_string(), "nations": nations, "owners": owners, "tension": B(gs.tension), "armies": armies, "recruiting": recruiting,
			"manpower": manpower, "wars": wars, "ambition": gs.ai_ambition.duplicate(true), "ambition_wait": gs.ai_ambition_wait.duplicate(), "plans": JSON.stringify(gs.ai_plans)}


func _border_target(enemy: String, from: int, index: int) -> int:
	var seen := {from: 0}
	var queue := [from]
	var found := []
	while not queue.is_empty() and found.size() <= index + 1:
		var cur: int = queue.pop_front()
		if gs.province_owner[cur] == enemy and gs.province_controller[cur] == enemy:
			found.append(cur)
		for n in Mil.neighbors(cur):
			if not seen.has(n):
				seen[n] = seen[cur] + 1
				queue.append(n)
	return found[index] if found.size() > index else (found[0] if not found.is_empty() else 0)


func _merge(dst: Dictionary, src: Dictionary) -> void:
	for k in src:
		if src[k] is Dictionary and dst.get(k) is Dictionary:
			_merge(dst[k], src[k])
		else:
			dst[k] = src[k]
