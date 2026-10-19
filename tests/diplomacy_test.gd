extends SceneTree
## Headless test for the diplomacy foundations: the scenario's treaty web, blocs, relations,
## treaty queries, and adding and ending treaties.
## Run: godot --headless --path . -s res://tests/diplomacy_test.gd
## Class names are loaded at runtime because this script compiles before the autoloads exist.

var _failures := 0
var gs: Node
var D
var Mil
var DeclareC
var CancelC
var AnswerJoinC
var ProposeTreatyC
var GiftC
var BuyC
var ImproveC
var ProgramC
var Eco
var clock: Node


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", msg)
	else:
		print("ok:   ", msg)


func _initialize() -> void:
	await process_frame
	gs = root.get_node("GameState")
	gs.ai_enabled = false  # these tests are about other systems; the AI has its own
	clock = root.get_node("Clock")
	D = load("res://scripts/sim/diplomacy.gd")
	Mil = load("res://scripts/sim/military.gd")
	DeclareC = load("res://scripts/sim/declare_war.gd")
	CancelC = load("res://scripts/sim/cancel_treaty.gd")
	AnswerJoinC = load("res://scripts/sim/answer_join.gd")
	ProposeTreatyC = load("res://scripts/sim/propose_treaty.gd")
	GiftC = load("res://scripts/sim/gift.gd")
	BuyC = load("res://scripts/sim/buy_points.gd")
	ImproveC = load("res://scripts/sim/improve_relations.gd")
	ProgramC = load("res://scripts/sim/set_program.gd")
	Eco = load("res://scripts/sim/economy.gd")

	_test_blocs()
	_test_treaties()
	_test_start_war()
	_test_relations()
	_test_edit()
	_test_reload()
	_test_declare()
	_test_unprovoked()
	_test_passage()
	_test_joins()
	_test_player_join()
	_test_crisis()
	_test_points()
	_test_income_sources()
	_test_buying()
	_test_improving()
	_test_player_crisis()

	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)


func _test_blocs() -> void:
	_check(D.bloc_of(gs, "FRA") == "Entente" and D.bloc_of(gs, "GER") == "Central Powers", "blocs are read from the scenario")
	_check(D.bloc_of(gs, "ITA") == "", "Italy is in no bloc")
	_check("ITA" not in D.bloc_members(gs, "Central Powers"), "Italy is not a Central Power")


func _test_treaties() -> void:
	_check(D.are_allied(gs, "FRA", "RUS") and D.are_allied(gs, "RUS", "FRA"), "France and Russia are allied, both ways round")
	_check(D.are_allied(gs, "GER", "AUH"), "Germany and Austria-Hungary are allied")
	_check(not D.are_allied(gs, "FRA", "GER"), "France and Germany are not allied")
	var ita = D.find_treaty(gs, "alliance", "ITA", "GER")
	_check(ita != null and ita.terms.get("defensive_only", false), "Italy's tie to Germany binds defensively only")
	_check(D.has_treaty(gs, "neutral_pact", "ITA", "AUH"), "Italy has the neutrality clause with Austria-Hungary")
	var entente = D.find_treaty(gs, "alliance", "GBR", "FRA")
	_check(entente != null and entente.terms.get("entente", false), "the Entente Cordiale is an entente, not a binding alliance")
	_check(D.guarantors_of(gs, "BEL").size() == 3 and "GBR" in D.guarantors_of(gs, "BEL"), "Belgium is guaranteed by Britain, Germany and France")
	_check(D.guaranteed_by(gs, "GBR") == ["BEL"], "Britain guarantees Belgium")
	_check(D.has_treaty(gs, "guarantee", "GBR", "BEL") and not D.has_treaty(gs, "guarantee", "BEL", "GBR"), "guarantees run one way")
	_check(D.has_passage(gs, "FRA", "RUS"), "allies may cross each other's land")
	_check(D.has_passage(gs, "GBR", "FRA") and D.has_passage(gs, "FRA", "GBR"), "so may entente partners")
	_check(not D.has_passage(gs, "BEL", "GER"), "Germany has no right to cross Belgium")
	_check(D.treaties_of(gs, "BEL", "guarantee").size() == 3, "treaties_of filters by kind")
	for t: Object in gs.treaties:
		_check(gs.nations.has(t.a) and gs.nations.has(t.b), "treaty %d names real nations" % t.id)


func _test_relations() -> void:
	var tags: Array = gs.nations.keys()
	var pairs: int = tags.size() * (tags.size() - 1) / 2
	_check(gs.relations.size() == pairs, "every pair of %d nations has a relation (%d)" % [tags.size(), pairs])
	_check(D.relation(gs, "AUH", "SRB") == -80.0, "a scenario relations entry overrides the baseline")
	_check(D.relation(gs, "FRA", "RUS") > D.relation(gs, "FRA", "AUH"), "France likes its ally more than Austria-Hungary")
	_check(D.relation(gs, "FRA", "RUS") == D.relation(gs, "RUS", "FRA"), "relations are symmetric")
	_check(D.relation(gs, "FRA", "FRA") == 100.0, "a nation's opinion of itself is the maximum")
	for v: float in gs.relations.values():
		if v < -100.0 or v > 100.0:
			_check(false, "relation out of range: %s" % v)
	D.set_relation(gs, "FRA", "SUI", 500.0)
	_check(D.relation(gs, "FRA", "SUI") == 100.0, "relations clamp at the maximum")
	var base: float = gs.relation_base[D.pair_key("FRA", "SUI")]
	var seen := [0]
	gs.relations_changed.connect(func(_a: String, _b: String) -> void: seen[0] += 1)
	D.step_month(gs)
	_check(D.relation(gs, "FRA", "SUI") == 99.0 and seen[0] >= 1, "opinion drifts a step toward its baseline each month")
	for i in 200:
		D.step_month(gs)
	_check(is_equal_approx(D.relation(gs, "FRA", "SUI"), base), "and settles on it (%s)" % base)


