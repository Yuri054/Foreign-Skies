class_name Flows
extends RefCounted
## Daily resource flows. Every nation makes some of each resource and uses some (industry,
## homes, railways, the equipment lines, building works, the army's animals and medical stores).
## A nation's surplus can be exported; a shortfall is made good first from the stockpile (coal
## and chemicals only), then by automatic imports: from nations that have a surplus and are not at
## war with it, and from the world outside the map for a nation with a coast. Imports are not free:
## each locks civilian factories at the resource's trade rate (units a day per factory), so trade
## takes construction capacity. A blockade cuts what gets through. What cannot be had is a
## shortage, and a resource's `max_penalty` says how hard a total shortage hits what it powers.
##
## Figures are kt a year, as everywhere in Economy; one unit a day is 1,000 kt a year.


static func cfg() -> Dictionary:
	return Economy.cfg.flows


## Units a day for a figure in kt a year.
static func units(r: String, kt_year: float) -> float:
	return kt_year * float(Economy.cfg.resources[r].units_per_kt)


## kt a year for units a day.
static func kt(r: String, units_day: float) -> float:
	return units_day / float(Economy.cfg.resources[r].units_per_kt)


## What a nation uses of each resource beyond its industry and homes, in kt a year, by use:
## {resource: {"buildings", "lines", "works", "army"}}.
static func extra_uses(n: Nation, raw: Dictionary) -> Dictionary:
	var out := {}
	for r in Economy.resource_ids():
		out[r] = {"buildings": float(raw.get("use_" + r, 0.0)), "lines": 0.0, "works": 0.0, "army": 0.0}
	var lines := Production.planned_materials(n)
	for key: String in lines:
		if out.has(key):
			out[key].lines = float(lines[key])
	# Building works consume materials in step with the IC they take in each day.
	for job in n.construction:
		var mats: Dictionary = Economy.cfg.buildings[job.type].get("materials", {})
		for r: String in mats:
			if out.has(r):
				out[r].works += kt(r, float(job.get("given", 0.0)) * float(mats[r]))
	out["chemicals"].army += float(n.total_men()) * float(cfg().chem_per_man)
	out["draft_animals"].army += n.animal_need
	return out


## Solves every nation. `raws` maps tag to the summed province output (Economy.recompute).
## Returns {tag: {"res": {resource: info}, "lock": civilian factories locked by trade,
## "free": civilian factories left for building}}.
static func solve(gs: Node, raws: Dictionary) -> Dictionary:
	var tags: Array = gs.nations.keys()
	tags.sort()
	var out := {}
	for tag: String in tags:
		out[tag] = _balance(gs.nations[tag], raws[tag])
	_trade(gs, tags, out, raws)
	return out


## One nation's production, demand and balance before any trade.
static func _balance(n: Nation, raw: Dictionary) -> Dictionary:
	var mob_mult: float = 1.0 - Economy.cfg.mobilization_output_penalty * n.mobilization
	var uses := extra_uses(n, raw)
	var res := {}
	for r in Economy.resource_ids():
		var def: Dictionary = Economy.cfg.resources[r]
		var production: float = float(raw[r]) * mob_mult
		var from_industry: float = float(raw.industry) * def.industry_demand * n.intensity.get(r, 1.0)
		var from_homes: float = n.population * def.pop_demand * n.intensity.get(r, 1.0)
		var u: Dictionary = uses[r]
		var demand: float = from_industry + from_homes + u.buildings + u.lines + u.works + u.army
		var balance := production - demand
		var saves: bool = def.stockpile
		var cap: float = demand * float(cfg().stockpile_days) / 365.0 if saves else 0.0
		var stock: float = n.stock.get(r, 0.0) if saves else 0.0
		var info := {"production": production, "demand": demand, "balance": balance, "stock": stock, "cap": cap,
				"exported": 0.0, "imported": 0.0, "fill": 0.0, "draw": 0.0, "shortage": 0.0, "need": 0.0, "surplus": 0.0,
				"from_industry": from_industry, "from_homes": from_homes, "from_buildings": u.buildings,
				"from_lines": u.lines, "from_works": u.works, "from_army": u.army,
				"cost_industry": 0.0, "cost_gdp": 0.0, "mult": 1.0, "cic": 0.0}
		if balance >= 0.0:
			if saves and stock < cap:
				info.fill = minf((cap - stock) * 365.0, balance)
			info.surplus = balance - info.fill
		else:
			info.need = -balance
		res[r] = info
	return {"res": res, "lock": 0.0, "free": 0.0}


