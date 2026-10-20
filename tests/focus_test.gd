extends SceneTree
## Headless test for national foci: trees for every nation, starting and finishing, each kind of
## effect, requirements, the AI's choices, saves and the window.
## Run: godot --headless --path . -s res://tests/focus_test.gd

var _failures := 0
var gs: Node
var clock: Node


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", msg)
	else:
		print("ok:   ", msg)


func _fresh() -> void:
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	gs.set_player("ESP")
	gs.ai_enabled = false


func _finish(tag: String, id: String) -> void:
	assert(gs.issue(load("res://scripts/sim/set_focus.gd").new(tag, id)))
	gs.nations[tag].focus.days_left = 1
	clock.advance_day()


func _initialize() -> void:
	await process_frame
	gs = root.get_node("GameState")
	clock = root.get_node("Clock")
	var F = load("res://scripts/sim/focus.gd")
	var D = load("res://scripts/sim/diplomacy.gd")
	var Set = load("res://scripts/sim/set_focus.gd")
	_fresh()
	# Every nation has a tree whose requirements exist and whose ids are unique.
	var sane := true
	for tag in gs.nations:
		var tree: Array = F.tree_of(tag)
		var ids := {}
		for f: Dictionary in tree:
			sane = sane and not ids.has(f.id) and f.days > 0 and not f.effects.is_empty()
			ids[f.id] = true
		for f: Dictionary in tree:
			for req in f.requires:
				sane = sane and ids.has(req)
		_check(tree.size() >= 4, "%s has a tree of %d foci" % [tag, tree.size()])
	_check(sane, "every tree is well formed")
	_check(F.tree_of("GER").size() > F.tree_of("LUX").size(), "a great power has a bigger tree than Luxembourg")

	# Starting, requirements, one at a time.
	var n = gs.nations["FRA"]
	var cmd = Set.new("FRA", "heavy_industry")
	_check(not gs.issue(cmd) and cmd.reason == "locked", "a focus whose requirement is not done is locked")
	_check(gs.issue(Set.new("FRA", "industrial_drive")), "France starts the industrial drive")
	_check(not gs.issue(Set.new("FRA", "agrarian_reform")) and F.block(gs, "FRA", "agrarian_reform") == "busy", "only one at a time")
	var days: int = n.focus.days_left
	clock.advance_day()
	_check(n.focus.days_left == days - 1, "a day passes on it")
	_check(gs.issue(Set.new("FRA", "")) and n.focus.is_empty(), "it can be dropped")
	# Lasting effects: output.
	_fresh()
	n = gs.nations["FRA"]
	var gdp: float = n.budget.gdp
	_finish("FRA", "industrial_drive")
	_check("industrial_drive" in n.focus_done and n.focus.is_empty(), "the focus is done after its days")
	_check(n.budget.gdp > gdp * 1.03, "output rises (%.1f to %.1f)" % [gdp, n.budget.gdp])
	_check(F.block(gs, "FRA", "industrial_drive") == "done", "and cannot be taken again")
	var ic: float = n.budget.construction_points
	_finish("FRA", "heavy_industry")
	_check(n.budget.construction_points >= ic + 6.0, "heavy industry adds construction capacity (%.0f to %.0f)" % [ic, n.budget.construction_points])
	var food: float = n.budget.food_production
	_finish("FRA", "agrarian_reform")
	_check(n.budget.food_production > food * 1.05, "agrarian reform feeds more people")
	var income: float = D.point_income(gs, "FRA")
	_finish("FRA", "army_reform")
	_finish("FRA", "diplomatic_corps")
	_check(D.point_income(gs, "FRA") >= income + 0.99, "the diplomatic corps adds a point a month")
	# One-off effects.
	var prestige: float = n.prestige
	_finish("FRA", "great_power_standing")
	_check(n.prestige > prestige + 7.0, "great-power standing adds prestige")
	_fresh()
	n = gs.nations["SRB"]
	var army: int = n.peacetime_army
	_finish("SRB", "modernise_army")
	_check(n.peacetime_army == int(round(army * 1.1)) + (0 if true else 0) or n.peacetime_army > army, "modernising grows the peacetime army (%d to %d)" % [army, n.peacetime_army])
	var support: float = n.war_support
	_finish("SRB", "greater_serbia")
	_check(D.casus_belli_options(gs, "SRB", "AUH").has("national_claim") or D.casus_belli_options(gs, "SRB", "AUH")[0] == "national_claim", "Greater Serbia gives a claim on Austria-Hungary")
	_check(n.war_support > support, "and war support")
	_fresh()
	var rel: float = D.relation(gs, "RUS", "SRB")
	_finish("RUS", "army_reform")
	_finish("RUS", "diplomatic_corps")
	_finish("RUS", "pan_slav_patron")
	_check(D.relation(gs, "RUS", "SRB") > rel + 20.0, "patronage warms Serbia (%.0f to %.0f)" % [rel, D.relation(gs, "RUS", "SRB")])
	_fresh()
	var pts: float = gs.nations["BEL"].diplomacy_points
	F.apply_effects(gs, "BEL", {"points": 12, "treasury": 3.0})
	_check(gs.nations["BEL"].diplomacy_points == pts + 12.0, "points and money effects apply")

	# Saves keep it.
	_fresh()
	_finish("DEN", "administrative_reform")
	gs.issue(Set.new("DEN", "farm_cooperatives"))
	var save = load("res://scripts/sim/save_game.gd")
	var path := "user://test_focus.sav"
	save.write(gs, path)
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	_check(gs.nations["DEN"].focus_done.is_empty(), "a fresh game has no foci done")
	save.read(gs, path)
	DirAccess.remove_absolute(path)
	_check("administrative_reform" in gs.nations["DEN"].focus_done and gs.nations["DEN"].focus.id == "farm_cooperatives" and gs.nations["DEN"].focus_fx.get("gdp", 0.0) > 0.0, "a loaded save keeps the foci, the one in hand and their effects")

	# The AI picks, finishes and moves on.
	_fresh()
	gs.ai_enabled = true
	var AF = load("res://scripts/ai/ai_focus.gd")
	AF.step(gs, "NED")
	_check(not gs.nations["NED"].focus.is_empty(), "an AI nation takes up a focus")
	for i in 400:
		clock.advance_day()
	var tally := 0
	for tag in gs.nations:
		tally += gs.nations[tag].focus_done.size()
	_check(tally >= 22 * 3, "after 400 days the AI nations have finished %d foci" % tally)
	var calm = gs.nations["NED"]
	_check(calm.focus_done.size() >= 3, "a quiet nation works through its tree (%d done)" % calm.focus_done.size())

	# The window.
	_fresh()
	var win = load("res://scripts/ui/focus_panel.gd").new()
	root.add_child(win)
	await process_frame
	gs.set_player("GBR")
	win.toggle()
	await process_frame
	_check(win._buttons.size() == F.tree_of("GBR").size(), "the window shows every focus of the tree (%d)" % win._buttons.size())
	win.select("industrial_drive")
	_check(not win._start.disabled, "an open focus can be started from it")
	win._on_start()
	_check(not gs.nations["GBR"].focus.is_empty() and gs.nations["GBR"].focus.id == "industrial_drive", "Start begins it")
	win.select("heavy_industry")
	_check(win._start.disabled and win._detail.text.contains("Needs"), "a locked one says what it needs")
	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)