func _test_start_war() -> void:
	_check(gs.at_war("AUH", "SRB"), "Austria-Hungary is already at war with Serbia")
	_check(gs.wars.size() == 1, "and it is the only war")


func _test_edit() -> void:
	var events := []
	gs.treaty_changed.connect(func(t: Object, added: bool) -> void: events.append([t.kind, added]))
	var base_before: float = gs.relation_base[D.pair_key("ESP", "POR")]
	var t = D.add_treaty(gs, "nap", "ESP", "POR")
	_check(t != null and D.has_treaty(gs, "nap", "POR", "ESP"), "a non-aggression pact is signed and is mutual")
	_check(D.add_treaty(gs, "nap", "POR", "ESP") == null, "a second pact between the same pair is refused")
	_check(gs.relation_base[D.pair_key("ESP", "POR")] == base_before + D.cfg.treaties.nap.relation_bonus, "signing raises the baseline")
	var p = D.add_treaty(gs, "passage", "ESP", "FRA")
	_check(D.has_passage(gs, "ESP", "FRA") and not D.has_passage(gs, "FRA", "ESP"), "passage rights run one way")
	D.end_treaty(gs, t)
	_check(not D.has_treaty(gs, "nap", "ESP", "POR"), "an ended treaty no longer counts")
	_check(gs.relation_base[D.pair_key("ESP", "POR")] == base_before, "and takes its bonus back")
	_check(t in gs.treaties, "but it stays on record")
	_check(events == [["nap", true], ["passage", true], ["nap", false]], "treaty_changed fires for each change (%s)" % str(events))
	var future = D.add_treaty(gs, "nap", "DEN", "NED", clock.days_elapsed + 10)
	_check(D.has_treaty(gs, "nap", "DEN", "NED"), "a treaty with an end date stands until then")
	for i in 11:
		clock.advance_day()
	_check(not D.has_treaty(gs, "nap", "DEN", "NED"), "and lapses on that day")
	_check(p != null and future != null, "treaties were created")


func _test_reload() -> void:
	var count: int = gs.treaties.size()
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	_check(gs.treaties.size() < count + 1 and D.has_treaty(gs, "alliance", "FRA", "RUS"), "reloading the scenario restores the starting web")
	_check(not D.has_treaty(gs, "nap", "ESP", "POR"), "and drops treaties signed in play")
	_check(gs.at_war("AUH", "SRB") and gs.wars.size() == 1, "and the starting war")


func _fresh() -> void:
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	gs.wars.clear()
	gs.join_calls.clear()  # the scenario starts a crisis; these tests want a quiet world
	gs.scenario["war_plans"] = []
	gs.set_player("ESP")


## Declares with the aggressor mobilized enough for a war without a casus belli.
func _declare(a: String, b: String, cb: String) -> bool:
	if cb == "none":
		gs.nations[a].mobilization = 0.5
	return gs.issue(DeclareC.new(a, b, cb))


## Runs days until every called nation has mobilized and joined (or 80 days pass).
func _settle() -> void:
	for i in 80:
		if gs.join_calls.is_empty():
			return
		clock.advance_day()


