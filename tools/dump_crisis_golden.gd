extends SceneTree
## Writes what the real game does with its crises, for the Rust port (rust/fs_sim) to reproduce: scenarios run day by day with the
## world's own quarrels switched on (pressure_ai) and the AI's turn off, a player who answers the demands made of them, mediates,
## backs a side and presses demands of their own. Every action is logged with its result; the crises, their ends, the
## cooldowns, the casus belli, the chronicle and the nations' standing are written down every few days.
##   godot --headless --path . -s res://tools/dump_crisis_golden.gd -- rust/fs_sim/tests/golden/crisis.json

const LOOSE := {"min_score": 0.3, "min_gap_months": 1, "max_active": 4, "max_wars": 12, "per_month": 2, "claim_min_tension": 20, "pair_cooldown_months": 12, "min_odds": 0.4}
var gs: Node
var clock: Node


func B(x: float) -> String:
	return str(PackedFloat64Array([x]).to_byte_array().decode_s64(0))


func _bits_map(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		out[k] = B(d[k])
	return out


func _initialize() -> void:
	await process_frame
	var out_path: String = OS.get_cmdline_user_args()[0]
	gs = root.get_node("GameState")
	clock = root.get_node("Clock")
	var Press: GDScript = load("res://scripts/sim/pressure.gd")
	var Dip: GDScript = load("res://scripts/sim/diplomacy.gd")
	var CrisisAct: GDScript = load("res://scripts/sim/crisis_action.gd")
	var PressDem: GDScript = load("res://scripts/sim/press_demand.gd")
	var runs := [
		{"name": "july_1914", "dir": "res://data/scenarios/july_1914/", "days": 600, "every": 10, "player": "SRB"},
		{"name": "july_1914", "dir": "res://data/scenarios/july_1914/", "days": 600, "every": 10, "player": "FRA"},
		{"name": "jan_1900", "dir": "res://data/scenarios/jan_1900/", "days": 800, "every": 10, "player": "GER"},
		{"name": "jan_1900", "dir": "res://data/scenarios/jan_1900/", "days": 800, "every": 10, "player": "BEL"},
		# the gate loosened, so that many more quarrels open and every threshold is tried
		{"name": "july_1914", "dir": "res://data/scenarios/july_1914/", "days": 700, "every": 10, "player": "ITA", "gate": LOOSE},
		{"name": "july_1914", "dir": "res://data/scenarios/july_1914/", "days": 700, "every": 10, "player": "BEL", "gate": LOOSE},
		{"name": "jan_1900", "dir": "res://data/scenarios/jan_1900/", "days": 900, "every": 10, "player": "FRA", "gate": LOOSE},
		{"name": "jan_1900", "dir": "res://data/scenarios/jan_1900/", "days": 900, "every": 10, "player": "ESP", "gate": LOOSE},
	]
	var result := []
	for run in runs:
		gs.player_tag = ""
		gs.load_scenario(run.dir)
		gs.ai_enabled = false
		gs.pressure_ai = true
		gs.set_player(run.player)
		var CrisisCls: GDScript = load("res://scripts/sim/crisis.gd")
		CrisisCls.load_config()
		for k in run.get("gate", {}):
			CrisisCls.cfg.gate[k] = run.gate[k]
		var log := []
		var snaps := [_snapshot()]
		var cycle := 0
		for d in run.days:
			# the player answers what is asked of them, helps in what is not theirs, and presses a demand now and then
			for ev in gs.pending_events.duplicate():
				var opt := 0
				if str(ev.event).begins_with("crisis:"):
					opt = cycle % ev.options.size()
					cycle += 1
				var ok: bool = Press.answer(gs, ev.id, opt)
				log.append([d, "answer", ev.id, opt, ok])
			if d % 7 == 3:
				for c in gs.crises.duplicate():
					var actions := ["mediate", "back_a", "back_b"] if gs.player_tag != c.b else ["yield", "refuse", "mobilize", "appeal"]
					var action: String = actions[cycle % actions.size()]
					cycle += 1
					var cmd = CrisisAct.new(gs.player_tag, c.id, action)
					var okc: bool = cmd.execute(gs)
					log.append([d, "crisis", c.id, action, okc])
			if d % 45 == 20:
				var kinds := ["claim", "border", "indemnity", "revanche", "disarm", "naval"]
				var neigh: Array = Dip.neighbor_nations(gs, gs.player_tag).duplicate()
				if gs.player_tag in Press.GREAT:
					for g in Press.GREAT:
						if g != gs.player_tag and g not in neigh:
							neigh.append(g)
				neigh.sort()
				if not neigh.is_empty():
					var b: String = neigh[cycle % neigh.size()]
					var kind: String = kinds[(cycle / 2) % kinds.size()]
					cycle += 1
					var pd = PressDem.new(gs.player_tag, b, kind)
					var okp: bool = pd.execute(gs)
					log.append([d, "press", b, kind, okp, pd.reason])
			clock.advance_day()
			if d % run.every == run.every - 1:
				snaps.append(_snapshot())
		result.append({"name": run.name, "player": run.player, "gate": run.get("gate", {}), "every": run.every, "days": run.days, "log": log, "snaps": snaps})
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(result))
	f.close()
	print("wrote ", out_path)
	quit(0)


