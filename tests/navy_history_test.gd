extends SceneTree
## Headless test of the 1914 war at sea played by the AI alone: the markers that make it look
## like the war it models (a British blockade that bites, the High Seas Fleet mostly in harbour,
## the Mediterranean contested, the Baltic quiet, a few landings and none that wins the war),
## determinism, and the daily cost of the navy.
## Run: godot --headless --path . -s res://tests/navy_history_test.gd
## The nations at war keep their war support and their credit (as in tools/ai_report.gd
## "longwar"), because the land war ends in the spring of 1915 and the navy needs longer.
## Class names are loaded at runtime because this script compiles before the autoloads exist.

const MEDITERRANEAN := ["Tyrrhenian Sea", "Ionian Sea", "Southern Adriatic", "Northern Adriatic", "Aegean Sea",
		"Eastern Mediterranean", "Ligurian Sea", "Sicilian Channel", "Balearic Sea", "Algerian Basin", "Alboran Sea"]
const QUIET := ["Southern Baltic", "Central Baltic", "Western Black Sea"]

var _failures := 0
var gs: Node
var clock: Node
var map: Node
var A


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
	map = root.get_node("MapData")
	A = load("res://scripts/ai/ai.gd")
	_test_history()
	_test_determinism()
	_test_cost()
	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)


func _start() -> void:
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	gs.ai_enabled = true
	gs.set_player("ESP")


func _day() -> void:
	clock.advance_day()
	if gs.has_pending():
		gs.pending_joins.clear()
		gs.pending_offers.clear()
	for tag in gs.nations:
		var n = gs.nations[tag]
		if not gs.wars_of(tag).is_empty():
			n.war_support = maxf(n.war_support, 60.0)
			n.treasury = maxf(n.treasury, 0.0)


## Ship strength of a nation in port and at sea.
func _ships(tag: String) -> Dictionary:
	var out := {"port": 0.0, "sea": 0.0}
	for f in gs.fleets.values():
		if f.tag != tag:
			continue
		for s in f.ships:
			out["port" if f.port > 0 else "sea"] += s.strength
	return out


func _test_history() -> void:
	_start()
	var collapsed: Array = []
	var days_at := {}
	gs.nation_collapsed.connect(func(tag: String, _men: int) -> void: collapsed.append(tag))
	gs.sea_battle_fought.connect(func(zone: int, _tags: Array) -> void:
		var zname: String = map.sea_zones[zone].name
		days_at[zname] = days_at.get(zname, 0) + 1)
	var aboard := {}
	var landings := 0
	var german_port := 0.0
	var german_seen := 0.0
	var blockade_by_day := {}
	var britain_worst := 0.0
	for day in 400:
		_day()
		var now := {}
		for a in gs.armies.values():
			if a.fleet_id > 0:
				now[a.id] = true
			elif aboard.has(a.id):
				landings += 1
		aboard = now
		if day >= 60 and day % 10 == 0:
			var ships := _ships("GER")
			german_port += ships.port
			german_seen += ships.port + ships.sea
		britain_worst = maxf(britain_worst, gs.nations["GBR"].blockade)
		if day == 120 or day == 240 or day == 399:
			blockade_by_day[day] = gs.nations["GER"].blockade
	_check(gs.at_war("GBR", "GER"), "Britain and Germany are still at war after 400 days")
	_check(blockade_by_day[120] > 0.15, "the British blockade bites within months (%.2f at day 120)" % blockade_by_day[120])
	_check(blockade_by_day[240] > 0.3 and blockade_by_day[399] > 0.3, "and holds (%.2f at day 240, %.2f at day 399)" % [blockade_by_day[240], blockade_by_day[399]])
	_check(gs.nations["GER"].blockade > britain_worst, "Germany is cut off harder than Britain ever is (%.2f against %.2f)" % [gs.nations["GER"].blockade, britain_worst])
	var share := german_port / maxf(german_seen, 1.0)
	_check(share > 0.7, "the High Seas Fleet is mostly in harbour (%d%% of German ship strength in port)" % roundi(share * 100.0))
	var med := 0
	for z in MEDITERRANEAN:
		med += days_at.get(z, 0)
	_check(med >= 3, "the Mediterranean is contested (%d days of fighting)" % med)
	for z in QUIET:
		_check(days_at.get(z, 0) <= 12, "the %s stays near stalemate (%d days of fighting)" % [z, days_at.get(z, 0)])
	var total := 0
	for z in days_at:
		total += days_at[z]
	_check(total >= 10, "there is real fighting at sea (%d days of battle)" % total)
	_check(landings >= 1 and landings <= 8, "there are a few landings and not a flood (%d)" % landings)
	_check(collapsed.is_empty(), "no landing, blockade or defeat ends a nation in 400 days (%s)" % str(collapsed))
	for tag in ["GER", "GBR", "FRA", "RUS", "AUH"]:
		var home: int = 0
		for p in range(1, map.provinces.size()):
			if map.provinces[p].owner == tag:
				home += 1
		_check(gs.nations[tag].provinces.size() >= 0.8 * home, "%s still holds four fifths of its land" % tag)
	var strength := {}
	for tag in ["GBR", "GER"]:
		var ships := _ships(tag)
		strength[tag] = ships.port + ships.sea
	_check(strength["GBR"] > 20.0 and strength["GER"] > 10.0, "neither navy has been swept from the sea (GBR %.0f, GER %.0f)" % [strength["GBR"], strength["GER"]])


func _fingerprint(days: int) -> String:
	_start()
	for i in days:
		_day()
	var places := []
	for f in gs.fleets.values():
		places.append("%d:%d:%d:%d" % [f.id, f.zone, f.port, f.ships.size()])
	return "%s|%s|%s" % [JSON.stringify(gs.command_log), ",".join(places), ",".join(gs.province_controller)]


func _test_determinism() -> void:
	var first := _fingerprint(120)
	var second := _fingerprint(120)
	_check(first == second and first.length() > 1000, "the same war run twice gives the same orders and the same fleets after 120 days")


## The navy's share of a busy war's day: the naval AI and the landings it plans.
func _test_cost() -> void:
	_start()
	for i in 60:
		_day()
	A.profile = true
	A.timings.clear()
	var days := 100
	for i in days:
		_day()
	var navy_ms := float(int(A.timings.get("navy", 0)) + int(A.timings.get("landing", 0))) / 1000.0 / days
	A.profile = false
	print("      (the naval AI costs %.1f ms a day)" % navy_ms)
	_check(OS.get_environment("SPEED_TESTS") == "0" or navy_ms < 10.0, "the naval AI costs under 10 ms a day with the fleets out")