func _test_declare() -> void:
	_fresh()
	var opts: Array = D.casus_belli_options(gs, "FRA", "GER")
	_check("reconquest" in opts and opts.back() == "none", "France can claim Alsace-Lorraine back (%s)" % str(opts))
	_check(D.casus_belli_options(gs, "FRA", "ESP") == ["none"], "France has no justification against Spain")
	_check("border_claim" in D.casus_belli_options(gs, "ITA", "AUH"), "Italy has a border claim on Austria-Hungary")
	_check("border_claim" not in D.casus_belli_options(gs, "ITA", "GER"), "but none on Germany")
	_check(D.declare_block(gs, "FRA", "RUS") == "allied", "France cannot declare on its ally")
	_check(D.declare_block(gs, "FRA", "GBR") == "allied", "nor on the Entente partner")
	_check(D.declare_block(gs, "FRA", "FRA") == "same" and D.declare_block(gs, "FRA", "XXX") == "unknown", "nor on itself or a stranger")

	var rel_before: float = D.relation(gs, "FRA", "GER")
	var world_before: float = D.relation(gs, "FRA", "ESP")
	var prestige_before: float = gs.nations["FRA"].prestige
	_check(not gs.issue(DeclareC.new("FRA", "ESP", "reconquest")), "a casus belli France does not hold is refused")
	_check(not gs.at_war("FRA", "ESP") and gs.command_log.is_empty(), "and changes nothing")
	_check(gs.issue(DeclareC.new("FRA", "GER", "reconquest")), "France declares on Germany to reconquer Alsace-Lorraine")
	var war = gs.war_between("FRA", "GER")
	_check(war != null and war.casus_belli == "reconquest" and war.war_group > 0, "the war records its casus belli and group")
	_check(war.log[0].text.contains("reconquest"), "and the log says why (%s)" % war.log[0].text)
	_check(D.relation(gs, "FRA", "GER") == rel_before - 30.0, "the target's opinion drops by the casus belli's price")
	_check(D.relation(gs, "FRA", "ESP") == world_before and gs.nations["FRA"].prestige == prestige_before, "a justified war costs the rest of the world nothing")
	_check(gs.casus_belli.is_empty(), "and earns no one a casus belli")
	_check(not gs.issue(DeclareC.new("FRA", "GER", "reconquest")) and not _declare("GER", "FRA", "none"), "a second declaration on the same pair is refused")
	_check(gs.command_log.size() == 1 and gs.command_log[0].type == "DeclareWar" and gs.command_log[0].casus_belli == "reconquest", "the declaration is in the command log")

	# A non-aggression pact blocks a declaration until it is cancelled, at a price.
	_fresh()
	var nap = D.add_treaty(gs, "nap", "ESP", "POR")
	_check(D.declare_block(gs, "ESP", "POR") == "nap" and not gs.issue(DeclareC.new("ESP", "POR", "none")), "a non-aggression pact blocks a declaration")
	var world: float = D.relation(gs, "ESP", "ITA")
	_check(not gs.issue(CancelC.new("FRA", nap.id)), "an outsider cannot cancel it")
	_check(gs.issue(CancelC.new("ESP", nap.id)), "a party can")
	_check(D.relation(gs, "ESP", "ITA") == world - 15.0 and gs.nations["ESP"].prestige == -10.0, "breaking it costs everyone's opinion and prestige")
	_check(D.declare_block(gs, "ESP", "POR") == "", "and then war may be declared")


func _test_unprovoked() -> void:
	_fresh()
	var prestige: float = gs.nations["GER"].prestige
	var world: float = D.relation(gs, "GER", "ITA")
	_check(_declare("GER", "BEL", "none"), "a war with no casus belli is allowed once mobilized")
	_check(D.relation(gs, "GER", "ITA") == world - 20.0 and gs.nations["GER"].prestige == prestige - 15.0, "but costs world opinion and prestige")
	var fra: Array = D.casus_belli_options(gs, "FRA", "GER")
	_check("unprovoked_aggression" in fra, "a neighbour gets a casus belli against the aggressor (%s)" % str(fra))
	_check("unprovoked_aggression" in D.casus_belli_options(gs, "GBR", "GER"), "so does a guarantor of the victim")
	_check("guarantee_defence" in D.casus_belli_options(gs, "GBR", "GER"), "who can also defend the guaranteed nation")
	_check("unprovoked_aggression" not in D.casus_belli_options(gs, "ESP", "GER"), "a distant bystander does not")
	_check(D.grievance(gs, "FRA", "GER") == 40.0, "the neighbours resent it")
	_check(not D.provoked(gs, "FRA", "GER"), "not yet enough to strike")

	# Resentment cools.
	D.step_month(gs)
	_check(D.grievance(gs, "FRA", "GER") == 38.0, "grievance cools by a step a month")
	D.add_grievance(gs, "NED", "GER", 70.0)
	D.add_grievance(gs, "ESP", "GER", 70.0)
	_check(D.provoked(gs, "NED", "GER"), "a Dutch grievance past the threshold is provoked")
	D.step_month(gs)
	_check(not gs.at_war("NED", "GER"), "the monthly step no longer declares for anyone: provoked AI nations answer through AIDiplomacy (see ai_diplomacy_test)")

	# The casus belli lapses after its years.
	_fresh()
	_declare("GER", "BEL", "none")
	for i in 5 * 12 + 2:
		D.step_month(gs)
		for d in 31:
			clock.advance_day()
	_check(gs.casus_belli.is_empty() and "unprovoked_aggression" not in D.casus_belli_options(gs, "FRA", "GER"), "the casus belli lapses after five years")


func _test_passage() -> void:
	_fresh()
	var fra: int = gs.nations["FRA"].provinces[0]
	var bel: int = gs.nations["BEL"].provinces[0]
	_check(Mil.can_enter(gs, "RUS", fra), "an ally's armies may enter French ground")
	_check(Mil.can_enter(gs, "GBR", fra), "and so may an Entente partner's")
	_check(not Mil.can_enter(gs, "GER", bel), "Germany may not enter neutral Belgium")
	D.add_treaty(gs, "passage", "BEL", "GER")
	_check(Mil.can_enter(gs, "GER", bel) and not Mil.can_enter(gs, "BEL", gs.nations["GER"].provinces[0]), "a passage treaty opens Belgium to Germany, one way")
	gs.set_war("FRA", "GER", true)
	_check(Mil.can_enter(gs, "FRA", gs.nations["GER"].provinces[0]), "war still opens the enemy's ground")
	# Ground an ally owns but an enemy holds is open only if the holder allows it too.
	gs.set_war("ITA", "GER", true)
	gs.province_controller[fra] = "ITA"
	_check(not Mil.can_enter(gs, "RUS", fra), "ground held by a third party needs its leave as well as the owner's")


