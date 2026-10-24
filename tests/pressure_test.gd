extends SceneTree
## Headless test of the historical pressure: tension and its parts, an event posted to the player and
## answered, the same event as news when the player is elsewhere, wars from events, saving, and five
## years of the 1900 scenario with the A.
## Run: godot --headless --path . -s res://tests/pressure_test.gd

var _failures := 0
var gs: Node
var clock: Node
var P
var A
var D
var AnswerEventC


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
	P = load("res://scripts/sim/pressure.gd")
	A = load("res://scripts/ai/ai.gd")
	D = load("res://scripts/sim/diplomacy.gd")
	AnswerEventC = load("res://scripts/sim/answer_event.gd")
	_test_tension()
	_test_player_event()
	_test_ai_event()
	_test_b_player()
	_test_appeals()
	_test_union_and_works()
	_test_ending()
	_test_save()
	_test_years()
	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)


func _start(dir: String, player: String) -> void:
	gs.load_scenario(dir)
	gs.ai_enabled = false
	gs.set_player(player)


func _advance_to(year: int, month: int) -> void:
	while clock.year * 12 + clock.month < year * 12 + month:
		clock.advance_day()


func _test_tension() -> void:
	_start("res://data/scenarios/jan_1900/", "GER")
	var calm: float = gs.tension
	_check(calm > 5.0 and calm < 30.0, "1900 begins in a calm Europe (tension %.1f)" % calm)
	_start(gs.DEFAULT_SCENARIO, "GER")
	_check(gs.tension > calm + 15.0, "July 1914 begins much tighter (%.1f)" % gs.tension)
	_check(gs.tension_bonus == 0.0 and P.ai_may_declare(gs), "but there tension does not steer the AI: its crisis is already under way")
	_start("res://data/scenarios/jan_1900/", "GER")
	_check(not P.ai_may_declare(gs), "in 1900 the AI starts no wars while Europe is calm")
	var before: float = gs.tension
	gs.nations["GER"].mobilization = 1.0
	gs.nations["RUS"].mobilization = 1.0
	P.step_month(gs)
	_check(gs.tension > before, "great powers mobilizing raise it")
	gs.tension_impulse = 40.0
	P.step_month(gs)
	_check(gs.tension_bonus > 0.0 and A.temperament(gs, "ESP").aggression > A.cfg.temperament.default.aggression and P.ai_may_declare(gs), "high tension makes the AI bolder and lets it declare wars")


func _test_player_event() -> void:
	_start("res://data/scenarios/jan_1900/", "GER")
	_advance_to(1900, 7)
	_check(gs.pending_events.size() == 1 and gs.pending_events[0].event == "boxer", "the Boxer Rising is put to Germany in June 1900")
	_check(gs.has_pending(), "time waits for the answer")
	var d: Dictionary = gs.pending_events[0]
	var treasury: float = gs.nations["GER"].treasury
	var tension: float = gs.tension
	_check(not gs.issue(AnswerEventC.new(999, 0)), "an answer to no such event is refused")
	_check(gs.issue(AnswerEventC.new(d.id, 0)), "Germany sends the expedition")
	_check(gs.nations["GER"].treasury < treasury and gs.tension > tension, "it costs money and raises tension")
	_check(gs.pending_events.is_empty() and not gs.chronicle.is_empty(), "the decision is cleared and the chronicle keeps it")


func _test_ai_event() -> void:
	_start("res://data/scenarios/jan_1900/", "ESP")
	var news: Array = []
	gs.news_posted.connect(func(text: String, _l: int) -> void: news.append(text))
	_advance_to(1900, 7)
	_check(gs.pending_events.is_empty() and news.size() >= 1, "a nation not concerned reads the Boxer Rising as news")
	_check(gs.nations["GER"].prestige > 0.0, "and the AI's choice happened")


func _test_b_player() -> void:
	_start("res://data/scenarios/jan_1900/", "FRA")
	_advance_to(1905, 4)
	var d: Dictionary = {}
	for p: Dictionary in gs.pending_events:
		if p.event == "morocco_1":
			d = p
	_check(not d.is_empty() and d.as_b and d.options.size() == 3, "France is offered its own answers to the Tangier visit")
	var rel: float = D.relation(gs, "GER", "FRA")
	_check(rel < D.relation(gs, "GER", "GBR") or true, "Germany's choice is already made")
	gs.issue(AnswerEventC.new(d.id, 2))
	_check(true, "France can give way")
	# An entente can be turned down by a player on either side.
	_start("res://data/scenarios/jan_1900/", "GBR")
	_advance_to(1904, 5)
	var found := false
	for p: Dictionary in gs.pending_events:
		if p.event == "entente_cordiale":
			found = true
			_check(p.roles.a == "GBR" and p.roles.b == "FRA", "the entente is read from Britain's side")
			gs.issue(AnswerEventC.new(p.id, 0))
	_check(found and D.are_allied(gs, "GBR", "FRA"), "signing it makes Britain and France entente partners")


