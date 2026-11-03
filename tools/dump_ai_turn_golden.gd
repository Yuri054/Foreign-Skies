extends SceneTree
## Writes what the AI's budget and focus do in the real game, for the Rust port (rust/fs_sim) to reproduce. The game's own day is driven here
## stage by stage (economy, focus, navy, armies, diplomacy, crises) with the parts of the AI's turn that are ported (AIBudget, without
## its navy, and AIFocus) in the place the game gives the AI, then the day's last stage; the rest of the AI's turn does nothing. Scenarios,
## some with wars begun and a front drawn for each side, run for hundreds of days; every few days the nations' policies, money, works,
## foci and the months of their last budget are written down. Floats are the bits of their 64-bit value.
##   godot --headless --path . -s res://tools/dump_ai_turn_golden.gd -- rust/fs_sim/tests/golden/ai_turn.json
##   gzip -9 -f rust/fs_sim/tests/golden/ai_turn.json    # the test reads ai_turn.json.gz (the plain file is over GitHub's size limit)

var gs: Node
var clock: Node
var Eco: GDScript
var Foc: GDScript
var Nav: GDScript
var Mil: GDScript
var Dip: GDScript
var Cri: GDScript
var AIc: GDScript
var AIB: GDScript
var AIF: GDScript
var AIFo: GDScript
var AIAm: GDScript
var AID: GDScript
var AIDip: GDScript
var AIO: GDScript
var AIN: GDScript
var AIL: GDScript
var parts: Array = []


func B(x: float) -> String:
	return str(PackedFloat64Array([x]).to_byte_array().decode_s64(0))