func _war_with_any(tag: String) -> bool:
	return not gs.wars_of(tag).is_empty()


func _test_joins() -> void:
	# An attack on guaranteed Belgium pulls in the guarantors, and their allies after them.
	_fresh()
	_declare("GER", "BEL", "none")
	_settle()
	var wars_total: int = gs.wars.size()
	_check(gs.at_war("GBR", "GER") and gs.at_war("FRA", "GER"), "Britain and France, Belgium's guarantors, join against Germany")
	_check(gs.war_between("GBR", "GER").casus_belli == "guarantee_defence", "on a guarantee casus belli")
	_check(gs.at_war("RUS", "GER"), "France's ally Russia is called in after it")
	_check(gs.at_war("AUH", "BEL") and gs.at_war("AUH", "GBR") and gs.at_war("AUH", "RUS"), "Germany's ally Austria-Hungary joins against the whole other side")
	_check(not _war_with_any("ITA"), "Italy stays out: its alliance is defensive only and Germany is the aggressor")
	_check(not _war_with_any("POR"), "so does Portugal: Britain was not attacked")
	_check(not _war_with_any("ESP") and not _war_with_any("SRB"), "and nations with no tie")
	var group: int = gs.war_between("GER", "BEL").war_group
	var same := true
	for w: Object in gs.wars.values():
		if w.war_group != group:
			same = false
	_check(same, "every war of the conflict shares one war group")
	_check(D.group_side(gs, group, "attack") == ["AUH", "GER"], "the attackers are Germany and Austria-Hungary (%s)" % str(D.group_side(gs, group, "attack")))
	_check(D.group_side(gs, group, "defend") == ["BEL", "FRA", "GBR", "RUS"], "and the defenders their four enemies (%s)" % str(D.group_side(gs, group, "defend")))
	_check(wars_total == 2 * 4 - 0 and not gs.at_war("BEL", "RUS"), "wars are pairwise across the sides only (%d)" % wars_total)
	_check(gs.nations["ITA"].prestige == 0.0 and D.relation(gs, "ITA", "GER") > 0.0, "staying out of a call it was not bound by costs nothing")

	# An attack on Germany binds even Italy (a defensive alliance), and calls France's ally.
	_fresh()
	_declare("RUS", "GER", "none")
	_settle()
	_check(gs.at_war("AUH", "RUS") and gs.at_war("ITA", "RUS"), "an attack on Germany brings in Austria-Hungary and Italy")
	_check(gs.war_between("ITA", "RUS").casus_belli == "ally_called", "Italy on an ally casus belli")
	_check(gs.at_war("FRA", "GER"), "and Russia's ally France joins against Germany")

	# An entente is optional: the AI joins only against a nation it despises.
	_fresh()
	D.set_relation(gs, "GBR", "GER", -10.0)
	_declare("GER", "FRA", "none")
	_settle()
	_check(not gs.at_war("GBR", "GER") and D.relation(gs, "GBR", "FRA") >= 25.0, "Britain stays out of Germany's war on France at middling hostility")
	_fresh()
	D.set_relation(gs, "GBR", "GER", -30.0)
	_declare("GER", "FRA", "none")
	_settle()
	_check(gs.at_war("GBR", "GER") and gs.war_between("GBR", "GER").casus_belli == "ally_called", "but joins once the world's anger at Germany has pushed it below the line")

	# A border violation asks the guarantors without making the victim a combatant.
	_fresh()
	D.violate_border(gs, "GER", "BEL")
	_settle()
	_check(gs.at_war("GBR", "GER") and gs.at_war("FRA", "GER") and not gs.at_war("BEL", "GER"), "crossing Belgium's border brings in its guarantors (no war between the two)")

	# The war that exists at the start calls its allies up, and the crisis plays out.
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	gs.set_player("ESP")
	_check(gs.at_war("AUH", "SRB") and gs.wars.size() == 1, "only the Austro-Serbian war is on at first")
	var g: int = gs.war_between("AUH", "SRB").war_group
	_check(D.group_side(gs, g, "attack") == ["AUH"] and D.group_side(gs, g, "defend") == ["SRB"], "registered as a conflict")
	var called: Array = []
	for d: Dictionary in gs.join_calls.values():
		called.append(d.tag)
	called.sort()
	_check(called == ["GER", "MNE", "RUS"], "Russia, Montenegro and Germany are called up (%s)" % str(called))
	_check(not _war_with_any("RUS"), "but have not joined yet")
	var start_day: int = clock.days_elapsed
	_settle()
	_check(gs.at_war("RUS", "AUH") and gs.at_war("MNE", "AUH") and gs.at_war("GER", "SRB") and gs.at_war("GER", "RUS"), "they enter the war once mobilized")
	_check(gs.at_war("FRA", "GER") and gs.at_war("FRA", "AUH"), "France follows Russia in")
	_check(not _war_with_any("ITA") and not _war_with_any("ESP"), "while Italy and the neutrals stay out")
	_check(clock.days_elapsed - start_day >= 8 and clock.days_elapsed - start_day <= 40, "after a mobilization of days, not at once (%d days)" % (clock.days_elapsed - start_day))
	_check(gs.nations["RUS"].mobilization >= 0.4 and gs.nations["GER"].mobilization >= 0.4, "the great powers are on a war footing")
	_check(gs.alarms.has("RUS>GER") or gs.alarms.has("GER>RUS") or gs.at_war("GER", "RUS"), "their mobilization alarmed each other along the way")


