extends SceneTree
## Writes what the GDScript peace conferences do, for the Rust port (rust/fs_sim) to reproduce: the July 1914 war with its allies
## called in, ground taken from Germany by Russia and its partners, and the player (Russia or France) proposing a conference with
## demands small and large (taken whole, refused, a counter-offer made, accepted or not), then the days after, in which the AI makes
## its own peace overtures. Floats are the bits of their 64-bit value.
##   godot --headless --path . -s res://tools/dump_conference_golden.gd -- rust/fs_sim/tests/golden/conference.json

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
	var campaigns := [
		{"name": "small_demand", "player": "POR", "actions": [["days", 45], ["seize", "GER", "RUS", 4], ["conf", "RUS", "GER", 2, true], ["days", 40]]},
		{"name": "large_demand", "player": "POR", "actions": [["days", 45], ["seize", "GER", "RUS", 6], ["conf", "RUS", "GER", 6, true], ["answer", true], ["days", 40]]},
		{"name": "counter_declined", "player": "POR", "actions": [["days", 45], ["seize", "GER", "RUS", 6], ["conf", "RUS", "GER", 6, true], ["answer", false], ["conf", "RUS", "GER", 1, false], ["days", 40]]},
		{"name": "alone", "player": "POR", "actions": [["war", "GER", "FRA"], ["days", 30], ["seize", "GER", "FRA", 3], ["conf", "FRA", "GER", 2, false], ["conf", "FRA", "GER", 3, true], ["days", 20], ["answer", true], ["days", 30]]},
		{"name": "white_peace", "player": "POR", "actions": [["days", 100], ["conf", "RUS", "GER", 0, true], ["conf", "RUS", "AUH", 0, false], ["days", 60]]},
		{"name": "player_is_the_enemy", "player": "GER", "actions": [["joins"], ["days", 45], ["seize", "GER", "RUS", 4], ["conf", "RUS", "GER", 3, true], ["days", 60]]},
	]
	var result := []
	for camp in campaigns:
		gs.player_tag = ""
		gs.load_scenario("res://data/scenarios/july_1914/")
		gs.ai_enabled = false
		gs.pressure_ai = false
		gs.set_player(camp.player)
		var log := []
		var snaps := [_snapshot()]
		for act in camp.actions:
			_play(act, log, snaps)
		var answers := {}
		for gid in gs.war_groups:
			var g: Dictionary = gs.war_groups[gid]
			for tag in g.declined:
				answers["%s|%d" % [tag, gid]] = false
			for tag in g.called:
				answers["%s|%d" % [tag, gid]] = true
		result.append({"name": camp.name, "player": camp.player, "log": log, "snaps": snaps, "answers": answers})
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(result))
	f.close()
	print("wrote ", out_path)
	quit(0)


func _border(taker: String, victim: String, n: int) -> Array:
	var Mil: GDScript = load("res://scripts/sim/military.gd")
	var out := []
	for id in range(1, gs.province_owner.size()):
		if gs.province_owner[id] != victim or gs.province_controller[id] != victim:
			continue
		for nb in Mil.neighbors(id):
			if gs.province_owner[nb] == taker:
				out.append(id)
				break
	return out.slice(0, n)


func _play(act: Array, log: Array, snaps: Array) -> void:
	match act[0]:
		"joins":
			var dip: GDScript = load("res://scripts/sim/diplomacy.gd")
			while not gs.pending_joins.is_empty():
				var d: Dictionary = gs.pending_joins[0]
				var ok: bool = dip.answer_join(gs, d.id, true)
				log.append(["join", d.id, ok])
		"war":
			load("res://scripts/sim/diplomacy.gd").start_war(gs, act[1], act[2], true)
			log.append(act)
		"seize":
			# ground of the victim taken by the taker's side: the first provinces of the victim that a taker's army could reach
			var ids := _border(act[2], act[1], act[3])
			for id in ids:
				gs.set_controller(id, act[2])
			load("res://scripts/sim/economy.gd").recompute(gs)
			log.append(["seize", act[2], ids])
		"conf":
			var enemy: String = act[2]
			var tag: String = act[1]
			# the demands: the first n provinces the taker holds of the enemy's
			var held := []
			for id in gs.nations[enemy].provinces:
				if gs.province_controller[id] == tag:
					held.append(id)
			var demands := []
			if act[3] > 0 and not held.is_empty():
				demands.append({"kind": "province", "ids": held.slice(0, act[3])})
			var partners := []
			if act[4]:
				partners = load("res://scripts/sim/conference.gd").partners(gs, tag, enemy)
			var cmd: GDScript = load("res://scripts/sim/propose_conference.gd")
			var c = cmd.new(tag, enemy, demands, partners)
			var ok: bool = c.execute(gs)
			log.append(["conf", tag, enemy, demands, partners, ok, c.result.get("accepted", false) if c.result.get("accepted", false) != null else null, c.result.get("reason", "")])
		"answer":
			var cmd: GDScript = load("res://scripts/sim/answer_conference.gd")
			var ok: bool = cmd.new(act[1]).execute(gs)
			log.append(["answer", act[1], ok])
		"days":
			for i in act[1]:
				clock.advance_day()
				if i % 10 == 9 or i == act[1] - 1:
					log.append(["day", true])
					snaps.append(_snapshot())
				else:
					log.append(["day", false])
			return
	snaps.append(_snapshot())
	log.append(["shot"])


func _snapshot() -> Dictionary:
	var owners := []
	var controllers := []
	for id in range(1, gs.province_owner.size()):
		owners.append(gs.province_owner[id])
		controllers.append(gs.province_controller[id])
	var wars := []
	for w in gs.wars.values():
		wars.append([w.id, w.a, w.b])
	var prestige := {}
	for tag in gs.nations:
		prestige[tag] = B(gs.nations[tag].prestige)
	var counter = gs.conference_counter
	var counter_out = null
	if not counter.is_empty():
		var entries := []
		for e in counter.entries:
			entries.append([e.tag, JSON.stringify(e.demands)])
		counter_out = [counter.from, counter.enemy, entries, counter.day, counter.until_day]
	var cooldown := {}
	for k in gs.peace_cooldown:
		cooldown[k] = gs.peace_cooldown[k]
	return {"day": clock.days_elapsed, "owners": owners, "controllers": controllers, "wars": wars, "history": gs.war_history.size(), "prestige": prestige,
			"relations": _bits_map(gs.relations), "cooldown": cooldown, "counter": counter_out, "pending": gs.pending_offers.size(), "indemnities": gs.indemnities.size(),
			"offer_id": gs.next_offer_id, "members": gs.war_groups.values().map(func(g): return [g.id, g.members.keys()])}