func _crisis(c: Dictionary) -> Array:
	return [c.id, c.kind, c.a, c.b, JSON.stringify(c.demand), JSON.stringify(c.goal), c.start_day, c.think_day, c.deadline_day, c.backers_a.duplicate(), c.backers_b.duplicate(),
			c.title, c.text, c.get("mediators_tried", []).duplicate()]


func _snapshot() -> Dictionary:
	var nations := []
	for tag in gs.nations:
		var n = gs.nations[tag]
		nations.append([B(n.treasury), B(n.prestige), B(n.war_support), B(n.mobilization), B(n.diplomacy_points), n.provinces.size(), n.capital])
	var wars := []
	for w in gs.wars.values():
		wars.append([w.id, w.a, w.b, w.war_group])
	var owners := []
	for id in range(1, gs.province_owner.size()):
		owners.append(gs.province_owner[id])
	var cb := []
	for c in gs.casus_belli:
		cb.append([c.holder, c.target, c.kind, c.expires_day, c.get("refused_day", -1), JSON.stringify(c.get("goal", {}))])
	var chron := []
	for e in gs.chronicle.slice(0, 8):
		chron.append([e.date, e.title, e.text])
	var pend := []
	for p in gs.pending_events:
		pend.append([p.id, p.event, p.title, p.text, p.options.map(func(o): return [o.label, o.get("text", ""), o.get("tip", ""), o.get("effects", [])])])
	var ended := []
	for e in gs.crisis_log:
		ended.append([e.id, e.kind, e.a, e.b, e.start, e.end_day, e.outcome, e.title, e.end_date, e.goal])
	var ind: Array = gs.indemnities.map(func(i): return [i.payer, i.receiver, B(i.monthly), i.months_left])
	var rest: Array = gs.restrictions.map(func(r): return [r.nation, r.holder, r.get("kind", ""), r.until_day])
	return {"day": clock.days_elapsed, "date": clock.date_string(), "nations": nations, "wars": wars, "owners": owners, "casus_belli": cb,
			"crises": gs.crises.map(_crisis), "ended": ended, "cooldown": gs.crisis_cooldown.duplicate(), "next_id": gs.next_crisis_id,
			"chronicle": chron, "chronicle_size": gs.chronicle.size(), "pending": pend, "tension": B(gs.tension), "relations": _bits_map(gs.relations),
			"grievance": _bits_map(gs.grievance), "indemnities": ind, "restrictions": rest, "treaties": gs.treaties.size(), "uid": gs.next_event_uid}