func _test_player_join() -> void:
	_fresh()
	gs.set_player("FRA")
	var asked := []
	gs.join_requested.connect(func(d: Dictionary) -> void: asked.append(d.kind))
	_declare("GER", "BEL", "none")
	_check(gs.pending_joins.size() == 1 and asked == ["guarantee"], "the player is asked, as Belgium's guarantor")
	var d: Dictionary = gs.pending_joins[0]
	_check(d.tag == "FRA" and d.ally == "BEL" and d.enemies == ["GER"] and d.join_cost.prestige == 5, "with the enemies and the price of joining")
	_check(d.decline_cost.end_treaty and d.decline_cost.ally_relations == -30, "and the price of declining")
	_check(clock.paused and not gs.at_war("FRA", "GER"), "time is held and France is not at war yet")
	clock.paused = false
	_check(clock.paused, "and cannot be started while a decision waits")
	_check(gs.join_calls.has("GBR|%d" % d.group) and not gs.at_war("GBR", "GER"), "the AI guarantor is called up, and has not joined yet")
	_settle()
	_check(gs.at_war("GBR", "GER"), "and joins once mobilized")
	_check(not gs.issue(AnswerJoinC.new(999, true)), "an answer to no such decision is refused")

	# Declining.
	var rel: float = D.relation(gs, "FRA", "BEL")
	var prestige: float = gs.nations["FRA"].prestige
	_check(gs.issue(AnswerJoinC.new(d.id, false)), "France declines")
	_check(D.relation(gs, "FRA", "BEL") == rel - 30.0 and gs.nations["FRA"].prestige == prestige - 10.0, "which costs Belgium's goodwill and prestige")
	_check(not D.has_treaty(gs, "guarantee", "FRA", "BEL"), "and ends the guarantee")
	_check(not gs.at_war("FRA", "GER") and gs.pending_joins.is_empty(), "France stays out and nothing is left pending")
	clock.paused = false
	_check(not clock.paused, "time can run once nothing is pending")
	clock.paused = true

	# Joining.
	_fresh()
	gs.set_player("FRA")
	_declare("GER", "BEL", "none")
	d = gs.pending_joins[0]
	var prestige_before: float = gs.nations["FRA"].prestige
	_check(gs.issue(AnswerJoinC.new(d.id, true)), "France joins")
	_settle()
	_check(gs.at_war("FRA", "GER") and gs.at_war("RUS", "GER") and gs.at_war("AUH", "FRA"), "and brings Russia in, and the other side's allies are called against it")
	_check(absf(gs.nations["FRA"].prestige - (prestige_before + 5.0)) < 0.5, "defending a guaranteed nation earns prestige")
	_check(gs.command_log.back().type == "AnswerJoin" and gs.command_log.back().joins, "the answer is in the command log")


func _test_crisis() -> void:
	# A war with no casus belli needs mobilization first.
	_fresh()
	gs.nations["GER"].mobilization = 0.0
	_check(D.declare_gate(gs, "GER", "none") == "mobilization" and not gs.issue(DeclareC.new("GER", "BEL", "none")), "an unjustified war is refused before mobilization")
	_check(D.declare_gate(gs, "GER", "border_claim") == "", "a justified one is not held up")
	gs.nations["GER"].mobilization = 0.3
	_check(gs.issue(DeclareC.new("GER", "BEL", "none")), "and goes ahead once the nation is 30% mobilized")

	# Mobilizing alarms the neighbours, once.
	_fresh()
	gs.set_player("GER")  # the AI would otherwise ease its own mobilization back down
	var fra_rel: float = D.relation(gs, "FRA", "GER")
	gs.nations["GER"].mobilization = 0.35
	D.step_day(gs)
	_check(gs.alarms.has("GER>FRA") and gs.alarms.has("GER>NED"), "Germany's mobilization alarms its neighbours")
	_check(not gs.alarms.has("GER>AUH"), "but not its ally")
	_check(D.relation(gs, "FRA", "GER") == fra_rel - 10.0 and D.grievance(gs, "FRA", "GER") == 15.0, "they think worse of it and resent it")
	_check(gs.mobilization_calls.has("RUS|GER") and not gs.mobilization_calls.has("GBR|GER"), "France's ally is called up; an entente partner is not")
	D.step_day(gs)
	_check(D.relation(gs, "FRA", "GER") == fra_rel - 10.0, "the alarm is raised once, not every day")
	var fra: Object = gs.nations["FRA"]
	for i in 12:
		D.step_day(gs)
	_check(is_equal_approx(fra.mobilization, 0.28), "France, whose ally Russia was alarmed, answers with 80%% of it (%.3f)" % fra.mobilization)
	_check(is_equal_approx(gs.nations["RUS"].mobilization, 0.28) and is_equal_approx(gs.nations["BEL"].mobilization, 0.175), "Russia likewise; Belgium, alarmed directly, with 50%% (%.3f)" % gs.nations["BEL"].mobilization)
	_check(gs.nations["ITA"].mobilization == 0.0, "an uninvolved nation does not move")
	gs.nations["GER"].mobilization = 0.05
	D.step_day(gs)
	_check(gs.alarms.is_empty() and gs.mobilization_calls.is_empty(), "standing down clears the alarm and the calls")
	for i in 40:
		D.step_day(gs)
	_check(fra.mobilization == 0.0, "and the neighbours stand down in time")

	# The player is never mobilized for, but a war puts everyone on a footing.
	_fresh()
	gs.set_player("FRA")
	gs.nations["GER"].mobilization = 0.35
	D.step_day(gs)
	D.step_day(gs)
	_check(gs.nations["FRA"].mobilization == 0.0, "the player's own mobilization is left to the player")
	gs.set_war("FRA", "GER", true)
	for i in 12:
		D.step_day(gs)
	_check(is_equal_approx(gs.nations["FRA"].mobilization, 0.5) and is_equal_approx(gs.nations["GER"].mobilization, 0.5), "a nation at war is raised to the war floor")
	gs.nations["FRA"].economy_law = "war_economy"
	gs.nations["FRA"].mobilization = 0.8
	D.step_day(gs)
	_check(gs.nations["FRA"].mobilization == 0.8, "but never lowered by it")


