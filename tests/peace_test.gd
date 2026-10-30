extends SceneTree
## Headless test for war score and peace: scoring, prices, offers, AI answers, terms.
## Run: godot --headless --path . -s res://tests/peace_test.gd
## Class names are loaded at runtime because this script compiles before the autoloads exist.

var _failures := 0
var gs: Node
var clock: Node
var P
var D
var Mil
var UnitC
var ProposeC
var AnswerC
var DeclareC


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
	P = load("res://scripts/sim/peace.gd")
	D = load("res://scripts/sim/diplomacy.gd")
	Mil = load("res://scripts/sim/military.gd")
	UnitC = load("res://scripts/sim/unit.gd")
	ProposeC = load("res://scripts/sim/propose_peace.gd")
	AnswerC = load("res://scripts/sim/answer_peace.gd")
	DeclareC = load("res://scripts/sim/declare_war.gd")

	_test_score()
	_test_prices_and_checks()
	_test_ai_answers()
	_test_terms()
	_test_clauses()
	_test_capital()
	_test_quarter()
	_test_player()
	_test_separate_peace()
	_test_overtures()

	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)


## A quiet world with France and Germany at war and the player in neutral Spain.
func _war() -> Object:
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	gs.join_calls.clear()
	gs.scenario["war_plans"] = []
	gs.wars.clear()
	gs.armies.clear()
	gs.set_player("ESP")
	gs.set_war("FRA", "GER", true)
	return gs.war_between("FRA", "GER")


## `by` takes control of `count` provinces `owner` holds, from the border inward (never the capital).
func _occupy(owner: String, by: String, count: int) -> Array:
	var ids: Array = []
	# From the border inward, so the ground held hangs together as a front would leave it.
	var Mil_ = load("res://scripts/sim/military.gd")
	var order: Array = []
	var queue: Array = []
	for id: int in gs.nations[owner].provinces:
		for n: int in Mil_.neighbors(id):
			if gs.province_owner[n] == by:
				queue.append(id)
				break
	while not queue.is_empty():
		var p: int = queue.pop_front()
		if p in order:
			continue
		order.append(p)
		for n: int in Mil_.neighbors(p):
			if gs.province_owner[n] == owner and n not in order:
				queue.append(n)
	for id: int in gs.nations[owner].provinces:
		if id not in order:
			order.append(id)
	for id: int in order:
		if ids.size() >= count:
			break
		if id != gs.nations[owner].capital:
			gs.set_controller(id, by)
			ids.append(id)
	return ids


## The least valuable province a nation owns on its border with `by`, apart from its capital.
func _cheapest(owner: String, by: String) -> int:
	var best := 0
	for id: int in gs.nations[owner].provinces:
		var on_border := false
		for n: int in Mil.neighbors(id):
			on_border = on_border or gs.province_owner[n] == by
		if on_border and id != gs.nations[owner].capital and (best == 0 or P.province_share(gs, id, owner) < P.province_share(gs, best, owner)):
			best = id
	return best


