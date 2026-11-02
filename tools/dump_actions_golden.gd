extends SceneTree
## Writes what the GDScript does when the player acts in diplomacy, for the Rust port (rust/fs_sim) to reproduce: buying diplomacy
## points (the price climbing), starting efforts to improve relations, proposing treaties (accepted and refused, with their points and
## prestige), gifts (and the memory of them), cancelling treaties and what it costs, naming alliances, and declaring war for points.
## Between the actions the real game runs by itself for days and months (the clock driven, the AI off). Floats are the bits of their
## 64-bit value.
##   godot --headless --path . -s res://tools/dump_actions_golden.gd -- rust/fs_sim/tests/golden/actions.json

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
	var peace_dir := _make_peace_copy("july_1914")
	var campaigns := [
		{"name": "points", "player": "GBR", "actions": [
			["buy"], ["buy"], ["buy"], ["days", 35, 35], ["buy"], ["gain", "GBR", 150], ["buy"], ["buy"], ["gift", "GBR", "NED", 500.0], ["buy"], ["treasury", "GBR", 0.5], ["buy"]]},
		{"name": "improve", "player": "GBR", "actions": [
			["improve", "GBR", "NED"], ["improve", "GBR", "NED"], ["improve", "GBR", "GER"], ["improve", "GBR", "SUI"], ["improve", "GBR", "DEN"], ["improve", "GBR", "GBR"],
			["gain", "GBR", 100], ["improve", "GBR", "DEN"], ["improve", "GBR", "SUI"], ["days", 100, 20], ["improve", "GBR", "DEN"], ["war", "GBR", "GER"], ["improve", "GBR", "GER"],
			["days", 280, 40], ["improve", "GBR", "ESP"], ["days", 20, 5],
			["rel", "GBR", "LUX", 100.0], ["improve", "GBR", "LUX"], ["setpoints", "GBR", 5.0], ["improve", "GBR", "NOR"], ["gain", "GBR", 60], ["improve", "GBR", "NOR"]]},
		{"name": "treaties", "player": "GBR", "actions": [
			["rel", "ITA", "GBR", 45.0], ["rel", "BEL", "NED", 60.0], ["rel", "DEN", "SWE", 70.0], ["rel", "NOR", "SWE", 65.0], ["rel", "POR", "ESP", 80.0], ["gain", "GBR", 150],
			["propose", "GBR", "ITA", "alliance"], ["propose", "GBR", "ITA", "guarantee"], ["propose", "GBR", "ITA", "nap"], ["propose", "GBR", "ITA", "passage"], ["propose", "GBR", "ITA", "nonsense"],
			["propose", "GBR", "FRA", "alliance"], ["propose", "GBR", "GBR", "nap"], ["propose", "NED", "GBR", "guarantee"], ["propose", "POR", "ESP", "nap"], ["propose", "POR", "ESP", "alliance"],
			["propose", "DEN", "SWE", "alliance"], ["propose", "NOR", "SWE", "alliance"], ["propose", "SWE", "NOR", "guarantee"], ["gain", "NED", 100], ["rel", "GER", "NED", 55.0], ["rel", "FRA", "NED", 55.0], ["rel", "GBR", "NED", 55.0], ["propose", "NED", "BEL", "alliance"],
			["treasury", "NED", 100.0], ["gift", "NED", "BEL", 40.0], ["gift", "NED", "BEL", 40.0], ["propose", "NED", "BEL", "alliance"], ["propose", "GER", "NED", "alliance"], ["propose", "GBR", "NED", "alliance"],
			["propose", "FRA", "NED", "alliance"], ["days", 35, 5], ["propose", "ITA", "GBR", "alliance"], ["prestige", "ITA", 30.0], ["propose", "ITA", "GBR", "alliance"],
			["propose", "ITA", "SWE", "alliance"], ["prestige", "ITA", -40.0], ["propose", "ITA", "SWE", "nap"], ["days", 5, 5],
			["gain", "ITA", 200], ["gain", "GBR", 200], ["propose", "GBR", "ITA", "passage"], ["prestige", "ITA", 30.0], ["rel", "SWE", "ITA", 30.0], ["propose", "ITA", "SWE", "alliance"],
			["prestige", "ITA", 100.0], ["rel", "ESP", "ITA", 20.0], ["propose", "ITA", "ESP", "alliance"], ["rel", "GER", "GBR", 100.0], ["propose", "GBR", "GER", "alliance"],
			["rival", "AUH>ESP", 0.5], ["rel", "ESP", "AUH", 100.0], ["propose", "AUH", "ESP", "alliance"], ["propose", "AUH", "ESP", "nap"], ["propose", "AUH", "ESP", "guarantee"],
			["cancel", "GBR", "ITA", "nap"], ["cancel_id", "POR", "GER", "AUH", "alliance"], ["days", 5, 5]]},
		{"name": "gifts", "player": "GBR", "actions": [
			["gift", "GBR", "NED", 5.0], ["gift", "GBR", "NED", 5.0], ["gift", "GBR", "NED", 0.0], ["gift", "GBR", "NED", -3.0], ["gift", "GBR", "NED", 100000.0], ["gift", "GBR", "GBR", 1.0],
			["gift", "GBR", "LUX", 12.5], ["gift", "GBR", "SUI", 1.0], ["gain", "GBR", 100], ["treasury", "GBR", 500.0], ["gift", "GBR", "GER", 20.0], ["gift", "GBR", "FRA", 20.0], ["gift", "GBR", "SRB", 8.0], ["gift", "GBR", "SRB", 8.0], ["days", 100, 20], ["gift", "GBR", "SRB", 8.0], ["days", 100, 50]]},
		{"name": "cancel", "player": "GBR", "actions": [
			["cancel", "GBR", "FRA", "alliance"], ["cancel", "GER", "AUH", "alliance"], ["cancel", "GBR", "BEL", "guarantee"], ["cancel", "GER", "BEL", "guarantee"], ["cancel", "GBR", "RUS", "alliance"],
			["gain", "GBR", 100], ["cancel", "GBR", "RUS", "alliance"], ["cancel", "GBR", "FRA", "alliance"], ["cancel", "GBR", "POR", "alliance"], ["cancel", "ITA", "GER", "neutral_pact"],
			["cancel", "ITA", "GER", "alliance"], ["cancel", "ITA", "AUH", "alliance"], ["cancel", "GBR", "ITA", "alliance"], ["cancel", "POR", "GBR", "alliance"], ["days", 35, 5]]},
		{"name": "naming", "player": "GBR", "actions": [
			["gain", "POR", 100], ["gain", "ESP", 100], ["gain", "NED", 100], ["gain", "DEN", 100], ["treasury", "POR", 200.0], ["treasury", "ESP", 200.0], ["treasury", "NED", 200.0],
			["treasury", "DEN", 200.0], ["rel", "POR", "ESP", 70.0], ["rel", "NED", "DEN", 70.0], ["rel", "ESP", "NED", 60.0], ["rel", "POR", "NED", 60.0], ["gift", "POR", "ESP", 30.0], ["gift", "ESP", "POR", 30.0],
			["propose", "POR", "ESP", "alliance"], ["rename", "POR", "Iberian League"], ["rename", "ESP", "  "], ["rename", "GBR", "Mine"], ["rename", "FRA", "Entente?"],
			["rename", "XXX", "Nope"], ["rename", "ESP", "A very long name for an alliance that has far too many characters in it to fit"], ["propose", "NED", "DEN", "alliance"],
			["gift", "NED", "DEN", 30.0], ["gift", "DEN", "NED", 30.0], ["propose", "NED", "DEN", "alliance"], ["propose", "ESP", "NED", "alliance"], ["rename", "NED", "Northern Pact"],
			["propose", "POR", "NED", "alliance"], ["cancel", "POR", "ESP", "alliance"], ["rename", "ESP", "Alone"], ["days", 3, 1]]},
	]
	var result := []
	for camp in campaigns:
		gs.player_tag = ""
		gs.load_scenario(peace_dir)
		gs.ai_enabled = false
		gs.pressure_ai = false
		gs.set_player(camp.player)
		var log := []
		var snaps := [_snapshot()]
		for act in camp.actions:
			_play(act, log, snaps)
		result.append({"name": camp.name, "player": camp.player, "log": log, "snaps": snaps})
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(result))
	f.close()
	print("wrote ", out_path)
	quit(0)