func _test_player_crisis() -> void:
	# The default player (France) is asked when Russia, its ally, enters the war.
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	gs.set_player("FRA")
	for i in 60:
		if not gs.pending_joins.is_empty():
			break
		clock.advance_day()
	_check(gs.pending_joins.size() == 1 and gs.pending_joins[0].tag == "FRA" and gs.pending_joins[0].ally == "RUS", "France is asked to join once Russia has mobilized and entered")
	_check(gs.pending_joins[0].kind == "alliance_called" and clock.paused, "as a called ally, with time held")
	_check(not gs.at_war("FRA", "GER") and gs.at_war("RUS", "AUH"), "while Russia is already at war")


func _test_points() -> void:
	_fresh()
	var C: Dictionary = D.cfg.points
	_check(gs.nations["FRA"].diplomacy_points == 50.0 and C.max == 200, "a nation starts with 50 points and can hold 200")
	_check(D.cost_of("declare_war", "none") == 30.0 and D.cost_of("declare_war", "reconquest") == 10.0 and D.cost_of("declare_war", "ally_called") == 0.0, "an unjustified war costs 30, a claim 10, a called ally nothing")
	_check(D.cost_of("propose", "alliance") == 40.0 and D.cost_of("cancel", "nap") == 10.0 and D.cost_of("gift") == 10.0, "treaties, cancelling and gifts have prices")

	# Income.
	var fra: Dictionary = D.point_income_parts(gs, "FRA")
	_check(fra.base == 3.0 and fra.output == 1.5 and is_equal_approx(fra.total, 4.5), "France earns 3 and a bonus for being a top-five economy (%.1f)" % fra.total)
	_check(is_equal_approx(D.point_income(gs, "LUX"), 3.0), "a small nation earns the base (3)")
	gs.nations["LUX"].prestige = 50.0
	_check(is_equal_approx(D.point_income(gs, "LUX"), 5.0), "prestige adds 0.04 a point")
	gs.nations["LUX"].prestige = -500.0
	_check(D.point_income(gs, "LUX") == 1.0, "but income never falls below 1")
	gs.nations["LUX"].prestige = 0.0
	D.step_month(gs)
	_check(is_equal_approx(gs.nations["FRA"].diplomacy_points, 54.5) and is_equal_approx(gs.nations["LUX"].diplomacy_points, 53.0), "each month adds the income")
	gs.nations["FRA"].diplomacy_points = 199.0
	D.step_month(gs)
	_check(gs.nations["FRA"].diplomacy_points == 200.0, "and stops at the maximum")
	var seen := []
	gs.diplomacy_points_changed.connect(func(tag: String, v: float) -> void: seen.append([tag, v]))
	D.spend(gs, "FRA", 20.0)
	_check(seen.size() == 1 and seen[0] == ["FRA", 180.0], "spending sends a signal")
	D.spend(gs, "FRA", 1000.0)
	_check(gs.nations["FRA"].diplomacy_points == 0.0, "and cannot go below zero")

	# Declaring war.
	_fresh()
	var cmd = DeclareC.new("FRA", "GER", "reconquest")
	_check(gs.issue(cmd) and gs.nations["FRA"].diplomacy_points == 40.0, "declaring war on a claim costs 10 points")
	_fresh()
	gs.nations["FRA"].diplomacy_points = 9.0
	cmd = DeclareC.new("FRA", "GER", "reconquest")
	_check(not gs.issue(cmd) and cmd.reason == "points" and not gs.at_war("FRA", "GER") and gs.nations["FRA"].diplomacy_points == 9.0, "with 9 points the declaration is refused and nothing is spent")
	_fresh()
	gs.nations["GER"].mobilization = 0.5
	gs.nations["GER"].diplomacy_points = 29.0
	cmd = DeclareC.new("GER", "BEL", "none")
	_check(not gs.issue(cmd) and cmd.reason == "points", "a war with no justification needs 30")
	gs.nations["GER"].diplomacy_points = 30.0
	_check(gs.issue(DeclareC.new("GER", "BEL", "none")) and gs.nations["GER"].diplomacy_points == 0.0, "and uses them up")
	_fresh()
	gs.issue(DeclareC.new("FRA", "GER", "reconquest"))
	var after: float = gs.nations["FRA"].diplomacy_points
	_check(not gs.issue(DeclareC.new("FRA", "GER", "reconquest")) and gs.nations["FRA"].diplomacy_points == after, "a refused declaration for another reason costs nothing")

	# Internal moves are free: a nation bound to a war, or retaliating, spends nothing.
	_fresh()
	gs.nations["GER"].mobilization = 0.5
	D.declare_war(gs, "GER", "BEL", "none")
	_check(gs.nations["GER"].diplomacy_points == 50.0, "the rules' own declarations (war plans, retaliation, joins) are free")
	_settle()
	_check(gs.nations["GBR"].diplomacy_points >= 50.0 and gs.nations["FRA"].diplomacy_points >= 50.0, "as is joining a war")

	# Treaties.
	_fresh()
	var prop = ProposeTreatyC.new("FRA", "ITA", "nap")
	_check(gs.issue(prop) and prop.result.accepted and gs.nations["FRA"].diplomacy_points == 35.0, "a pact Italy accepts costs 15 points")
	_fresh()
	prop = ProposeTreatyC.new("ESP", "POR", "nap")
	_check(gs.issue(prop) and not prop.result.accepted and is_equal_approx(gs.nations["ESP"].diplomacy_points, 42.5), "a refused one costs half: 7.5 of the 15 come back")
	_fresh()
	gs.nations["FRA"].diplomacy_points = 14.0
	prop = ProposeTreatyC.new("FRA", "ITA", "nap")
	_check(not gs.issue(prop) and prop.result.reason == "points" and not D.has_treaty(gs, "nap", "FRA", "ITA") and gs.nations["FRA"].diplomacy_points == 14.0, "14 points do not buy a pact")
	gs.nations["FRA"].diplomacy_points = 50.0
	prop = ProposeTreatyC.new("FRA", "RUS", "alliance")
	_check(not gs.issue(prop) and prop.result.reason == "exists" and gs.nations["FRA"].diplomacy_points == 50.0, "a proposal that cannot be made costs nothing")

	# Cancelling and gifts.
	_fresh()
	var nap = D.add_treaty(gs, "nap", "FRA", "ITA")
	gs.nations["FRA"].diplomacy_points = 9.0
	var cancel = CancelC.new("FRA", nap.id)
	_check(not gs.issue(cancel) and cancel.reason == "points" and D.has_treaty(gs, "nap", "FRA", "ITA"), "cancelling a pact needs 10 points")
	gs.nations["FRA"].diplomacy_points = 10.0
	_check(gs.issue(CancelC.new("FRA", nap.id)) and not D.has_treaty(gs, "nap", "FRA", "ITA") and gs.nations["FRA"].diplomacy_points == 0.0, "and spends them")
	_fresh()
	var money: float = gs.nations["FRA"].treasury
	var gift = GiftC.new("FRA", "ITA", 5.0)
	_check(gs.issue(gift) and gs.nations["FRA"].diplomacy_points == 40.0 and is_equal_approx(gs.nations["FRA"].treasury, money - 5.0), "a gift costs 10 points as well as the money")
	gs.nations["FRA"].diplomacy_points = 4.0
	gift = GiftC.new("FRA", "ITA", 5.0)
	_check(not gs.issue(gift) and gift.reason == "points" and is_equal_approx(gs.nations["FRA"].treasury, money - 5.0), "and is refused when the points are short, the money untouched")