func _test_score() -> void:
	var war = _war()
	_check(P.war_score(gs, war, "FRA") == 0.0 and P.war_score(gs, war, "GER") == 0.0, "a war starts level")
	_check(gs.nations["GER"].capital == 368 and gs.nations["FRA"].capital == 233, "nations have capitals")
	var taken := _occupy("GER", "FRA", 20)
	var pts: float = P.occupation_points(gs, "FRA", "GER")
	_check(pts > 0.0 and pts < 50.0, "holding 20 German provinces earns France some points (%.1f)" % pts)
	_check(is_equal_approx(P.war_score(gs, war, "FRA"), pts) and is_equal_approx(P.war_score(gs, war, "GER"), -pts), "the score is the same number from both sides, signed")
	for id: int in taken:
		gs.set_controller(id, "GER")
	_check(P.war_score(gs, war, "FRA") == 0.0, "and goes when the ground is retaken")

	var parts: Dictionary = P.score_parts(gs, war, "FRA")
	_check(parts.occupation == 0.0 and parts.capital == 0.0 and parts.battles == 0.0, "the parts are all zero again")
	gs.set_controller(368, "FRA")
	var cap: float = P.score_parts(gs, war, "FRA").capital
	var whole: float = P.score_parts(gs, war, "FRA").capital + P.score_parts(gs, war, "FRA").occupation
	_check(P.capital_taken_by(gs, "GER") == "FRA" and cap > 20.0 and cap < 33.0, "the capital's bonus is a large part of the score (%.1f)" % cap)
	_check(is_equal_approx(whole, 33.0), "Berlin with its bonus is a third of Germany's value (%.1f)" % whole)
	_check(is_equal_approx(P.score_parts(gs, war, "GER").capital, -cap), "and costs the other side the same")
	gs.set_controller(368, "GER")

	P.record_battle(war, {"winner": "FRA", "lost": {"FRA": 5000.0, "GER": 20000.0}})
	_check(is_equal_approx(war.battle_points["FRA"], 6.0), "a battle won scales with the loser's losses (%.2f)" % war.battle_points["FRA"])
	P.record_battle(war, {"winner": "GER", "lost": {"FRA": 400000.0, "GER": 1000.0}})
	_check(is_equal_approx(war.battle_points["GER"], 10.0), "and is capped at 10")
	P.record_battle(war, {"winner": "", "lost": {"FRA": 1000.0, "GER": 1000.0}})
	_check(is_equal_approx(P.war_score(gs, war, "FRA"), -4.0), "a draw earns nothing; the score is the difference (%.2f)" % P.war_score(gs, war, "FRA"))
	gs.set_controller(368, "FRA")
	for id in range(1, gs.province_owner.size()):
		if gs.province_owner[id] == "GER":
			gs.set_controller(id, "FRA")
	war.battle_points["FRA"] = 20.0
	_check(P.war_score(gs, war, "FRA") == 100.0 and P.war_score(gs, war, "GER") == -100.0, "the score is capped at 100")
	gs.set_war("FRA", "GER", false)
	war = _war()
	P.record_battle(war, {"winner": "FRA", "lost": {"FRA": 5000.0, "GER": 20000.0}})
	P.step_month(gs)
	_check(is_equal_approx(war.battle_points["FRA"], 6.0 * 0.98), "battle points fade 2% a month")


func _test_prices_and_checks() -> void:
	var war = _war()
	var taken := _occupy("GER", "FRA", 10)
	var held: int = taken[0]
	var free_id := 0
	for id: int in gs.nations["GER"].provinces:
		if gs.province_controller[id] == "GER" and id != 368:
			free_id = id
			break
	var held_price: float = P.province_price(gs, held, "FRA", "GER")
	var free_price: float = P.province_price(gs, free_id, "FRA", "GER")
	_check(held_price > 0.0 and free_price > 0.0, "provinces have a price (%.2f held, %.2f free)" % [held_price, free_price])
	var same_weight: float = P.province_share(gs, held, "GER") * 100.0
	_check(is_equal_approx(held_price, same_weight * 0.5), "ground already held costs half")
	_check(is_equal_approx(P.province_price(gs, 368, "FRA", "GER"), P.province_share(gs, 368, "GER") * 100.0) and is_equal_approx(P.province_share(gs, 368, "GER"), 0.33), "a capital costs its bonus: a third of the country")
	_check(P.demand_cost(gs, "FRA", "GER", {"kind": "province", "ids": [233]}) == -1.0, "a province the other side does not own cannot be demanded")
	_check(P.demand_cost(gs, "FRA", "GER", {"kind": "indemnity", "share": 0.9, "months": 12}) == -1.0, "nor an indemnity past the share limit")
	_check(is_equal_approx(P.demand_cost(gs, "FRA", "GER", {"kind": "indemnity", "share": 0.25, "months": 60}), 25.0), "an indemnity of a quarter of revenue for five years costs 25")
	_check(P.demand_cost(gs, "FRA", "GER", {"kind": "release_ally", "nation": "AUH"}) == 10.0, "releasing an ally costs 10")
	_check(P.demand_cost(gs, "FRA", "GER", {"kind": "release_ally", "nation": "ITA"}) == 10.0, "also a defensive-only one")
	_check(P.demand_cost(gs, "FRA", "GER", {"kind": "release_ally", "nation": "ESP"}) == -1.0, "but not a nation it has no tie to")
	_check(P.demand_cost(gs, "FRA", "GER", {"kind": "nonsense"}) == -1.0, "unknown demands are invalid")

	var ok: Dictionary = P.check(gs, "FRA", "GER", "demand", [{"kind": "province", "ids": taken}])
	_check(ok.ok and ok.taker == "FRA" and ok.giver == "GER" and ok.cost > 0.0, "France can demand the ground it holds")
	var dear: Dictionary = P.check(gs, "FRA", "GER", "demand", [{"kind": "indemnity", "share": 0.5, "months": 60}])
	_check(not dear.ok and dear.reason == "too_expensive", "but not an indemnity it cannot pay for (%.1f)" % dear.cost)
	_check(P.check(gs, "FRA", "ITA", "demand", []).reason == "no_war", "peace needs a war")
	_check(P.check(gs, "FRA", "GER", "demand", [{"kind": "province", "ids": [233]}]).reason == "invalid", "an invalid demand is refused")
	var back: Dictionary = P.check(gs, "GER", "FRA", "demand", [{"kind": "indemnity", "share": 0.1, "months": 12}])
	_check(back.reason == "too_expensive", "Germany, behind, cannot demand anything")
	_check(P.check(gs, "GER", "FRA", "demand", []).ok, "but a white peace costs nothing")
	_check(P.check(gs, "GER", "FRA", "offer", [{"kind": "indemnity", "share": 0.1, "months": 12}]).ok, "and Germany can offer money to France, who is ahead")


