extends SceneTree
## Plays the scenario with the AI at every controller but the player's and prints, month by
## month, what the war looks like: wars, battles, territory changing hands, armies, treasuries
## and war support, campaigns, and every peace. Used to tune data/ai.json.
## Run: godot --headless --path . -s res://tools/ai_report.gd -- [days] [player] [step] [longwar]
##   days    how long to run (default 400)
##   player  tag of the nation that is meant to be the player (default ESP, a bystander)
##   step    days between reports (default 30)
##   longwar keeps every nation at war willing to fight on (war support held up and no debt
##           collapse), to watch the navy for two years

var gs: Node
var clock: Node
var map: Node
var battles := {}
var battle_days := {}
const GREAT := ["GER", "FRA", "RUS", "AUH", "GBR", "SRB", "BEL", "MNE"]
const NAVAL := ["GBR", "GER", "FRA", "RUS", "AUH", "ITA", "OTT"]
## Sea battles fought so far: zone name -> days of fighting, and ships lost per nation.
var sea_days := {}
var sea_lost := {}
## Armies aboard a fleet yesterday (id -> tag), and the landings seen: "date TAG>province".
var aboard := {}
var landings: Array = []


func _initialize() -> void:
	await process_frame
	gs = root.get_node("GameState")
	clock = root.get_node("Clock")
	map = root.get_node("MapData")
	var args := OS.get_cmdline_user_args()
	var days := int(args[0]) if args.size() > 0 else 400
	var player: String = args[1] if args.size() > 1 else "ESP"
	var step := int(args[2]) if args.size() > 2 else 30
	var longwar := args.size() > 3 and args[3] == "longwar"
	gs.set_player(player)
	gs.war_changed.connect(func(a: String, b: String, at_war: bool) -> void:
		print("[%s] %s %s %s" % [clock.date_string(), a, "declares on" if at_war else "makes peace with", b]))
	gs.battle_fought.connect(func(province: int, tags: Array) -> void:
		var key := "%s %s" % [map.provinces[province].name, "-".join(tags)]
		battles[key] = battles.get(key, 0) + 1)
	gs.sea_battle_fought.connect(func(zone: int, _tags: Array) -> void:
		var zname: String = map.sea_zones[zone].name
		sea_days[zname] = sea_days.get(zname, 0) + 1)
	var A = load("res://scripts/ai/ai.gd")
	A.profile = true
	var t0 := Time.get_ticks_msec()
	for i in days:
		clock.advance_day()
		_watch_navy()
		if longwar:
			_keep_fighting()
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
	_report_navy()
	_report_raiders()
	var fronts := {}
	for f in gs.fronts.values():
		fronts[f.tag] = fronts.get(f.tag, 0) + 1
	var keys := battles.keys()
	keys.sort()
	if gs.wars.size() > 0:
		print("   battle places: %s" % str(keys.slice(0, 14)))


## Per day: remember which armies are aboard, note the ones that have gone ashore, and fold
## finished sea battles' losses into the totals.
func _watch_navy() -> void:
	var now := {}
	for a in gs.armies.values():
		if a.fleet_id > 0:
			now[a.id] = a.tag
		elif aboard.has(a.id):
			landings.append("%s %s>%s" % [clock.date_string(), a.tag, map.provinces[a.province].name])
	aboard = now
	for battle: Dictionary in gs.sea_battle_archive.values():
		if battle.get("counted", false):
			continue
		battle["counted"] = true
		for tag: String in battle.lost:
			var key := "%s/%s" % [battle.name, tag]
			sea_lost[key] = sea_lost.get(key, 0.0) + battle.lost[tag]


func _report_navy() -> void:
	var port := []
	var sea := []
	var carried := 0
	for tag in NAVAL:
		var in_port := 0.0
		var at_sea := 0.0
		for f in gs.fleets.values():
			if f.tag != tag:
				continue
			for s in f.ships:
				if f.port > 0:
					in_port += s.strength
				else:
					at_sea += s.strength
		port.append("%s %d" % [tag, roundi(in_port)])
		sea.append("%s %d" % [tag, roundi(at_sea)])
	for a in gs.armies.values():
		if a.fleet_id > 0:
			carried += 1
	var held := []
	var contested := []
	for zone: int in gs.sea_control:
		var c: Dictionary = gs.sea_control[zone]
		var zname: String = map.sea_zones[zone].name
		if c.contested:
			contested.append(zname)
		else:
			held.append("%s:%s" % [zname, "+".join(c.holders)])
	var cut := []
	for tag in GREAT + ["ITA", "OTT"]:
		if gs.nations.has(tag) and gs.nations[tag].blockade > 0.01:
			cut.append("%s %d%%" % [tag, roundi(gs.nations[tag].blockade * 100.0)])
	print("   ships in port: %s" % ", ".join(port))
	print("   ships at sea:  %s | armies aboard %d" % [", ".join(sea), carried])
	print("   sea held: %s" % ", ".join(held))
	if not contested.is_empty():
		print("   sea contested: %s" % ", ".join(contested))
	print("   blockade: %s" % (", ".join(cut) if not cut.is_empty() else "none"))
	print("   sea battle days: %s" % str(sea_days))
	var lost := {}
	for key: String in sea_lost:
		lost[key] = snappedf(sea_lost[key], 0.1)
	print("   ships lost: %s" % str(lost))
	print("   landings so far: %s" % str(landings))


## Test aid: nations at war keep their war support and their credit, so wars run on.
func _keep_fighting() -> void:
	for tag in gs.nations:
		var n = gs.nations[tag]
		if not gs.wars_of(tag).is_empty():
			n.war_support = maxf(n.war_support, 60.0)
			n.treasury = maxf(n.treasury, 0.0)


## Where each navy's submarine flotillas lie, and who is cutting off whom.
func _report_raiders() -> void:
	var rows := []
	for tag in NAVAL:
		var zones := []
		for f in gs.fleets.values():
			if f.tag == tag and f.mission == "raid":
				zones.append(map.sea_zones[f.zone].name if f.zone > 0 else "port")
		if not zones.is_empty():
			rows.append("%s %s" % [tag, ",".join(zones)])
	print("   raiders: %s" % " | ".join(rows))
	var by := []
	for tag in GREAT + ["ITA", "OTT"]:
		if gs.nations.has(tag) and gs.nations[tag].blockade > 0.01:
			by.append("%s<-%s" % [tag, "+".join(gs.nations[tag].blockade_by)])
	print("   blockaded by: %s" % ", ".join(by))