## Automatic trade. Importers are served in tag order, resources in file order, so the result is
## the same each time.
static func _trade(gs: Node, tags: Array, out: Dictionary, raws: Dictionary) -> void:
	var overseas := {}
	for r: String in cfg().overseas:
		overseas[r] = float(cfg().overseas[r])
	for tag: String in tags:
		var n: Nation = gs.nations[tag]
		var raw: Dictionary = raws[tag]
		var entry: Dictionary = out[tag]
		var free := maxf(float(cfg().min_trade_factories), float(raw.factories) * (1.0 - Economy.consumer_share(n)))
		var throughput := 1.0 - n.blockade
		var coastal: bool = float(raw.get("coast", 0.0)) > 0.0
		if not coastal:
			# A landlocked nation is supplied from overseas through a friendly neighbour's ports.
			for other: String in Diplomacy.neighbor_nations(gs, tag):
				if raws.has(other) and float(raws[other].get("coast", 0.0)) > 0.0 and not gs.at_war(tag, other):
					coastal = true
					break
		for r in Economy.resource_ids():
			var info: Dictionary = entry.res[r]
			var def: Dictionary = Economy.cfg.resources[r]
			if info.need > 0.0:
				var want := units(r, info.need) * throughput
				want = minf(want, free * float(def.trade_rate))
				var got := 0.0
				# Nations with a surplus that are not at war with this one, the biggest first.
				var sellers: Array = []
				for other: String in tags:
					if other != tag and out[other].res[r].surplus > 0.0 and not gs.at_war(tag, other):
						sellers.append(other)
				sellers.sort_custom(func(a: String, b: String) -> bool:
					var sa: float = out[a].res[r].surplus
					var sb: float = out[b].res[r].surplus
					return sa > sb or (sa == sb and a < b))
				for other: String in sellers:
					if want - got <= 0.0001:
						break
					var seller: Dictionary = out[other].res[r]
					var ready: float = units(r, seller.surplus) * (1.0 - gs.nations[other].blockade)
					var take := minf(want - got, ready)
					if take <= 0.0:
						continue
					got += take
					seller.exported += kt(r, take)
					seller.surplus = maxf(0.0, seller.surplus - kt(r, take))
				if coastal and overseas.has(r) and want - got > 0.0001:
					var pool: float = overseas[r]
					var take2 := want - got if pool < 0.0 else minf(want - got, pool)
					if take2 > 0.0:
						got += take2
						if pool >= 0.0:
							overseas[r] = pool - take2
				info.imported = kt(r, got)
				info.cic = got / float(def.trade_rate)
				free -= info.cic
				entry.lock += info.cic
			# What trade could not bring is taken from the stockpile, so the stock stays a buffer
			# against a blockade or a war that closes the markets.
			var unmet: float = maxf(0.0, info.need - info.imported)
			if def.stockpile and unmet > 0.0:
				info.draw = minf(unmet, info.stock * 365.0)
				unmet -= info.draw
			info.shortage = unmet / maxf(info.demand, 1.0) if info.demand > 0.0 else 0.0
			info.mult = 1.0 - float(def.max_penalty) * info.shortage
			info.cost_industry = info.shortage * def.shortage.industry
			info.cost_gdp = info.shortage * def.shortage.gdp
		entry.free = free