func _test_ai_answers() -> void:
	# The AI giver refuses while it is not losing.
	var war = _war()
	var r: Dictionary = P.propose(gs, "FRA", "GER", "demand", [{"kind": "release_ally", "nation": "AUH"}])
	_check(r.reason == "too_expensive", "no score, no terms")
	var cheap := _cheapest("GER", "FRA")
	gs.set_controller(cheap, "FRA")
	var small: Array = [{"kind": "province", "ids": [cheap]}]
	_check(P.check(gs, "FRA", "GER", "demand", small).ok, "a small win pays for one province")
	var score: float = P.war_score(gs, war, "GER")
	_check(score > -5.0, "Germany is barely behind (%.2f)" % score)
	r = P.propose(gs, "FRA", "GER", "demand", small)
	_check(r.ok and r.accepted == false and gs.at_war("FRA", "GER"), "so it refuses and the war goes on")
	_check(gs.peace_cooldown.has("FRA|GER"), "the proposer must wait before asking again")
	_check(P.check(gs, "FRA", "GER", "demand", small).reason == "cooldown", "a second ask is held up")

	# A white peace is taken unless the nation is clearly winning.
	war = _war()
	_check(P.propose(gs, "FRA", "GER", "demand", []).accepted == true and not gs.at_war("FRA", "GER"), "a white peace in a level war is accepted")
	war = _war()
	_occupy("FRA", "GER", 80)
	_check(P.war_score(gs, war, "GER") > 20.0, "Germany is far ahead (%.1f)" % P.war_score(gs, war, "GER"))
	r = P.propose(gs, "FRA", "GER", "demand", [])
	_check(r.accepted == false and gs.at_war("FRA", "GER"), "it will not make a white peace")

	# A losing AI accepts terms it can be made to pay.
	war = _war()
	var ids := _occupy("GER", "FRA", 60)
	var worth: float = P.war_score(gs, war, "FRA")
	_check(worth > 10.0, "France is well ahead (%.1f)" % worth)
	var terms: Array = [{"kind": "province", "ids": ids.slice(0, mini(30, P.max_cession(gs, "GER")))}]
	var price: float = P.check(gs, "FRA", "GER", "demand", terms).cost
	_check(price <= worth, "the terms are within its means (%.1f of %.1f)" % [price, worth])
	var cmd = ProposeC.new("FRA", "GER", "demand", terms)
	_check(gs.issue(cmd) and cmd.result.accepted == true, "Germany accepts the terms")
	_check(not gs.at_war("FRA", "GER") and gs.war_history.size() == 1, "the war is over")
	_check(gs.command_log.back().type == "ProposePeace", "and the proposal is in the command log")


