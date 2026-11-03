extends SceneTree
## Writes the figures the Rust port (rust/fs_sim) is tested against: what the GDScript simulation gives for a grid of
## inputs, with every float as the bits of its 64-bit value so that nothing is lost in the text.
##   godot --headless --path . -s res://tools/dump_sim_golden.gd -- rust/fs_sim/tests/golden/slice.json
## It covers Clock (the calendar), Economy (base income, building plans, a nation's budget from its sums) and
## Population's rounding. Add a section here for each system that is ported, and a test for it in rust/fs_sim/tests.


class FakeState extends Node:
	var province_controller: PackedStringArray = []
	var province_population := PackedInt32Array()
	var province_pop_frac := PackedFloat32Array()


## A float as the decimal text of its IEEE bits (JSON numbers cannot hold a 64-bit integer exactly).
func B(x: float) -> String:
	return str(PackedFloat64Array([x]).to_byte_array().decode_s64(0))


## The sim's classes are loaded when the script runs: a script given to -s is compiled before the autoloads they name exist.
var Eco: GDScript
var NationCls: GDScript
var Pop: GDScript


func _initialize() -> void:
	await process_frame
	Eco = load("res://scripts/sim/economy.gd")
	NationCls = load("res://scripts/sim/nation.gd")
	Pop = load("res://scripts/sim/population.gd")
	var out_path: String = OS.get_cmdline_user_args()[0]
	Eco.load_config()
	var golden := {}
	print("section clock_days_in_month")
	golden["clock_days_in_month"] = _clock_days()
	print("section clock_run")
	golden["clock_run"] = _clock_run()
	print("section clock_date_after")
	golden["clock_date_after"] = _clock_date_after()
	print("section base_income")
	golden["base_income"] = _base_income()
	print("section build_plan")
	golden["build_plan"] = _build_plan()
	print("section budget")
	golden["budget"] = _budget()
	print("section population_add")
	golden["population_add"] = _population_add()
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(golden))
	f.close()
	print("wrote ", out_path)
	quit(0)


func _clock_days() -> Array:
	var rows := []
	for y in [1, 1896, 1899, 1900, 1904, 1908, 1914, 1996, 2000, 2024, 2100, 2400]:
		for m in range(1, 13):
			rows.append([y, m, load("res://scripts/sim/clock.gd").days_in_month(y, m)])
	return rows


func _clock_run() -> Dictionary:
	var clock: Node = load("res://scripts/sim/clock.gd").new()
	var rows := []
	for start in [[1914, 7, 28], [1900, 1, 1], [1899, 12, 31], [1999, 2, 27]]:
		clock.start(start[0], start[1], start[2])
		var track := []
		for i in 1500:
			var before_month: int = clock.month
			var before_year: int = clock.year
			clock.advance_day()
			track.append([clock.year, clock.month, clock.day, clock.days_elapsed,
					1 if clock.month != before_month else 0, 1 if clock.year != before_year else 0])
		rows.append({"start": start, "days": track})
	clock.free()
	return {"runs": rows}


func _clock_date_after() -> Array:
	var clock: Node = load("res://scripts/sim/clock.gd").new()
	var rows := []
	for start in [[1914, 7, 28], [1900, 1, 1], [1899, 12, 31], [1900, 2, 28], [1999, 2, 27]]:
		for offset in [0, 1, 3, 31, 100, 365, 366, 1000, 5000]:
			clock.year = start[0]
			clock.month = start[1]
			clock.day = start[2]
			rows.append([start[0], start[1], start[2], offset, clock.date_after(offset)])
		clock.year = start[0]
		clock.month = start[1]
		clock.day = start[2]
		rows.append([start[0], start[1], start[2], -1, clock.date_string()])
	clock.free()
	return rows


func _bits_dict(d: Dictionary) -> Dictionary:
	var r := {}
	for k in d:
		if d[k] is float:
			r[k] = B(d[k])
	return r


func _base_income() -> Array:
	var rows := []
	for pop in [0.0, 1.0, 999.0, 1000.0, 54321.0, 250000.0, 830500.0, 1000000.0, 2880000.0, 7250000.0, 12345678.0]:
		rows.append({"pop": B(pop), "income": B(Eco.base_income(pop))})
	return rows


func _build_plan() -> Array:
	var rows := []
	for type in Eco.building_ids():
		var plan: Dictionary = Eco.build_plan(null, 0, type)
		rows.append({"type": type, "gold": B(plan.gold), "cp": B(plan.cp), "days": plan.days})
	return rows


## Nation_budget over a grid of sums and nation states. The capital is province 1; `held` says whether the nation holds it.
func _budget() -> Array:
	var rows := []
	var gs := FakeState.new()
	gs.province_controller = PackedStringArray(["", "TST", "XXX"])
	var sums := [{}, {"base": 6.3, "factories": 18.0, "ports": 0.3, "occupied": 0.0, "upkeep": 0.77, "cp": 3.0, "pool": 7680000.0},
			{"base": 0.6123, "factories": 1.5, "ports": 0.0, "occupied": 1.25, "upkeep": 0.07, "cp": 1.0, "pool": 540000.0},
			{"base": 12.7, "factories": 9.0, "ports": 2.4, "occupied": 0.333, "upkeep": 1.234, "cp": 2.0, "pool": 15000000.0}]
	var k := 0
	for raw: Dictionary in sums:
		for mob in [0.0, 0.4, 1.0]:
			for blockade in [0.0, 0.5, 1.0]:
				for war_mult in [1.0, 0.72]:
					for held in [true, false]:
						k += 1
						var n = NationCls.new("TST", {"name": "Test", "color": Color.WHITE}, {})
						n.mobilization = mob
						n.blockade = blockade
						n.capital = 1 if held else 2
						n.treasury = [50.0, -120.0, 0.0][k % 3]
						n.peacetime_army = [0, 300000, 9000000][k % 3]
						n.naval_budget = [0.0, 23.5][k % 2]
						n.focus_fx = [{}, {"income": 0.1, "cp": 0.5}][k % 2]
						var army: float = [0.0, 3.25, 9.75][k % 3]
						var b: Dictionary = Eco.nation_budget(gs, n, raw, war_mult, army)
						rows.append({"raw": _bits_dict(raw), "mobilization": B(mob), "blockade": B(blockade), "war_mult": B(war_mult),
								"capital": n.capital, "treasury": B(n.treasury), "peacetime_army": n.peacetime_army,
								"naval_budget": B(n.naval_budget), "fx": _bits_dict(n.focus_fx), "army": B(army), "out": _bits_dict(b)})
	gs.free()
	return rows


func _population_add() -> Array:
	var rows := []
	var deltas := [123.4, -50.25, 0.6, 0.6, -0.7, 999.99, -2500.0, 3.3333333, -1e6, 1e6, 0.0, -0.5, 0.5, 12345.678, -12345.678]
	for start in [1000, 1500, 25000, 2000000]:
		var gs := FakeState.new()
		gs.province_population.resize(2)
		gs.province_pop_frac.resize(2)
		gs.province_population[1] = start
		var steps := []
		for rep in 3:
			for d in deltas:
				Pop._add(gs, 1, d)
				steps.append({"delta": B(d), "pop": gs.province_population[1], "frac": B(gs.province_pop_frac[1])})
		rows.append({"start": start, "steps": steps})
		gs.free()
	return rows
