extends SceneTree
## Headless test for peace conferences: who sits at the table, what each partner asks, the package taken or refused whole,
## the counter-offer, the chairman, and the answer to a counter-offer.
## Run: godot --headless --path . -s res://tests/conference_test.gd

var _failures := 0
var gs: Node
var K
var P
var D


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", msg)
	else:
		print("ok:   ", msg)


## Germany and Italy at war with France, in one conflict; each holds some French ground on its own border.
func _war(ger_ground := 4, ita_ground := 3) -> void:
	gs.load_scenario("res://data/scenarios/jan_1900/")
	gs.join_calls.clear()
	gs.wars.clear()
	gs.set_player("GER")
	gs.ai_enabled = false
	gs.set_war("GER", "FRA", true, "none")
	var group: int = gs.war_between("GER", "FRA").war_group
	gs.set_war("ITA", "FRA", true, "ally_called", group)
	D._open_group(gs, "GER", "FRA", group)
	D._open_group(gs, "ITA", "FRA", group)
	_hold("GER", ger_ground)
	_hold("ITA", ita_ground)
	gs.nations["GER"].diplomacy_points = 100.0


## `tag` takes `count` French provinces, from its border inward (never the capital).
func _hold(tag: String, count: int) -> void:
	var Mil = load("res://scripts/sim/military.gd")
	var queue: Array = []
	for id: int in gs.nations["FRA"].provinces:
		for n: int in Mil.neighbors(id):
			if gs.province_owner[n] == tag:
				queue.append(id)
				break
	var taken := 0
	var seen := {}
	while not queue.is_empty() and taken < count:
		var p: int = queue.pop_front()
		if seen.has(p):
			continue
		seen[p] = true
		if gs.province_controller[p] != "FRA" or p == gs.nations["FRA"].capital:
			continue
		gs.province_controller[p] = tag
		taken += 1
		for n: int in Mil.neighbors(p):
			if gs.province_owner[n] == "FRA" and not seen.has(n):
				queue.append(n)


func _ground(tag: String) -> Array:
	var out: Array = []
	for id: int in gs.nations["FRA"].provinces:
		if gs.province_controller[id] == tag:
			out.append(id)
	return out