func _test_income_sources() -> void:
	_fresh()
	var base: float = D.point_income(gs, "FRA")
	_check(gs.issue(ProgramC.new("FRA", "diplomatic_service", true)), "the Diplomatic service program can be switched on")
	var parts: Dictionary = D.point_income_parts(gs, "FRA")
	_check(is_equal_approx(parts.program, 1.5) and is_equal_approx(parts.total, base + 1.5), "and adds 1.5 a month (%.1f to %.1f)" % [base, parts.total])
	gs.issue(ProgramC.new("FRA", "diplomatic_service", false))
	_check(is_equal_approx(D.point_income(gs, "FRA"), base), "switched off, it adds nothing")

	_check(not Eco.cfg.buildings.has("foreign_ministry") and not D.point_income_parts(gs, "FRA").has("ministry"), "there is no Foreign ministry any more: points come from the program, prestige and output")

	# Prestige: fades, and comes from treaties.
	gs.nations["FRA"].prestige = 100.0
	D.step_month(gs)
	_check(is_equal_approx(gs.nations["FRA"].prestige, 99.0), "prestige fades 1% a month")
	gs.nations["FRA"].prestige = 0.0
	gs.nations["SUI"].prestige = 0.0
	var prop = ProposeTreatyC.new("FRA", "SUI", "guarantee")
	gs.issue(prop)
	_check(prop.result.accepted and is_equal_approx(gs.nations["FRA"].prestige, 1.0) and is_equal_approx(gs.nations["SUI"].prestige, 1.0), "a new guarantee earns both sides a point of prestige")
	var win := 0.0
	gs.nations["FRA"].prestige = 0.0
	var WS = load("res://scripts/sim/war_support.gd")
	WS.on_battle(gs, {"winner": "FRA", "loser": "GER", "province": gs.nations["FRA"].provinces[0]})
	_check(is_equal_approx(gs.nations["FRA"].prestige, 0.25), "a battle won earns a quarter point")