func _test_terms() -> void:
	var war = _war()
	var ids := _occupy("GER", "FRA", 40)
	var pop_ger: int = gs.nations["GER"].population
	var pop_fra: int = gs.nations["FRA"].population
	var take: Array = ids.slice(0, 15)
	var moved_pop := 0
	for id: int in take:
		moved_pop += gs.province_population[id]
	var rest: Array = ids.slice(15)
	var ok: bool = P.propose(gs, "FRA", "GER", "demand", [{"kind": "province", "ids": take}]).accepted
	_check(ok == true, "the peace is made")
	for id: int in take:
		if gs.province_owner[id] != "FRA" or gs.province_controller[id] != "FRA":
			ok = false
	_check(ok, "ceded provinces change hands, owner and holder")
	_check(gs.nations["GER"].population == pop_ger - moved_pop and gs.nations["FRA"].population == pop_fra + moved_pop, "and their people go with them")
	var back := true
	for id: int in rest:
		if gs.province_controller[id] != "GER":
			back = false
	_check(back, "ground France held but did not take goes back to Germany")
	_check(war.peace.taker == "FRA" and war.peace.giver == "GER" and not war.peace.white and war.peace.terms.size() == 1, "the war records its terms")
	_check(gs.nations["FRA"].prestige > 1.0 and gs.nations["GER"].prestige < -0.5 and absf(gs.nations["GER"].prestige + gs.nations["FRA"].prestige / 2.0) < 0.01, "peace terms earn the taker prestige and cost the giver half as much (%.1f, %.1f)" % [gs.nations["FRA"].prestige, gs.nations["GER"].prestige])
	_check(war.log.back().kind == "peace" and war.log.back().text.contains("takes"), "and the log says who took what (%s)" % war.log.back().text.left(80))
	_check(gs.occupation.is_empty() or not gs.occupation.has(take[0]), "occupation of the ceded ground is dropped")

	# Armies on ground they may no longer stand on withdraw.
	war = _war()
	_occupy("GER", "FRA", 5)
	var deep := 0
	for id: int in gs.nations["GER"].provinces:
		if gs.province_controller[id] == "FRA":
			deep = id
			break
	var a = Mil.new_army(gs, "FRA", "Test army", deep)
	a.units.append(UnitC.new("infantry"))
	var b = Mil.new_army(gs, "GER", "Home guard", gs.nations["GER"].provinces[30])
	b.units.append(UnitC.new("infantry"))
	_check(gs.armies.size() == 2 and a.province == deep, "a French army stands in occupied Germany")
	P.propose(gs, "FRA", "GER", "demand", [])
	_check(not gs.at_war("FRA", "GER"), "white peace")
	_check(Mil.can_enter(gs, "FRA", a.province) and gs.province_owner[a.province] != "GER", "the French army has been pulled back to ground it may hold")
	_check(gs.armies.has(b.id) and b.province == gs.nations["GER"].provinces[30], "while the German army stays where it was")
	_check(gs.province_controller[deep] == "GER", "and the occupied province is German again")

	# An indemnity is paid over time.
	war = _war()
	_occupy("GER", "FRA", 60)
	var revenue: float = gs.nations["GER"].budget.revenue
	var ger0: float = gs.nations["GER"].treasury
	var fra0: float = gs.nations["FRA"].treasury
	var r: Dictionary = P.propose(gs, "FRA", "GER", "demand", [{"kind": "indemnity", "share": 0.1, "months": 3}])
	_check(r.accepted == true and gs.indemnities.size() == 1, "an indemnity is agreed")
	var monthly: float = revenue * 0.1 / 12.0
	_check(is_equal_approx(gs.indemnities[0].monthly, monthly), "a tenth of annual revenue spread over the months (%.2f a month)" % monthly)
	for i in 3:
		P.step_month(gs)
	_check(gs.indemnities.is_empty(), "it ends after three payments")
	_check(is_equal_approx(gs.nations["GER"].treasury, ger0 - 3.0 * monthly) and is_equal_approx(gs.nations["FRA"].treasury, fra0 + 3.0 * monthly), "Germany paid and France received %.1f" % (3.0 * monthly))
	gs.nations["GER"].treasury = 1.0
	gs.indemnities.append({"payer": "GER", "receiver": "FRA", "monthly": 5.0, "months_left": 1})
	var before: float = gs.nations["FRA"].treasury
	P.step_month(gs)
	_check(is_equal_approx(gs.nations["FRA"].treasury, before + 1.0) and gs.nations["GER"].treasury == 0.0, "a payer who cannot pay gives what it has")