func _initialize() -> void:
	await process_frame
	var out_path: String = OS.get_cmdline_user_args()[0]
	gs = root.get_node("GameState")
	clock = root.get_node("Clock")
	Eco = load("res://scripts/sim/economy.gd")
	Foc = load("res://scripts/sim/focus.gd")
	Nav = load("res://scripts/sim/navy.gd")
	Mil = load("res://scripts/sim/military.gd")
	Dip = load("res://scripts/sim/diplomacy.gd")
	Cri = load("res://scripts/sim/crisis.gd")
	AIc = load("res://scripts/ai/ai.gd")
	AIB = load("res://scripts/ai/ai_budget.gd")
	AIF = load("res://scripts/ai/ai_focus.gd")
	AIFo = load("res://scripts/ai/ai_forces.gd")
	AIAm = load("res://scripts/ai/ai_ambition.gd")
	AID = load("res://scripts/ai/ai_defense.gd")
	AIDip = load("res://scripts/ai/ai_diplomacy.gd")
	AIO = load("res://scripts/ai/ai_offense.gd")
	AIN = load("res://scripts/ai/ai_navy.gd")
	AIL = load("res://scripts/ai/ai_landing.gd")
	var Design: GDScript = load("res://scripts/sim/designate_front.gd")
	clock.day_ticked.disconnect(gs._on_day_ticked)
	clock.day_ticked.connect(_day)
	var runs := [
		{"name": "july_1914", "dir": "res://data/scenarios/july_1914/", "days": 400, "every": 5, "player": "GER", "wars": []},
		{"name": "jan_1900", "dir": "res://data/scenarios/jan_1900/", "days": 500, "every": 5, "player": "GBR", "wars": []},
		{"name": "july_1914", "dir": "res://data/scenarios/july_1914/", "days": 300, "every": 5, "player": "POR", "wars": [["GER", "FRA"], ["ITA", "AUH"], ["RUS", "OTT"]]},
		{"name": "jan_1900", "dir": "res://data/scenarios/jan_1900/", "days": 400, "every": 5, "player": "USA", "wars": [["RUS", "OTT"], ["FRA", "GER"], ["GBR", "ESP"]]},
		# the treasuries thrown about (by a factor for each nation in tag order), so that every branch of the budget is tried
		{"name": "july_1914", "dir": "res://data/scenarios/july_1914/", "days": 500, "every": 5, "player": "GER", "wars": [], "purse": [-3.0, 0.1, 8.0, 40.0, 1.0, 0.0, 200.0]},
		{"name": "jan_1900", "dir": "res://data/scenarios/jan_1900/", "days": 700, "every": 5, "player": "GBR", "wars": [], "purse": [60.0, -5.0, 0.3, 12.0, 1.0, 3.0]},
		{"name": "july_1914", "dir": "res://data/scenarios/july_1914/", "days": 400, "every": 5, "player": "POR", "wars": [["GER", "FRA"], ["ITA", "AUH"], ["RUS", "OTT"]], "purse": [0.2, 30.0, -2.0, 5.0, 100.0]},
		{"name": "jan_1900", "dir": "res://data/scenarios/jan_1900/", "days": 1500, "every": 10, "player": "USA", "wars": [], "purse": [1.0]},
	]
	var ALL := ["forces", "budget", "focus", "ambition"]
	var LAX_D := {"diplomacy": {"war": {"declare_threshold": 0.4, "min_motive": 0.15, "truce_days": 200, "unjustified_odds": 1.3, "unjustified_min_aggression": 0.4}, "treaties": {"points_reserve": 5, "propose_threshold": 0.35, "improve_threshold": 0.2}}}
	var LAX_AD := {"ambition": {"threshold": 0.3, "start_delay_days": 0, "review_days": 30, "give_up_days": 150, "cooldown_days": 45, "odds_margin": 0.8, "min_aggression": 0.3}, "forces": {"demob_after_days": 20}, "diplomacy": LAX_D.diplomacy}
	var LAX := {"ambition": {"threshold": 0.3, "start_delay_days": 0, "review_days": 30, "give_up_days": 150, "cooldown_days": 45, "odds_margin": 0.8, "min_aggression": 0.3}, "forces": {"demob_after_days": 20}}
	runs.append_array([
		{"name": "july_1914", "dir": "res://data/scenarios/july_1914/", "days": 500, "every": 5, "player": "POR", "wars": [["GER", "FRA"], ["ITA", "AUH"], ["RUS", "OTT"]], "parts": ALL},
		{"name": "july_1914", "dir": "res://data/scenarios/july_1914/", "days": 800, "every": 10, "player": "GBR", "wars": [["AUH", "SRB"], ["GER", "RUS"]], "parts": ALL, "purse": [3.0, 0.5, 10.0, 1.0]},
		{"name": "jan_1900", "dir": "res://data/scenarios/jan_1900/", "days": 900, "every": 10, "player": "USA", "wars": [["RUS", "OTT"], ["FRA", "GER"]], "parts": ALL},
		{"name": "jan_1900", "dir": "res://data/scenarios/jan_1900/", "days": 1500, "every": 10, "player": "GBR", "wars": [], "parts": ALL, "pressure": true},
		{"name": "july_1914", "dir": "res://data/scenarios/july_1914/", "days": 900, "every": 10, "player": "SRB", "wars": [], "parts": ALL, "pressure": true},
		# the AI's ambition and demobilizing loosened, so that they are tried (the same numbers are set by the Rust test)
		{"name": "july_1914", "dir": "res://data/scenarios/july_1914/", "days": 800, "every": 10, "player": "GBR", "wars": [["GER", "FRA"], ["ITA", "AUH"]], "parts": ALL, "ai_cfg": LAX},
		{"name": "jan_1900", "dir": "res://data/scenarios/jan_1900/", "days": 1000, "every": 10, "player": "USA", "wars": [["RUS", "OTT"], ["FRA", "GER"]], "parts": ALL, "ai_cfg": LAX},
		{"name": "july_1914", "dir": "res://data/scenarios/july_1914/", "days": 700, "every": 10, "player": "SRB", "wars": [], "parts": ALL, "ai_cfg": LAX, "pressure": true},
		{"name": "jan_1900", "dir": "res://data/scenarios/jan_1900/", "days": 1200, "every": 10, "player": "GBR", "wars": [], "parts": ALL, "ai_cfg": LAX, "pressure": true, "purse": [2.0, 0.5, 20.0]},
		# armies sent to the enemy's border, so that there is a threat to weigh; and a stricter ambition
		{"name": "july_1914", "dir": "res://data/scenarios/july_1914/", "days": 400, "every": 5, "player": "POR", "wars": [["GER", "FRA"], ["ITA", "AUH"], ["RUS", "OTT"]], "parts": ALL,
				"orders": [["GER", "FRA", 6], ["FRA", "GER", 6], ["ITA", "AUH", 4], ["AUH", "ITA", 4], ["RUS", "OTT", 4], ["OTT", "RUS", 4]]},
		{"name": "july_1914", "dir": "res://data/scenarios/july_1914/", "days": 500, "every": 5, "player": "GBR", "wars": [["GER", "RUS"], ["AUH", "SRB"], ["FRA", "ITA"]], "parts": ALL, "purse": [2.0, 0.6, 6.0],
				"orders": [["GER", "RUS", 8], ["RUS", "GER", 8], ["AUH", "SRB", 4], ["SRB", "AUH", 4], ["FRA", "ITA", 4], ["ITA", "FRA", 4]]},
		{"name": "jan_1900", "dir": "res://data/scenarios/jan_1900/", "days": 600, "every": 10, "player": "USA", "wars": [["RUS", "OTT"], ["FRA", "GER"], ["GBR", "ESP"]], "parts": ALL,
				"orders": [["RUS", "OTT", 5], ["OTT", "RUS", 5], ["FRA", "GER", 5], ["GER", "FRA", 5]]},
		{"name": "jan_1900", "dir": "res://data/scenarios/jan_1900/", "days": 1100, "every": 10, "player": "GBR", "wars": [], "parts": ALL, "pressure": true,
				"ai_cfg": {"ambition": {"threshold": 0.7, "start_delay_days": 100, "review_days": 45, "odds_margin": 1.0, "min_aggression": 0.4}, "forces": {"demob_after_days": 60}}},
		# the ambition's score near its real threshold, where each weight can decide
		{"name": "july_1914", "dir": "res://data/scenarios/july_1914/", "days": 900, "every": 10, "player": "GBR", "wars": [["GER", "FRA"], ["AUH", "SRB"]], "parts": ["forces", "ambition"],
				"ai_cfg": {"ambition": {"threshold": 0.85, "start_delay_days": 0, "review_days": 30, "odds_margin": 1.0, "min_aggression": 0.4}, "forces": {"demob_after_days": 30}}},
		{"name": "jan_1900", "dir": "res://data/scenarios/jan_1900/", "days": 1500, "every": 10, "player": "USA", "wars": [["RUS", "OTT"]], "parts": ["forces", "ambition"], "pressure": true,
				"ai_cfg": {"ambition": {"threshold": 0.8, "start_delay_days": 0, "review_days": 30, "odds_margin": 0.9, "min_aggression": 0.4, "give_up_days": 200, "cooldown_days": 60}}},
		{"name": "jan_1900", "dir": "res://data/scenarios/jan_1900/", "days": 1500, "every": 10, "player": "FRA", "wars": [], "parts": ["forces", "ambition"], "purse": [1.0],
				"ai_cfg": {"ambition": {"threshold": 1.0, "start_delay_days": 0, "review_days": 20, "odds_margin": 0.8, "min_aggression": 0.3, "give_up_days": 150, "cooldown_days": 30}}},
		# the AI at war on the defensive: fronts drawn by the AI (or by hand), armies sent to the border, wars of many nations
		{"name": "july_1914", "dir": "res://data/scenarios/july_1914/", "days": 300, "every": 5, "player": "POR", "wars": [["GER", "FRA"], ["ITA", "AUH"], ["RUS", "OTT"]], "parts": ["defence", "forces"], "nofronts": true,
				"orders": [["GER", "FRA", 6], ["FRA", "GER", 6], ["ITA", "AUH", 4], ["AUH", "ITA", 4], ["RUS", "OTT", 4], ["OTT", "RUS", 4]]},
		{"name": "july_1914", "dir": "res://data/scenarios/july_1914/", "days": 400, "every": 5, "player": "GBR", "wars": [["GER", "RUS"], ["AUH", "SRB"], ["FRA", "ITA"], ["OTT", "GRE"]], "parts": ["defence", "forces", "budget"], "nofronts": true,
				"orders": [["GER", "RUS", 8], ["RUS", "GER", 8], ["AUH", "SRB", 4], ["SRB", "AUH", 4], ["FRA", "ITA", 4], ["ITA", "FRA", 4], ["OTT", "GRE", 3], ["GRE", "OTT", 3]]},
		{"name": "july_1914", "dir": "res://data/scenarios/july_1914/", "days": 300, "every": 5, "player": "SRB", "wars": [["GER", "FRA"], ["AUH", "SRB"], ["RUS", "AUH"]], "parts": ["defence", "forces", "budget", "focus"]},
		{"name": "jan_1900", "dir": "res://data/scenarios/jan_1900/", "days": 500, "every": 10, "player": "USA", "wars": [["RUS", "OTT"], ["FRA", "GER"], ["GBR", "ESP"]], "parts": ["defence", "forces"], "nofronts": true,
				"orders": [["RUS", "OTT", 5], ["OTT", "RUS", 5], ["FRA", "GER", 5], ["GER", "FRA", 5]]},
		{"name": "jan_1900", "dir": "res://data/scenarios/jan_1900/", "days": 700, "every": 10, "player": "GBR", "wars": [["FRA", "GER"], ["RUS", "AUH"], ["ITA", "OTT"], ["ESP", "POR"]], "parts": ["defence", "forces", "budget"], "purse": [3.0, 1.0, 0.4],
				"orders": [["FRA", "GER", 6], ["GER", "FRA", 6], ["RUS", "AUH", 6], ["AUH", "RUS", 6]]},
		# the AI's diplomacy: declaring wars, pressing demands, proposing treaties
		{"name": "july_1914", "dir": "res://data/scenarios/july_1914/", "days": 700, "every": 10, "player": "GBR", "wars": [], "parts": ["diplomacy", "forces", "defence", "budget", "focus", "ambition"], "pressure": true, "ai_cfg": LAX_AD},
		{"name": "jan_1900", "dir": "res://data/scenarios/jan_1900/", "days": 1300, "every": 10, "player": "USA", "wars": [], "parts": ["diplomacy", "forces", "defence", "budget", "focus", "ambition"], "pressure": true, "ai_cfg": LAX_AD},
		{"name": "july_1914", "dir": "res://data/scenarios/july_1914/", "days": 500, "every": 10, "player": "SRB", "wars": [], "parts": ["diplomacy", "forces", "defence"], "ai_cfg": LAX_D},
		{"name": "jan_1900", "dir": "res://data/scenarios/jan_1900/", "days": 900, "every": 10, "player": "GBR", "wars": [], "parts": ["diplomacy", "forces", "defence", "budget", "focus", "ambition"], "pressure": true},
		{"name": "july_1914", "dir": "res://data/scenarios/july_1914/", "days": 600, "every": 10, "player": "POR", "wars": [], "parts": ["diplomacy", "forces", "defence", "budget", "focus", "ambition"], "pressure": true},
		# 1900 with no tension gate, so that ambitions lead to demands and wars
		{"name": "jan_1900", "dir": "res://data/scenarios/jan_1900/", "days": 900, "every": 10, "player": "USA", "wars": [], "parts": ["diplomacy", "forces", "defence", "budget", "focus", "ambition"], "ai_cfg": LAX_AD},
		{"name": "jan_1900", "dir": "res://data/scenarios/jan_1900/", "days": 1100, "every": 10, "player": "FRA", "wars": [], "parts": ["diplomacy", "forces", "defence", "ambition"], "purse": [1.0], "ai_cfg": {"ambition": LAX_AD.ambition, "diplomacy": {"war": {"declare_threshold": 0.8, "min_motive": 0.3, "truce_days": 400, "unjustified_odds": 2.0}, "treaties": {"points_reserve": 15, "propose_threshold": 0.5}}}},
		# the AI on the attack
		{"name": "july_1914", "dir": "res://data/scenarios/july_1914/", "days": 300, "every": 5, "player": "POR", "wars": [["GER", "FRA"], ["ITA", "AUH"], ["RUS", "OTT"]], "parts": ["defence", "offence", "forces"], "nofronts": true,
				"orders": [["GER", "FRA", 6], ["FRA", "GER", 6], ["ITA", "AUH", 4], ["AUH", "ITA", 4], ["RUS", "OTT", 4], ["OTT", "RUS", 4]]},
		{"name": "july_1914", "dir": "res://data/scenarios/july_1914/", "days": 400, "every": 5, "player": "GBR", "wars": [["GER", "RUS"], ["AUH", "SRB"], ["FRA", "ITA"], ["OTT", "GRE"]], "parts": ["defence", "offence", "forces", "budget"], "nofronts": true, "ai_cfg": {"offense": {"min_utility": -5.0, "max_share": 2.0}}},
		{"name": "jan_1900", "dir": "res://data/scenarios/jan_1900/", "days": 600, "every": 10, "player": "USA", "wars": [["RUS", "OTT"], ["FRA", "GER"], ["GBR", "ESP"]], "parts": ["defence", "offence", "forces"], "nofronts": true},
		{"name": "july_1914", "dir": "res://data/scenarios/july_1914/", "days": 500, "every": 5, "player": "GBR", "wars": [["GER", "FRA"], ["AUH", "SRB"]], "parts": ["defence", "offence", "forces"], "nofronts": true,
				"groups": [["GER", "Rhine", 6, "FRA", false], ["FRA", "Alsace", 5, "GER", false], ["AUH", "Balkans", 5, "SRB", false]]},
		{"name": "july_1914", "dir": "res://data/scenarios/july_1914/", "days": 700, "every": 10, "player": "SRB", "wars": [], "parts": ["diplomacy", "forces", "defence", "offence", "budget", "focus", "ambition"], "pressure": true, "ai_cfg": LAX_AD},
		{"name": "jan_1900", "dir": "res://data/scenarios/jan_1900/", "days": 900, "every": 10, "player": "USA", "wars": [], "parts": ["diplomacy", "forces", "defence", "offence", "budget", "focus", "ambition"], "ai_cfg": LAX_AD},
		# the AI at sea
		{"name": "july_1914", "dir": "res://data/scenarios/july_1914/", "days": 400, "every": 5, "player": "POR", "wars": [["GBR", "GER"], ["FRA", "ITA"], ["RUS", "OTT"]], "parts": ["defence", "offence", "forces", "navy"], "nofronts": true,
				"orders": [["FRA", "ITA", 4], ["ITA", "FRA", 4], ["RUS", "OTT", 4], ["OTT", "RUS", 4]]},
		{"name": "july_1914", "dir": "res://data/scenarios/july_1914/", "days": 500, "every": 5, "player": "SRB", "wars": [["GBR", "GER"], ["GBR", "OTT"], ["FRA", "AUH"]], "parts": ["defence", "offence", "forces", "navy", "budget"], "nofronts": true, "purse": [3.0, 1.0, 0.5, 8.0],
				"ai_cfg": {"navy": {"landing": {"min_force": 1, "min_utility": -5.0}}}},
		{"name": "jan_1900", "dir": "res://data/scenarios/jan_1900/", "days": 500, "every": 10, "player": "USA", "wars": [["GBR", "FRA"], ["GER", "RUS"], ["ESP", "ITA"]], "parts": ["defence", "offence", "forces", "navy", "budget"], "nofronts": true},
		{"name": "july_1914", "dir": "res://data/scenarios/july_1914/", "days": 700, "every": 10, "player": "BEL", "wars": [], "parts": ["diplomacy", "forces", "defence", "offence", "navy", "budget", "focus", "ambition"], "pressure": true, "ai_cfg": LAX_AD},
		{"name": "jan_1900", "dir": "res://data/scenarios/jan_1900/", "days": 800, "every": 10, "player": "FRA", "wars": [], "parts": ["diplomacy", "forces", "defence", "offence", "navy", "budget", "focus", "ambition"], "ai_cfg": LAX_AD},
		# war plans put in by hand, so that what the AI does with a plan is tried
		{"name": "july_1914", "dir": "res://data/scenarios/july_1914/", "days": 400, "every": 5, "player": "POR", "wars": [["GER", "FRA"], ["AUH", "SRB"], ["RUS", "GER"]], "parts": ["defence", "offence", "forces", "diplomacy", "budget"], "nofronts": true,
				"plans": [["GER", "FRA", "offensive"], ["FRA", "GER", "defensive"], ["AUH", "SRB", "offensive"], ["RUS", "GER", "offensive"], ["SRB", "AUH", "defensive"]], "ai_cfg": LAX_D},
		{"name": "jan_1900", "dir": "res://data/scenarios/jan_1900/", "days": 600, "every": 10, "player": "USA", "wars": [["FRA", "GER"], ["RUS", "AUH"]], "parts": ["defence", "offence", "forces", "diplomacy"], "nofronts": true,
				"plans": [["FRA", "GER", "offensive"], ["GER", "FRA", "defensive"], ["RUS", "AUH", "offensive"], ["AUH", "RUS", "offensive"]], "ai_cfg": LAX_D},
		{"name": "july_1914", "dir": "res://data/scenarios/july_1914/", "days": 500, "every": 10, "player": "GBR", "wars": [], "parts": ["diplomacy", "forces", "defence", "offence", "budget", "ambition"], "pressure": true,
				"plans": [["GER", "FRA", "offensive"], ["AUH", "SRB", "offensive"], ["RUS", "OTT", "offensive"], ["ITA", "AUH", "offensive"], ["BUL", "SRB", "offensive"]], "ai_cfg": LAX_AD},
		{"name": "jan_1900", "dir": "res://data/scenarios/jan_1900/", "days": 700, "every": 10, "player": "USA", "wars": [], "parts": ["diplomacy", "forces", "defence", "offence", "budget", "ambition"],
				"plans": [["FRA", "GER", "offensive"], ["GER", "FRA", "offensive"], ["RUS", "AUH", "offensive"], ["AUH", "SRB", "offensive"], ["BUL", "OTT", "offensive"], ["ITA", "AUH", "offensive"]], "ai_cfg": LAX_AD},
	])
	var result := []
	for run in runs:
		gs.player_tag = ""
		gs.load_scenario(run.dir)
		gs.ai_enabled = false
		gs.pressure_ai = run.get("pressure", false)
		gs.set_player(run.player)
		parts = run.get("parts", ["budget", "focus"])
		AIc.load_config()
		for section in run.get("ai_cfg", {}):
			_merge(AIc.cfg[section], run.ai_cfg[section])
		var setup := []
		var purse: Array = run.get("purse", [])
		if not purse.is_empty():
			var tags: Array = gs.nations.keys()
			tags.sort()
			for i in tags.size():
				gs.nations[tags[i]].treasury *= purse[i % purse.size()]
		for w in run.wars:
			Dip.start_war(gs, w[0], w[1], true)
			for pair in ([] if run.get("nofronts", false) else [[w[0], w[1]], [w[1], w[0]]]):
				var cmd = Design.new(pair[0], "Front " + pair[1], [] as Array[int], pair[1], "line", 0)
				var ok: bool = cmd.execute(gs)
				setup.append([pair[0], pair[1], ok])
		var orders_log := []
		var MoveCmd: GDScript = load("res://scripts/sim/move_army.gd")
		for o in run.get("orders", []):
			var sent := 0
			for a in Mil.armies_of(gs, o[0]):
				if sent >= o[2]:
					break
				var target := _border_target(o[1], a.province, sent)
				if target == 0:
					continue
				var cmd = MoveCmd.new(o[0], a.id, target)
				var ok: bool = cmd.execute(gs)
				orders_log.append([o[0], a.id, target, ok])
				if ok:
					sent += 1
		var plans_log := []
		for pl in run.get("plans", []):
			var border: Array = Mil.border_provinces(gs, pl[1], pl[0])
			var objs: Array = []
			var enemy_border: Array = []
			for id in range(1, gs.province_owner.size()):
				if gs.province_owner[id] != pl[1]:
					continue
				for nb in Mil.neighbors(id):
					if gs.province_owner[nb] == pl[0]:
						enemy_border.append(id)
						break
			enemy_border.sort()
			var wts := [1.0, 2.0, 1.0]
			for i in mini(3, enemy_border.size()):
				objs.append({"province": enemy_border[i], "weight": wts[i]})
			var plan := {"nation": pl[0], "enemy": pl[1], "posture": pl[2], "objectives": objs}
			gs.ai_plans.append(plan)
			plans_log.append(plan)
		var groups_log := []
		var MkGroup: GDScript = load("res://scripts/sim/create_army_group.gd")
		var MkLine: GDScript = load("res://scripts/sim/create_attack_line.gd")
		var SetLine: GDScript = load("res://scripts/sim/set_attack_line.gd")
		for g in run.get("groups", []):
			var list: Array = Mil.armies_of(gs, g[0])
			var gids: Array[int] = []
			for i in mini(g[2], list.size()):
				gids.append(list[i].id)
			var mk = MkGroup.new(g[0], g[1], gids)
			var ok1: bool = mk.execute(gs)
			var fid := 0
			for f in gs.fronts.values():
				if f.tag == g[0] and f.against == g[3]:
					fid = f.id
			var ml = MkLine.new(g[0], mk.group_id, g[3], fid if g[4] else 0)
			var ok2: bool = ml.execute(gs)
			var sl = SetLine.new(g[0], ml.line_id, true)
			var ok3: bool = sl.execute(gs)
			groups_log.append([g[0], g[1], gids, ok1, mk.group_id, ok2, ml.line_id, ok3, fid if g[4] else 0, g[3]])
		var snaps := [_snapshot()]
		for d in run.days:
			clock.advance_day()
			if d % run.every == run.every - 1:
				snaps.append(_snapshot())
		result.append({"name": run.name, "player": run.player, "wars": run.wars, "purse": run.get("purse", []), "parts": run.get("parts", ["budget", "focus"]), "pressure": run.get("pressure", false), "ai_cfg": run.get("ai_cfg", {}), "setup": setup, "orders": orders_log, "groups": groups_log, "plans_set": plans_log, "every": run.every, "snaps": snaps})
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(result))
	f.close()
	print("wrote ", out_path)
	quit(0)