func _test_buying() -> void:
	_fresh()
	var money: float = gs.nations["FRA"].treasury
	_check(is_equal_approx(D.purchase_price(gs, "FRA"), 3.0), "ten points first cost £3M")
	var buy = BuyC.new("FRA")
	_check(gs.issue(buy) and gs.nations["FRA"].diplomacy_points == 60.0 and is_equal_approx(gs.nations["FRA"].treasury, money - 3.0), "buying gives ten points for the money")
	_check(is_equal_approx(D.purchase_price(gs, "FRA"), 3.75), "and the next batch costs a quarter more")
	gs.issue(BuyC.new("FRA"))
	_check(is_equal_approx(D.purchase_price(gs, "FRA"), 3.0 * 1.25 * 1.25), "again")
	D.step_month(gs)
	_check(D.purchase_price(gs, "FRA") < 3.0 * 1.25 * 1.25 and D.purchase_price(gs, "FRA") > 3.0, "the price eases back each month (%.2f)" % D.purchase_price(gs, "FRA"))
	for i in 40:
		D.step_month(gs)
		gs.nations["FRA"].diplomacy_points = 50.0
	_check(D.purchase_price(gs, "FRA") < 3.1, "and returns to normal in time")
	gs.nations["FRA"].diplomacy_points = 195.0
	gs.issue(BuyC.new("FRA"))
	_check(gs.nations["FRA"].diplomacy_points == 200.0, "points bought never pass the maximum")
	buy = BuyC.new("FRA")
	_check(not gs.issue(buy) and buy.reason == "full", "and nothing can be bought once the stock is full")
	gs.nations["FRA"].diplomacy_points = 50.0
	gs.nations["FRA"].treasury = 1.0
	buy = BuyC.new("FRA")
	_check(not gs.issue(buy) and buy.reason == "money" and gs.nations["FRA"].diplomacy_points == 50.0, "without the money it is refused")


func _test_improving() -> void:
	_fresh()
	var rel: float = D.relation(gs, "FRA", "ITA")
	var base: float = gs.relation_base[D.pair_key("FRA", "ITA")]
	var cmd = ImproveC.new("FRA", "ITA")
	_check(gs.issue(cmd) and gs.nations["FRA"].diplomacy_points == 40.0 and gs.relation_projects.size() == 1, "improving relations costs 10 points and starts an effort")
	_check(D.improving(gs, "FRA", "ITA").months_left == 12, "that lasts twelve months")
	cmd = ImproveC.new("FRA", "ITA")
	_check(not gs.issue(cmd) and cmd.reason == "active" and gs.nations["FRA"].diplomacy_points == 40.0, "the same effort cannot be started twice, and costs nothing")
	D.step_month(gs)
	_check(D.relation(gs, "FRA", "ITA") >= rel + 1.5, "each month they warm to each other (%.1f to %.1f)" % [rel, D.relation(gs, "FRA", "ITA")])
	_check(is_equal_approx(gs.relation_base[D.pair_key("FRA", "ITA")], base + 0.25), "and a little of it lasts")
	_check(D.improving(gs, "FRA", "ITA").months_left == 11, "the effort counts down")
	for i in 11:
		D.step_month(gs)
	_check(D.improving(gs, "FRA", "ITA") == null and gs.relation_projects.is_empty(), "after a year it is over")
	_check(is_equal_approx(gs.relation_base[D.pair_key("FRA", "ITA")], base + 3.0), "leaving what they settle at three points higher")
	# Limits.
	_fresh()
	gs.nations["FRA"].diplomacy_points = 100.0
	for tag in ["ITA", "ESP", "SUI"]:
		gs.issue(ImproveC.new("FRA", tag))
	var fourth = ImproveC.new("FRA", "BEL")
	_check(not gs.issue(fourth) and fourth.reason == "limit" and gs.relation_projects.size() == 3, "only three efforts at a time")
	_fresh()
	gs.set_war("FRA", "GER", true)
	var at_war = ImproveC.new("FRA", "GER")
	_check(not gs.issue(at_war) and at_war.reason == "at_war", "not with an enemy")
	_fresh()
	gs.issue(ImproveC.new("FRA", "ITA"))
	gs.set_war("FRA", "ITA", true)
	D.step_month(gs)
	_check(gs.relation_projects.is_empty(), "a war ends an effort")
	_fresh()
	D.set_relation(gs, "FRA", "ITA", 100.0)
	var maxed = ImproveC.new("FRA", "ITA")
	_check(not gs.issue(maxed) and maxed.reason == "maxed", "and there is no improving what is already perfect")
	_fresh()
	gs.nations["FRA"].diplomacy_points = 9.0
	var poor = ImproveC.new("FRA", "ITA")
	_check(not gs.issue(poor) and poor.reason == "points", "it needs the points")