func _treaty_id(a: String, b: String, kind: String) -> int:
	for t in gs.treaties:
		if t.kind == kind and ((t.a == a and t.b == b) or (t.a == b and t.b == a)) and t.active_on(clock.days_elapsed):
			return t.id
	return 9999


func _play(act: Array, log: Array, snaps: Array) -> void:
	match act[0]:
		"war":
			gs.set_war(act[1], act[2], true, "none", 0, {})
			log.append(act)
		"rel":
			var dip: GDScript = load("res://scripts/sim/diplomacy.gd")
			dip.set_relation(gs, act[1], act[2], act[3])
			log.append(act)
		"gain":
			gs.nations[act[1]].diplomacy_points = minf(200.0, gs.nations[act[1]].diplomacy_points + act[2])
			log.append(act)
		"setpoints":
			gs.nations[act[1]].diplomacy_points = act[2]
			log.append(act)
		"rival":
			gs.rivalries[act[1]] = act[2]
			log.append(act)
		"cancel_id":
			var cmd: GDScript = load("res://scripts/sim/cancel_treaty.gd")
			var id := _treaty_id(act[2], act[3], act[4])
			var ok: bool = cmd.new(act[1], id).execute(gs)
			log.append(["cancel", act[1], id, ok])
		"treasury":
			gs.nations[act[1]].treasury = act[2]
			log.append(act)
		"prestige":
			gs.nations[act[1]].prestige = act[2]
			log.append(act)
		"buy":
			var cmd: GDScript = load("res://scripts/sim/buy_points.gd")
			var ok: bool = cmd.new("GBR").execute(gs)
			log.append(["buy", "GBR", ok])
		"improve":
			var cmd: GDScript = load("res://scripts/sim/improve_relations.gd")
			var ok: bool = cmd.new(act[1], act[2]).execute(gs)
			log.append(["improve", act[1], act[2], ok])
		"propose":
			var cmd: GDScript = load("res://scripts/sim/propose_treaty.gd")
			var c = cmd.new(act[1], act[2], act[3])
			var ok: bool = c.execute(gs)
			log.append(["propose", act[1], act[2], act[3], ok, c.result.get("accepted", false), c.result.get("reason", "")])
		"gift":
			var cmd: GDScript = load("res://scripts/sim/gift.gd")
			var ok: bool = cmd.new(act[1], act[2], act[3]).execute(gs)
			log.append(["gift", act[1], act[2], act[3], ok])
		"cancel":
			var cmd: GDScript = load("res://scripts/sim/cancel_treaty.gd")
			var id := _treaty_id(act[1], act[2], act[3])
			var ok: bool = cmd.new(act[1], id).execute(gs)
			log.append(["cancel", act[1], id, ok])
		"rename":
			var cmd: GDScript = load("res://scripts/sim/rename_alliance.gd")
			var ok: bool = cmd.new(act[1], act[2]).execute(gs)
			log.append(["rename", act[1], act[2], ok])
		"days":
			for i in act[1]:
				clock.advance_day()
				var shot: bool = i % act[2] == act[2] - 1 or i == act[1] - 1
				log.append(["day", shot])
				if shot:
					snaps.append(_snapshot())
			return
	snaps.append(_snapshot())
	log.append(["shot"])