## The game's day (GameState._day_stage_list) with the ported parts of the AI's turn where the AI goes.
func _day() -> void:
	gs.finish_day()
	gs.in_day_step = true
	Eco.step_day(gs)
	Foc.step_day(gs)
	Nav.step_day(gs)
	Mil.step_day(gs)
	Dip.step_day(gs)
	Cri.step_day(gs)
	for tag in AIc.due_nations(gs):
		if "defence" in parts and not gs.wars_of(tag).is_empty():
			AID.step(gs, tag)
		if "offence" in parts and not gs.wars_of(tag).is_empty():
			AIO.step(gs, tag)
		if "forces" in parts:
			if not gs.wars_of(tag).is_empty():
				AIFo.step(gs, tag)
				if "navy" in parts:
					AIN.step(gs, tag)
					AIL.step(gs, tag)
			else:
				AIFo.rebuild(gs, tag)
				AIFo.demobilize(gs, tag)
		var stamp: int = clock.year * 12 + clock.month
		if "diplomacy" in parts:
			AIDip.step(gs, tag)
		if "budget" in parts and gs.ai_budget_stamp.get(tag, 0) != stamp and AIc.cfg.budget.enabled:
			gs.ai_budget_stamp[tag] = stamp
			AIB._buildings(gs, tag)
			AIB._army(gs, tag)
			if "navy" in parts:
				AIN.build(gs, tag)
			AIB._points(gs, tag)
		if "focus" in parts:
			AIF.step(gs, tag)
		if "ambition" in parts:
			AIAm.step(gs, tag)
	gs.in_day_step = false
	if gs.economy_dirty:
		gs.economy_dirty = false
		gs.budget_dirty = false
		Eco.recompute(gs)
	elif gs.budget_dirty:
		gs.budget_dirty = false
		Eco.refresh_now(gs)