func _test_clauses() -> void:
	var war = _war()
	_occupy("GER", "FRA", 60)
	var r: Dictionary = P.propose(gs, "FRA", "GER", "demand", [{"kind": "release_ally", "nation": "AUH"}])
	_check(r.accepted == true and not D.are_allied(gs, "GER", "AUH"), "Germany is made to give up its alliance with Austria-Hungary")
	_check(D.has_treaty(gs, "alliance", "FRA", "RUS"), "other treaties stand")

	war = _war()
	_occupy("GER", "FRA", 60)
	var border: Array = Mil.border_provinces(gs, "GER", "FRA")
	_check(not border.is_empty(), "Germany has provinces on France's border (%d)" % border.size())
	r = P.propose(gs, "FRA", "GER", "demand", [{"kind": "disarm_border", "years": 3}])
	_check(r.accepted == true and gs.restrictions.size() == 1, "a disarmed border is agreed")
	var inner: int = border[0]
	var elsewhere := 0
	for id: int in gs.nations["GER"].provinces:
		if id not in border:
			elsewhere = id
			break
	_check(not Mil.can_enter(gs, "GER", inner) and Mil.can_enter(gs, "GER", elsewhere), "German armies may not enter the border provinces, and may enter the rest")
	_check(Mil.can_enter(gs, "FRA", inner) == Mil.can_enter(gs, "FRA", inner), "France is not bound")
	gs.set_war("FRA", "GER", true)
	_check(Mil.can_enter(gs, "GER", inner), "a new war lifts the restriction")
	gs.set_war("FRA", "GER", false)
	_check(not Mil.can_enter(gs, "GER", inner), "and peace restores it")
	for i in 38:
		clock.days_elapsed += 30
		P.step_month(gs)
	_check(gs.restrictions.is_empty() and Mil.can_enter(gs, "GER", inner), "after three years it lapses")


## A great power gives up at most a quarter of its provinces at one peace, however beaten (step 1's check).
func _test_quarter() -> void:
	var war = _war()
	var cap: int = P.max_cession(gs, "GER")
	_check(cap == floori(gs.nations["GER"].provinces.size() * float(P.cfg().great_power_max_share)), "Germany may give up at most %d provinces at once" % cap)
	_check(P.max_cession(gs, "BEL") == gs.nations["BEL"].provinces.size(), "a small nation may be taken whole")
	var held := _occupy("GER", "FRA", cap + 3)
	gs.nations["GER"].war_support = 0.0
	var all_held: Array = held.filter(func(id: int) -> bool: return id != gs.nations["GER"].capital)
	_check(all_held.size() > cap and P.check(gs, "FRA", "GER", "demand", [{"kind": "province", "ids": all_held}]).reason == "too_much", "a beaten Germany is not asked for more (%d held)" % all_held.size())
	var picked: Array = P.pick_takeable(gs, "FRA", "GER", all_held, func(_id: int) -> float: return 0.0, INF).ids
	_check(picked.size() <= cap, "and the AI's choice of ground stops at the limit (%d)" % picked.size())
	gs.set_war("FRA", "GER", false)