func _initialize() -> void:
	await process_frame
	gs = root.get_node("GameState")
	K = load("res://scripts/sim/conference.gd")
	P = load("res://scripts/sim/peace.gd")
	D = load("res://scripts/sim/diplomacy.gd")
	var AP = load("res://scripts/ai/ai_peace.gd")
	var Propose = load("res://scripts/sim/propose_conference.gd")
	var Answer = load("res://scripts/sim/answer_conference.gd")

	# --- The table ----------------------------------------------------------------------------
	_war()
	_check(K.partners(gs, "GER", "FRA") == ["ITA"], "Italy sits with Germany against France (%s)" % str(K.partners(gs, "GER", "FRA")))
	_check(K.partners(gs, "ITA", "FRA") == ["GER"], "and Germany with Italy")
	_check(K.partners(gs, "ESP", "FRA").is_empty() and K.partners(gs, "GER", "ESP").is_empty(), "nobody else is at the table")
	var terms: Array = K.partner_terms(gs, "ITA", "FRA")
	_check(not terms.is_empty() and terms[0].kind == "province", "Italy asks for ground it holds (%s)" % str(terms.slice(0, 1)))
	var own: Array = [{"kind": "province", "ids": _ground("GER").slice(0, 2)}]
	var all: Array = K.entries_for(gs, "GER", "FRA", own, ["ITA"])
	_check(all.size() == 2 and all[0].tag == "GER" and all[1].tag == "ITA", "the package has Germany's terms and Italy's")
	_check(K.entries_for(gs, "GER", "FRA", own, []).size() == 1, "a partner left out is not in it")
	_check(K.chairman(gs, all, "FRA") in ["GER", "ITA"], "someone chairs (%s)" % K.chairman(gs, all, "FRA"))

	# --- A package the enemy must take ---------------------------------------------------------
	gs.nations["FRA"].war_support = 0.0
	var prestige: float = gs.nations["GER"].prestige
	var chair: String = K.chairman(gs, all, "FRA")
	var chair_prestige: float = gs.nations[chair].prestige
	var ger_province: int = own[0].ids[0]
	_check(gs.issue(Propose.new("GER", "FRA", own, ["ITA"])), "Germany proposes a joint peace")
	_check(gs.war_between("GER", "FRA") == null and gs.war_between("ITA", "FRA") == null, "France takes it: both wars are over")
	_check(gs.province_owner[ger_province] == "GER", "Germany has its province")
	_check(gs.nations[chair].prestige > chair_prestige, "the chairman gains standing (%s: %.2f to %.2f)" % [chair, chair_prestige, gs.nations[chair].prestige])
	_check(gs.history_log.any(func(e: Dictionary) -> bool: return e.text.contains("chaired")), "and the conference is written into the history")

	# --- A refusal and a counter-offer ----------------------------------------------------------
	_war(6, 6)
	gs.nations["FRA"].war_support = 35.0
	var big: Array = [{"kind": "province", "ids": _ground("GER")}]
	var entries: Array = K.entries_for(gs, "GER", "FRA", big, ["ITA"])
	var cost0 := 0.0
	for e: Dictionary in entries:
		cost0 += P.check(gs, e.tag, "FRA", "demand", e.demands).cost
	var took: bool = K.acceptable(gs, entries, "FRA")
	if not took:
		var counter: Dictionary = K.counter(gs, entries, "FRA")
		if counter.is_empty():
			_check(true, "(France would take nothing less: no counter-offer)")
		else:
			var cost1 := 0.0
			for e: Dictionary in counter.entries:
				cost1 += P.check(gs, e.tag, "FRA", "demand", e.demands).cost
			_check(cost1 < cost0 and K.acceptable(gs, counter.entries, "FRA"), "the counter-offer is smaller (%.1f against %.1f) and France would take it" % [cost1, cost0])
	else:
		_check(true, "(France took the big package)")
	var strict: Array = [{"tag": "GER", "demands": [{"kind": "province", "ids": _ground("GER")}]}, {"tag": "ITA", "demands": [{"kind": "indemnity", "share": 0.5, "months": 60}]}]
	var trimmed: Dictionary = K.counter(gs, strict, "FRA")
	if not trimmed.is_empty():
		var n0 := 0
		for e: Dictionary in strict:
			n0 += e.demands.size()
		var n1 := 0
		for e: Dictionary in trimmed.entries:
			n1 += e.demands.size()
		_check(n1 <= n0, "striking demands never adds any")

	# A player proposal that is refused leaves the counter for the player to answer.
	_war(5, 5)
	gs.nations["FRA"].war_support = 45.0
	var greedy: Array = [{"kind": "province", "ids": _ground("GER")}]
	var cmd = Propose.new("GER", "FRA", greedy, ["ITA"])
	var ok: bool = gs.issue(cmd)
	_check(ok and cmd.result.has("accepted"), "a greedy joint proposal is made and answered")
	if cmd.result.accepted == false and not gs.conference_counter.is_empty():
		_check(gs.conference_counter.from == "GER" and gs.conference_counter.enemy == "FRA", "a counter-offer waits for the player")
		var made: bool = gs.issue(Answer.new(true))
		_check(made and gs.conference_counter.is_empty() and gs.war_between("GER", "FRA") == null, "accepting it makes the peace")
	else:
		_check(true, "(no counter-offer in this position)")
	_war()
	gs.conference_counter = {"from": "GER", "enemy": "FRA", "entries": K.entries_for(gs, "GER", "FRA", [], ["ITA"]), "day": 0}
	_check(gs.issue(Answer.new(false)) and gs.conference_counter.is_empty() and gs.war_between("GER", "FRA") != null, "refusing a counter-offer ends it and the war goes on")
	_check(not gs.issue(Answer.new(true)), "with none waiting there is nothing to answer")

	# A counter-offer does not wait for ever, and the enemy is asked again when it is taken.
	_war(5, 5)
	var small: Array = K.entries_for(gs, "GER", "FRA", [], ["ITA"])
	var clock = root.get_node("Clock")
	gs.conference_counter = {"from": "GER", "enemy": "FRA", "entries": small, "day": clock.days_elapsed, "until_day": clock.days_elapsed + int(P.cfg().counter_days)}
	_check(not K.waiting_counter(gs).is_empty(), "a fresh counter-offer waits")
	clock.days_elapsed += int(P.cfg().counter_days) + 1
	_check(K.waiting_counter(gs).is_empty() and gs.conference_counter.is_empty(), "and lapses after %d days" % int(P.cfg().counter_days))
	_check(not gs.issue(Answer.new(true)) and gs.war_between("GER", "FRA") != null, "a lapsed counter-offer cannot be taken")
	var dear_counter: Array = [{"tag": "GER", "demands": [{"kind": "indemnity", "share": 0.5, "months": 60}]}]
	gs.nations["FRA"].war_support = 80.0
	gs.conference_counter = {"from": "GER", "enemy": "FRA", "entries": dear_counter, "day": clock.days_elapsed, "until_day": clock.days_elapsed + 30}
	_check(not gs.issue(Answer.new(true)) and gs.war_between("GER", "FRA") != null, "one the enemy would no longer take is put to it again and fails")

	# The package is weighed whole: what each partner asks may be bearable alone and too much together.
	_war(6, 6)
	gs.nations["FRA"].war_support = 30.0
	var parts: Array = [{"tag": "GER", "demands": K.partner_terms(gs, "GER", "FRA")}, {"tag": "ITA", "demands": K.partner_terms(gs, "ITA", "FRA")}]
	var each := true
	var sum := 0.0
	for e: Dictionary in parts:
		var o: Dictionary = K.offer_of(gs, e, "FRA")
		each = each and not o.is_empty() and AP.accepts(gs, o)
		sum += float(o.get("cost", 0.0))
	var most := maxf(AP.urge(gs, "FRA", gs.war_between("GER", "FRA")), AP.urge(gs, "FRA", gs.war_between("ITA", "FRA")))
	if each and sum > most:
		_check(not K.acceptable(gs, parts, "FRA"), "terms France would take one by one are refused together (%.1f against its wish for peace %.1f)" % [sum, most])
	else:
		_check(K.acceptable(gs, parts, "FRA") == (each and sum <= most), "the package is taken only if France would take it whole")

	# --- Invalid packages -------------------------------------------------------------------
	_war()
	var bad: Array = [{"kind": "province", "ids": [gs.nations["BEL"].provinces[0]]}]
	var r: Dictionary = K.propose(gs, "GER", "FRA", bad, ["ITA"])
	_check(not r.ok and r.reason == "invalid", "terms that cannot be made refuse the whole package")
	_check(K.propose(gs, "GER", "ESP", [], []).reason == "no_war", "no war, no conference")

	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)