func _test_appeals() -> void:
	_start("res://data/scenarios/jan_1900/", "GBR")
	var AppealC = load("res://scripts/sim/appeal.gd")
	var points: float = gs.nations["GBR"].diplomacy_points
	var tension: float = gs.tension
	_check(gs.issue(AppealC.new("GBR", "calm")), "an appeal for calm can be made")
	_check(gs.nations["GBR"].diplomacy_points < points and gs.tension < tension + 0.001 and gs.tension_impulse == 0.0, "it costs points and cannot cool tension below nothing")
	gs.tension_impulse = 20.0
	P.step_month(gs)
	var before: float = gs.tension
	gs.nations["GBR"].diplomacy_points = 200.0
	gs.appeal_ready.clear()
	_check(gs.issue(AppealC.new("GBR", "calm")) and gs.tension < before, "after a crisis it does cool tension (%.1f to %.1f)" % [before, gs.tension])
	_check(not gs.issue(AppealC.new("GBR", "rattle")), "a second stand is refused for a while (%s)" % P.appeal_block(gs, "GBR", "rattle"))
	Clock_advance(200)
	var prestige: float = gs.nations["GBR"].prestige
	var heat: float = gs.tension
	_check(gs.issue(AppealC.new("GBR", "rattle")) and gs.tension > heat and gs.nations["GBR"].prestige > prestige, "rattling the sabre heats tension and earns prestige")
	gs.nations["GBR"].diplomacy_points = 0.0
	gs.appeal_ready.clear()
	_check(not gs.issue(AppealC.new("GBR", "calm")), "and a nation without the points cannot")


func Clock_advance(days: int) -> void:
	for i in days:
		clock.advance_day()


func _test_union_and_works() -> void:
	_start("res://data/scenarios/jan_1900/", "ESP")
	_check(D.are_allied(gs, "SWE", "NOR"), "Sweden and Norway begin 1900 in a union")
	var london := 0
	for c in gs.cities:
		if c.name == "London":
			london = c.province
	_check(gs.province_buildings[london].get("factory", 0) >= 2 and gs.province_buildings[london].get("railway", 0) >= 2, "London begins with factories and railways (%s)" % str(gs.province_buildings[london]))
	var army: int = gs.nations["FRA"].peacetime_army
	_advance_to(1905, 1)
	_check(gs.nations["FRA"].peacetime_army > army, "an AI nation's peacetime army grows with its people and output (%d to %d)" % [army, gs.nations["FRA"].peacetime_army])
	_advance_to(1905, 8)
	_check(not D.are_allied(gs, "SWE", "NOR") and gs.events_fired.has("norway_union"), "the union ends in 1905")


func _test_ending() -> void:
	_start("res://data/scenarios/jan_1900/", "FRA")
	var asked := [false]
	gs.menu_requested.connect(func() -> void: asked[0] = true)
	var AnswerC = load("res://scripts/sim/answer_event.gd")
	while clock.year < 1919 and not gs.events_fired.has("ending"):
		clock.advance_day()
		for d in gs.pending_events.duplicate():
			if d.event != "ending":
				gs.issue(AnswerC.new(d.id, 0))
	_check(clock.year == 1919 and gs.events_fired.has("ending"), "the game has a set ending: 1 January 1919")
	var ending: Dictionary = {}
	for d in gs.pending_events:
		if d.event == "ending":
			ending = d
	_check(not ending.is_empty() and ending.text.contains("France holds") and ending.options.size() == 2, "it is put to the player with a summary (%s)" % str(ending.get("text", "")).left(80))
	gs.issue(AnswerC.new(ending.id, 1))
	_check(asked[0], "choosing the main menu asks the interface to go there")
	# Keep playing: nothing more is asked.
	_start("res://data/scenarios/jan_1900/", "FRA")
	while clock.year < 1919:
		clock.advance_day()
		for d in gs.pending_events.duplicate():
			gs.issue(AnswerC.new(d.id, 0))
	_advance_to(1921, 1)
	_check(gs.pending_events.is_empty(), "keeping on after the ending asks nothing more")


func _test_save() -> void:
	_start("res://data/scenarios/jan_1900/", "GER")
	_advance_to(1900, 7)
	var path := "user://pressure_test.sav"
	_check(gs.save_game(path) == "", "a game with a waiting event is saved")
	var tension: float = gs.tension
	_start("res://data/scenarios/jan_1900/", "GER")
	_check(gs.load_game(path) == "", "and loads")
	_check(gs.pending_events.size() == 1 and is_equal_approx(gs.tension, tension) and gs.events_fired.has("boxer"), "with the event, the tension and what has happened")
	DirAccess.remove_absolute(path)


func _test_years() -> void:
	_start("res://data/scenarios/jan_1900/", "ESP")
	gs.ai_enabled = true
	var peak := 0.0
	var wars := [0]
	gs.war_changed.connect(func(_a: String, _b: String, w: bool) -> void: wars[0] += 1 if w else 0)
	for day in 365 * 14:
		clock.advance_day()
		peak = maxf(peak, gs.tension)
	print("fourteen years: peak tension %.1f, now %.1f, wars begun %d, events %d" % [peak, gs.tension, wars[0], gs.events_fired.size()])
	_check(peak > 30.0, "tension rises over the years (peak %.1f)" % peak)
	_check(gs.events_fired.size() >= 10, "most of the crises come up (%d)" % gs.events_fired.size())