func _snapshot() -> Dictionary:
	var nations := []
	for tag in gs.nations:
		var n = gs.nations[tag]
		nations.append([B(n.diplomacy_points), B(n.prestige), B(n.treasury), B(n.points_price)])
	var treaties := []
	for t in gs.treaties:
		treaties.append([t.id, t.kind, t.a, t.b, t.start_day, t.end_day, JSON.stringify(t.terms)])
	var projects := []
	for p in gs.relation_projects:
		projects.append([p.from, p.to, p.months_left])
	return {"day": clock.days_elapsed, "nations": nations, "treaties": treaties, "projects": projects, "relations": _bits_map(gs.relations),
			"base": _bits_map(gs.relation_base), "gifts": _bits_map(gs.gift_memory), "counters": gs.next_treaty_id}


func _make_peace_copy(name: String) -> String:
	var src := "res://data/scenarios/%s/" % name
	var dst := "user://peace_%s/" % name
	DirAccess.make_dir_recursive_absolute(dst)
	for file in DirAccess.get_files_at(src):
		if file.ends_with(".import"):
			continue
		if file == "scenario.json":
			var sc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(src + file))
			sc.erase("starting_wars")
			var out := FileAccess.open(dst + file, FileAccess.WRITE)
			out.store_string(JSON.stringify(sc))
			out.close()
		else:
			DirAccess.copy_absolute(src + file, dst + file)
	return dst
