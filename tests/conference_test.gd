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


## Germany and Austria-Hungary at war with France, in one conflict; each holds some French ground.
func _war(ger_ground := 4, auh_ground := 3) -> void:
	gs.load_scenario("res://data/scenarios/jan_1900/")
	gs.join_calls.clear()
	gs.wars.clear()
	gs.set_player("GER")
	gs.ai_enabled = false
	gs.set_war("GER", "FRA", true, "none")
	var group: int = gs.war_between("GER", "FRA").war_group
	gs.set_war("AUH", "FRA", true, "ally_called", group)
	D._open_group(gs, "GER", "FRA", group)
	D._open_group(gs, "AUH", "FRA", group)
	var fra: Array = gs.nations["FRA"].provinces.duplicate()
	for i in ger_ground:
		gs.province_controller[fra[i]] = "GER"
	for i in auh_ground:
		gs.province_controller[fra[ger_ground + i]] = "AUH"
	gs.nations["GER"].diplomacy_points = 100.0


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
	_check(K.partners(gs, "GER", "FRA") == ["AUH"], "Austria-Hungary sits with Germany against France (%s)" % str(K.partners(gs, "GER", "FRA")))
	_check(K.partners(gs, "AUH", "FRA") == ["GER"], "and Germany with Austria-Hungary")
	_check(K.partners(gs, "ESP", "FRA").is_empty() and K.partners(gs, "GER", "ESP").is_empty(), "nobody else is at the table")
	var terms: Array = K.partner_terms(gs, "AUH", "FRA")
	_check(not terms.is_empty() and terms[0].kind == "province", "Austria-Hungary asks for ground it holds (%s)" % str(terms.slice(0, 1)))
	var own: Array = [{"kind": "province", "ids": _ground("GER").slice(0, 2)}]
	var all: Array = K.entries_for(gs, "GER", "FRA", own, ["AUH"])
	_check(all.size() == 2 and all[0].tag == "GER" and all[1].tag == "AUH", "the package has Germany's terms and Austria-Hungary's")
	_check(K.entries_for(gs, "GER", "FRA", own, []).size() == 1, "a partner left out is not in it")
	_check(K.chairman(gs, all, "FRA") in ["GER", "AUH"], "someone chairs (%s)" % K.chairman(gs, all, "FRA"))

	# --- A package the enemy must take ---------------------------------------------------------
	gs.nations["FRA"].war_support = 0.0
	var prestige: float = gs.nations["GER"].prestige
	var chair: String = K.chairman(gs, all, "FRA")
	var chair_prestige: float = gs.nations[chair].prestige
	var ger_province: int = own[0].ids[0]
	_check(gs.issue(Propose.new("GER", "FRA", own, ["AUH"])), "Germany proposes a joint peace")
	_check(gs.war_between("GER", "FRA") == null and gs.war_between("AUH", "FRA") == null, "France takes it: both wars are over")
	_check(gs.province_owner[ger_province] == "GER", "Germany has its province")
	_check(gs.nations[chair].prestige > chair_prestige, "the chairman gains standing (%s: %.2f to %.2f)" % [chair, chair_prestige, gs.nations[chair].prestige])
	_check(gs.history_log.any(func(e: Dictionary) -> bool: return e.text.contains("chaired")), "and the conference is written into the history")

	# --- A refusal and a counter-offer ----------------------------------------------------------
	_war(6, 6)
	gs.nations["FRA"].war_support = 35.0
	var big: Array = [{"kind": "province", "ids": _ground("GER")}]
	var entries: Array = K.entries_for(gs, "GER", "FRA", big, ["AUH"])
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
	var strict: Array = [{"tag": "GER", "demands": [{"kind": "province", "ids": _ground("GER")}]}, {"tag": "AUH", "demands": [{"kind": "indemnity", "share": 0.5, "months": 60}]}]
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
	var cmd = Propose.new("GER", "FRA", greedy, ["AUH"])
	var ok: bool = gs.issue(cmd)
	_check(ok and cmd.result.has("accepted"), "a greedy joint proposal is made and answered")
	if cmd.result.accepted == false and not gs.conference_counter.is_empty():
		_check(gs.conference_counter.from == "GER" and gs.conference_counter.enemy == "FRA", "a counter-offer waits for the player")
		var made: bool = gs.issue(Answer.new(true))
		_check(made and gs.conference_counter.is_empty() and gs.war_between("GER", "FRA") == null, "accepting it makes the peace")
	else:
		_check(true, "(no counter-offer in this position)")
	_war()
	gs.conference_counter = {"from": "GER", "enemy": "FRA", "entries": K.entries_for(gs, "GER", "FRA", [], ["AUH"]), "day": 0}
	_check(gs.issue(Answer.new(false)) and gs.conference_counter.is_empty() and gs.war_between("GER", "FRA") != null, "refusing a counter-offer ends it and the war goes on")
	_check(not gs.issue(Answer.new(true)), "with none waiting there is nothing to answer")

	# --- Invalid packages -------------------------------------------------------------------
	_war()
	var bad: Array = [{"kind": "province", "ids": [gs.nations["BEL"].provinces[0]]}]
	var r: Dictionary = K.propose(gs, "GER", "FRA", bad, ["AUH"])
	_check(not r.ok and r.reason == "invalid", "terms that cannot be made refuse the whole package")
	_check(K.propose(gs, "GER", "ESP", [], []).reason == "no_war", "no war, no conference")

	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)
