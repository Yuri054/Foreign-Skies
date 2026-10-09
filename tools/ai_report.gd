extends SceneTree
## Plays the scenario with the AI at every controller but the player's and prints, month by
## month, what the war looks like: wars, battles, territory changing hands, armies, treasuries
## and war support, campaigns, and every peace. Used to tune data/ai.json.
## Run: godot --headless --path . -s res://tools/ai_report.gd -- [days] [player] [step]
##   days    how long to run (default 400)
##   player  tag of the nation that is meant to be the player (default ESP, a bystander)
##   step    days between reports (default 30)

var gs: Node
var clock: Node
var map: Node
var battles := {}
var battle_days := {}
const GREAT := ["GER", "FRA", "RUS", "AUH", "GBR", "SRB", "BEL", "MNE"]


func _initialize() -> void:
	await process_frame
	gs = root.get_node("GameState")
	clock = root.get_node("Clock")
	map = root.get_node("MapData")
	var args := OS.get_cmdline_user_args()
	var days := int(args[0]) if args.size() > 0 else 400
	var player: String = args[1] if args.size() > 1 else "ESP"
	var step := int(args[2]) if args.size() > 2 else 30
	gs.set_player(player)
	gs.war_changed.connect(func(a: String, b: String, at_war: bool) -> void:
		print("[%s] %s %s %s" % [clock.date_string(), a, "declares on" if at_war else "makes peace with", b]))
	gs.battle_fought.connect(func(province: int, tags: Array) -> void:
		var key := "%s %s" % [map.provinces[province].name, "-".join(tags)]
		battles[key] = battles.get(key, 0) + 1)
	var A = load("res://scripts/ai/ai.gd")
	A.profile = true
	var t0 := Time.get_ticks_msec()
	for i in days:
		clock.advance_day()
		if gs.has_pending():
			gs.pending_joins.clear()
			gs.pending_offers.clear()
		if (i + 1) % step == 0:
			_report()
	for part in A.timings:
		print("  AI %s: %.1f ms a day" % [part, A.timings[part] / 1000.0 / days])
	print("Ran %d days in %d ms (%.1f ms a day)" % [days, Time.get_ticks_msec() - t0, float(Time.get_ticks_msec() - t0) / days])
	quit()


func _report() -> void:
	var held := {}
	for id in range(1, gs.province_owner.size()):
		if gs.province_owner[id] != gs.province_controller[id]:
			var key := "%s>%s" % [gs.province_owner[id], gs.province_controller[id]]
			held[key] = held.get(key, 0) + 1
	var men := []
	var money := []
	var support := []
	for tag in GREAT:
		var total := 0.0
		for a in gs.armies.values():
			if a.tag == tag:
				total += a.men()
		men.append("%s %dk" % [tag, roundi(total / 1000.0)])
		money.append("%s %d" % [tag, roundi(gs.nations[tag].treasury)])
		support.append("%s %d" % [tag, roundi(gs.nations[tag].war_support)])
	print("== %s | wars %d | battles %d places | held across lines %s" % [clock.date_string(), gs.wars.size(), battles.size(), str(held)])
	print("   men: %s" % ", ".join(men))
	print("   treasury: %s" % ", ".join(money))
	print("   war support: %s" % ", ".join(support))
	print("   campaigns: %s" % str(gs.ai_campaign.keys()))
	var fronts := {}
	for f in gs.fronts.values():
		fronts[f.tag] = fronts.get(f.tag, 0) + 1
	var keys := battles.keys()
	keys.sort()
	if gs.wars.size() > 0:
		print("   battle places: %s" % str(keys.slice(0, 14)))