func _test_capital() -> void:
	var war = _war()
	var held := _occupy("GER", "FRA", 1)
	gs.set_controller(368, "FRA")
	_check(P.capital_taken_by(gs, "GER") == "FRA", "France holds Berlin")
	var dear: Array = [{"kind": "indemnity", "share": 0.5, "months": 60}]
	var c: Dictionary = P.check(gs, "FRA", "GER", "demand", dear)
	_check(not c.forced and c.reason == "too_expensive", "a capital alone does not let the winner dictate: Germany still fights (%s)" % c.reason)
	_check(P.check(gs, "FRA", "GER", "demand", [{"kind": "province", "ids": [368]}]).reason == "capital", "and the capital is never ceded on its own")

	# Once its people's will is spent as well, Germany is beaten: more than the score pays, but only what is held.
	gs.nations["GER"].war_support = float(D.cfg.war_support.floor)
	var score: float = P.war_score(gs, war, "FRA")
	var modest: Array = [{"kind": "province", "ids": held}, {"kind": "indemnity", "share": 0.5, "months": 48}]
	c = P.check(gs, "FRA", "GER", "demand", modest)
	_check(c.ok and c.forced and c.cost > score and c.cost <= c.budget, "a beaten nation gives more than the score (%.1f of %.1f, up to %.1f)" % [c.cost, score, c.budget])
	var dearer: Array = dear + [{"kind": "release_ally", "nation": "AUH"}]
	_check(P.check(gs, "FRA", "GER", "demand", dearer).reason == "too_expensive", "but not without limit")
	var not_held := 0
	for id: int in gs.nations["GER"].provinces:
		if gs.province_controller[id] != "FRA" and id != 368 and P.province_problem(gs, "FRA", "GER", [id]) == "":
			not_held = id
			break
	_check(not_held > 0 and P.check(gs, "FRA", "GER", "demand", [{"kind": "province", "ids": [not_held]}]).reason == "forced_terms", "and only the ground France holds or fights for")
	var r: Dictionary = P.propose(gs, "FRA", "GER", "demand", modest)
	_check(r.accepted == true and gs.province_owner[held[0]] == "FRA", "Germany gives in at once")
	_check(gs.province_owner[368] == "GER" and gs.province_controller[368] == "GER", "and Berlin goes back to it")

	# Most of the country held is defeat too, whatever the people feel.
	war = _war()
	_occupy("GER", "FRA", 200)
	_check(P.occupied_share(gs, "FRA", "GER") >= float(P.cfg().forced.occupied_share) and P.is_forced(gs, "FRA", "GER"), "holding most of Germany beats it (%.2f)" % P.occupied_share(gs, "FRA", "GER"))

	# Ground that would not touch the taker's land cannot be taken.
	war = _war()
	var far := 0
	for id: int in gs.nations["GER"].provinces:
		if id != 368 and not P.detached(gs, "FRA", [id]).is_empty():
			far = id
			break
	gs.set_controller(far, "FRA")
	_check(far > 0 and P.check(gs, "FRA", "GER", "demand", [{"kind": "province", "ids": [far]}]).reason == "detached", "a province cut off from France's land cannot be ceded to it (%d)" % far)
	_check(P.detached(gs, "FRA", [far]) == [far], "and the screen can say which")


func _test_player() -> void:
	var war = _war()
	gs.set_player("GER")
	var held := _occupy("GER", "FRA", 60)
	var events := []
	gs.peace_offered.connect(func(o: Dictionary) -> void: events.append("offered"))
	gs.peace_resolved.connect(func(o: Dictionary, accepted: bool) -> void: events.append(accepted))
	var terms: Array = [{"kind": "province", "ids": [held[0]]}]
	var cmd = ProposeC.new("FRA", "GER", "demand", terms)
	_check(gs.issue(cmd) and cmd.result.accepted == null, "an offer to the player waits")
	_check(gs.pending_offers.size() == 1 and events == ["offered"], "and the player is told")
	_check(clock.paused, "time is held")
	clock.paused = false
	_check(clock.paused, "and cannot be started")
	_check(P.check(gs, "FRA", "GER", "demand", []).reason == "pending", "no second offer while one waits")
	_check(not gs.issue(AnswerC.new(99, true)), "an answer to no such offer is refused")
	var id: int = gs.pending_offers[0].id
	_check(gs.issue(AnswerC.new(id, false)) and gs.at_war("FRA", "GER") and events.back() == false, "the player refuses and the war goes on")
	_check(gs.pending_offers.is_empty() and gs.peace_cooldown.has("FRA|GER"), "the offer is gone and a cooldown is set")
	clock.paused = false
	_check(not clock.paused, "time can run again")
	clock.paused = true
	gs.peace_cooldown.clear()
	gs.issue(ProposeC.new("FRA", "GER", "demand", terms))
	id = gs.pending_offers[0].id
	_check(gs.issue(AnswerC.new(id, true)) and not gs.at_war("FRA", "GER") and events.back() == true, "or accepts, and peace is made")
	_check(gs.province_owner[terms[0].ids[0]] == "FRA", "on the terms offered")

	# The player proposes to an AI; the answer is immediate.
	war = _war()
	gs.set_player("FRA")
	var r: Dictionary = P.propose(gs, "FRA", "GER", "demand", [])
	_check(r.accepted == true, "the player's own white peace is answered at once")


