extends SceneTree
## Writes the figures the Rust port (rust/fs_sim) is tested against: what the GDScript simulation gives for a grid of
## inputs, with every float as the bits of its 64-bit value so that nothing is lost in the text.
##   godot --headless --path . -s res://tools/dump_sim_golden.gd -- rust/fs_sim/tests/golden/slice.json
## It covers Clock (the calendar), Economy (province output, modifiers, tax, growth, workers, building costs) and
## Population's rounding. Add a section here for each system that is ported, and a test for it in rust/fs_sim/tests.


class FakeState extends Node:
	var province_buildings: Array = []
	var province_gdp := PackedFloat32Array()
	var province_industry := PackedFloat32Array()
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
	print("section modifiers")
	golden["modifiers"] = _modifiers()
	print("section province_output")
	golden["province_output"] = _province_output()
	print("section growth")
	golden["growth"] = _growth()
	print("section worker_share")
	golden["worker_share"] = _worker_share()
	print("section building_cost")
	golden["building_cost"] = _building_cost()
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


func _fx_cases() -> Array:
	return [{}, {"gdp": 0.1}, {"gdp": 0.1, "industry": 0.05, "food": 0.02, "trade": 0.01, "growth": 0.003},
			{"growth": 0.006, "industry": -0.02}]


func _building_sets() -> Array:
	return [{}, {"factory": 3, "railway": 2}, {"port": 2, "factory": 1, "railway": 8},
			{"railway": 1, "factory": 10, "port": 5, "trench": 4, "fortification": 2}]


func _bits_dict(d: Dictionary) -> Dictionary:
	var r := {}
	for k in d:
		r[k] = B(d[k])
	return r


func _modifiers() -> Array:
	var rows := []
	for b in _building_sets():
		for fx in _fx_cases():
			var m: Dictionary = Eco.modifiers(b, fx)
			# the order the buildings were given in matters to the sum: keep it
			rows.append({"buildings": b.keys().map(func(k: String) -> Array: return [k, b[k]]), "fx": _bits_dict(fx), "out": _bits_dict(m)})
	return rows


func _province_output() -> Array:
	var rows := []
	var deposits := [{}, {"coal": 40.0}, {"coal": 120.0, "iron": 300.0, "wood": 60.0}, {"wood": 50.0, "iron": 49.999}]
	for pop in [0, 1000, 50000, 500000, 3000000]:
		for area in [0.5, 50.0, 800.0, 5000.0, 30000.0]:
			for dev in [0.7, 1.0, 1.6]:
				for agri in [0.8, 1.3]:
					for fx in _fx_cases():
						var bi: int = (pop + int(area)) % 4
						var di: int = (pop / 1000 + int(dev * 10.0)) % 4
						var n = NationCls.new("TST", {"name": "Test", "color": Color.WHITE}, {})
						n.development = dev
						n.agri_yield = agri
						n.focus_fx = fx
						var b: Dictionary = _building_sets()[bi]
						var d: Dictionary = deposits[di]
						var o: Dictionary = Eco.province_output(pop, area, n, b, d)
						rows.append({"pop": pop, "area": B(area), "dev": B(dev), "agri": B(agri), "fx": _bits_dict(fx),
								"buildings": b.keys().map(func(k: String) -> Array: return [k, b[k]]), "deposit": _bits_dict(d),
								"out": _bits_dict(o)})
	return rows


func _growth() -> Array:
	var rows := []
	for rate in [0.0, 0.04, 0.05, 0.075, 0.1, 0.1000001, 0.2, 0.4, 0.5]:
		for invest in [0.0, 0.5, 2.0, 10.0, 60.0]:
			for gdp in [-1.0, 0.0, 0.001, 500.0, 5000.0]:
				for fx in _fx_cases():
					var n = NationCls.new("TST", {"name": "Test", "color": Color.WHITE}, {})
					n.tax_rate = rate
					n.investment = invest
					n.focus_fx = fx
					var has_gdp: bool = gdp >= 0.0
					if has_gdp:
						n.budget = {"gdp": gdp}
					rows.append({"rate": B(rate), "invest": B(invest), "gdp": B(gdp) if has_gdp else "", "fx": _bits_dict(fx),
							"strain": B(Eco.tax_strain(n)), "relief": B(Eco.tax_relief(n)),
							"investment_growth": B(Eco.investment_growth(n)), "growth_rate": B(Eco.growth_rate(n))})
	return rows


func _worker_share() -> Array:
	var rows := []
	for men in [0, 1000, 500000, 5000000, 90000000]:
		for pop in [0, 1, 400000, 8000000, 60000000]:
			for weary in [0.0, 0.1, 0.4, 1.5]:
				for starving in [false, true]:
					var n = NationCls.new("TST", {"name": "Test", "color": Color.WHITE}, {})
					n.men_in_units = men
					n.population = pop
					n.weariness = weary
					n.starving = starving
					rows.append({"men": men, "pop": pop, "weariness": B(weary), "starving": 1 if starving else 0, "share": B(Eco.worker_share(n))})
	return rows


func _building_cost() -> Array:
	var rows := []
	var gs := FakeState.new()
	var gdps := [0.0, 0.3, 4.0, 14.9, 15.0, 80.0]
	var inds := [0.0, 0.5, 6.0, 19.9, 20.0, 150.0]
	gs.province_gdp.resize(gdps.size() + 1)
	gs.province_industry.resize(inds.size() + 1)
	for i in gdps.size():
		gs.province_gdp[i + 1] = gdps[i]
		gs.province_industry[i + 1] = inds[i]
	for type in Eco.building_ids():
		for level in range(0, 11):
			for i in gdps.size():
				var id := i + 1
				gs.province_buildings = []
				for j in gdps.size() + 1:
					gs.province_buildings.append({type: level} if level > 0 else {})
				var plan: Dictionary = Eco.build_plan(gs, id, type)
				rows.append({"type": type, "level": level,
						"gdp": B(gs.province_gdp[id]), "industry": B(gs.province_industry[id]),
						"size_factor": B(Eco.size_factor(gs, id, type)), "level_cost": B(Eco.level_cost(gs, id, type)),
						"ic": B(plan.ic), "days": plan.days, "gold": B(plan.gold), "total": B(plan.total)})
	# an id outside the arrays costs the full price
	gs.province_buildings = [{}, {}]
	rows.append({"type": "factory", "level": 0, "gdp": B(0.0), "industry": B(0.0), "outside": 1,
			"size_factor": B(Eco.size_factor(gs, 99, "factory"))})
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
				var whole: float = Pop._add(gs, 1, d)
				steps.append({"delta": B(d), "whole": B(whole), "pop": gs.province_population[1], "frac": B(gs.province_pop_frac[1])})
		rows.append({"start": start, "steps": steps})
		gs.free()
	return rows