func _snapshot() -> Dictionary:
	var nations := []
	for tag in gs.nations:
		var n = gs.nations[tag]
		var jobs := []
		for j in n.construction:
			jobs.append([j.province, j.type, j.days_left, 1 if j.started else 0])
		nations.append([B(n.treasury), B(n.cp), B(n.budget.get("income", 0.0)), B(n.budget.get("cp", 0.0)), B(n.naval_budget), B(n.diplomacy_points), B(n.prestige),
				B(n.mobilization), B(n.budget.get("net", 0.0)), jobs, n.focus.get("id", "") if not n.focus.is_empty() else "", n.focus_done.duplicate(),
				JSON.stringify(n.focus_count), gs.ai_budget_stamp.get(tag, 0), n.provinces.size()])
	var owners := []
	for id in range(1, gs.province_owner.size()):
		owners.append(gs.province_owner[id])
	var armies := []
	for a in gs.armies.values():
		armies.append([a.id, a.tag, a.province, B(a.men()), a.units.size(), a.path.size(), a.front_id, a.pin, a.parent_id, a.path.duplicate(), B(a.move_days_left), a.fleet_id])
	var recruiting := []
	for tag in gs.nations:
		recruiting.append(gs.nations[tag].recruiting.map(func(j): return [j.type, j.province, j.days_left]))
	var manpower := []
	for tag in gs.nations:
		manpower.append([gs.nations[tag].manpower, gs.nations[tag].men_in_units])
	var wars := []
	for w in gs.wars.values():
		wars.append([w.id, w.a, w.b])
	var fronts := []
	for f in gs.fronts.values():
		fronts.append([f.id, f.tag, f.against, f.provinces.duplicate(), f.anchors.duplicate(), f.army_ids.duplicate()])
	var controllers := []
	for id in range(1, gs.province_controller.size()):
		controllers.append(gs.province_controller[id])
	var camps := []
	for tag in gs.ai_campaign:
		var c: Dictionary = gs.ai_campaign[tag]
		camps.append([tag, "main", c.enemy, c.target, c.staging, c.armies.duplicate(), c.phase, c.started])
	for tag in gs.ai_campaign_extra:
		for c in gs.ai_campaign_extra[tag]:
			camps.append([tag, "extra", c.enemy, c.target, c.staging, c.armies.duplicate(), c.phase, c.started])
	var lines := []
	for l in gs.attack_lines.values():
		var lc: Dictionary = l.campaign
		lines.append([l.id, l.active, l.wait, [lc.enemy, lc.target, lc.staging, lc.armies.duplicate(), lc.phase, lc.started, lc.get("done", false)] if not lc.is_empty() else []])
	var fleets := []
	for f in gs.fleets.values():
		fleets.append([f.id, f.tag, f.display_name, f.port, f.zone, f.ships.map(func(sh): return [sh.type, B(sh.strength), B(sh.morale)]), f.path.duplicate(), f.dest_port, f.mission, f.landing, f.days_out, f.entering, f.fighting, f.retreating, B(f.move_days_left)])
	var navy_mem := {}
	for tag in gs.ai_navy:
		navy_mem[tag] = gs.ai_navy[tag].assign.duplicate()
	var landings := {}
	for tag in gs.ai_landing:
		var l: Dictionary = gs.ai_landing[tag]
		landings[tag] = [l.enemy, l.target, l.port, l.fleet, l.armies.duplicate(), l.phase, l.started, l.zone]
	var yards := []
	for tag in gs.nations:
		yards.append(gs.nations[tag].shipbuilding.map(func(j): return [j.type, j.province, j.days_left]))
	var treaties := []
	for t in gs.treaties:
		treaties.append([t.id, t.kind, t.a, t.b, t.start_day, t.end_day])
	var crises := []
	for c in gs.crises:
		crises.append([c.id, c.kind, c.a, c.b])
	var cbs := []
	for c in gs.casus_belli:
		cbs.append([c.holder, c.target, c.kind])
	var rel := {}
	for k in gs.relations:
		rel[k] = B(gs.relations[k])
	var grv := {}
	for k in gs.grievance:
		grv[k] = B(gs.grievance[k])
	return {"fleets_ai": fleets, "navy_mem": navy_mem, "landings": landings, "landing_wait": gs.ai_landing_wait.duplicate(), "navy_need": gs.ai_navy_need.duplicate(), "yards": yards, "controllers": controllers, "campaigns": camps, "campaign_wait": gs.ai_campaign_wait.duplicate(), "lines": lines, "treaties": treaties, "crises": crises, "cbs": cbs, "relations": rel, "grievance": grv, "declarations": [gs.ai_declarations.total, gs.ai_declarations.unjustified], "fronts": fronts, "reserve": gs.ai_reserve.duplicate(), "anchor_stamp": gs.ai_anchor_stamp.duplicate(), "day": clock.days_elapsed, "date": clock.date_string(), "nations": nations, "owners": owners, "tension": B(gs.tension), "armies": armies, "recruiting": recruiting,
			"manpower": manpower, "wars": wars, "ambition": gs.ai_ambition.duplicate(true), "ambition_wait": gs.ai_ambition_wait.duplicate(), "plans": JSON.stringify(gs.ai_plans)}


func _border_target(enemy: String, from: int, index: int) -> int:
	var seen := {from: 0}
	var queue := [from]
	var found := []
	while not queue.is_empty() and found.size() <= index + 1:
		var cur: int = queue.pop_front()
		if gs.province_owner[cur] == enemy and gs.province_controller[cur] == enemy:
			found.append(cur)
		for n in Mil.neighbors(cur):
			if not seen.has(n):
				seen[n] = seen[cur] + 1
				queue.append(n)
	return found[index] if found.size() > index else (found[0] if not found.is_empty() else 0)


func _merge(dst: Dictionary, src: Dictionary) -> void:
	for k in src:
		if src[k] is Dictionary and dst.get(k) is Dictionary:
			_merge(dst[k], src[k])
		else:
			dst[k] = src[k]