func _test_separate_peace() -> void:
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	gs.join_calls.clear()
	gs.wars.clear()
	gs.set_player("ESP")
	gs.nations["GER"].mobilization = 0.5
	gs.issue(DeclareC.new("GER", "BEL", "none"))
	for i in 80:
		if gs.join_calls.is_empty():
			break
		clock.advance_day()
	_check(gs.at_war("RUS", "GER") and gs.at_war("FRA", "GER") and gs.at_war("RUS", "AUH"), "a general war is on")
	var group: int = gs.war_between("GER", "BEL").war_group
	var fra_rus: float = D.relation(gs, "FRA", "RUS")
	var r: Dictionary = P.propose(gs, "RUS", "GER", "demand", [])
	_check(r.accepted == true and not gs.at_war("RUS", "GER") and gs.at_war("RUS", "AUH"), "Russia makes a separate white peace with Germany only")
	_check(D.relation(gs, "RUS", "FRA") == fra_rus - 25.0, "France, still fighting, thinks worse of it (-25)")
	_check(gs.nations["RUS"].prestige == -5.0 * 1.0, "and it loses prestige")
	_check("RUS" in D.group_side(gs, group, "defend") and gs.at_war("FRA", "GER"), "Russia stays in the conflict against Austria-Hungary")
	P.propose(gs, "RUS", "AUH", "demand", [])
	_check(not gs.at_war("RUS", "AUH") and "RUS" not in D.group_side(gs, group, "defend"), "when its last enemy is gone it leaves the conflict")


func _test_overtures() -> void:
	var war = _war()
	_occupy("GER", "FRA", 200)
	_check(P.war_score(gs, war, "GER") <= -30.0, "Germany is losing badly (%.1f)" % P.war_score(gs, war, "GER"))
	var held_before := 0
	for id in range(1, gs.province_owner.size()):
		if gs.province_owner[id] == "GER" and gs.province_controller[id] == "FRA":
			held_before += 1
	P.step_month(gs)
	_check(not gs.at_war("FRA", "GER"), "a losing AI sues for peace and the winner takes it")
	var ceded := 0
	for id in range(1, gs.province_owner.size()):
		if gs.province_owner[id] == "FRA" and gs.nations["GER"].provinces.find(id) < 0 and id != 233:
			ceded += 1
	_check(held_before > 0 and war.peace.giver == "GER" and war.peace.terms.size() >= 1 and not war.peace.white, "France, far ahead, names its price in ground it holds (and perhaps an indemnity)")

	# A long stalemate ends in a white peace.
	war = _war()
	P.step_month(gs)
	_check(gs.at_war("FRA", "GER"), "a young war goes on")
	clock.days_elapsed += 1600
	P.step_month(gs)
	_check(not gs.at_war("FRA", "GER") and war.peace.white, "a stalemate of over four years ends in a white peace")

	# An offer to the player waits for them.
	war = _war()
	gs.set_player("FRA")
	_occupy("GER", "FRA", 200)
	P.step_month(gs)
	_check(gs.pending_offers.size() == 1 and gs.pending_offers[0].from == "GER" and gs.pending_offers[0].mode == "offer", "a losing AI's offer to the player is pending")
	_check(clock.paused and gs.pending_offers[0].taker == "FRA", "with time held")
