class_name Navy
extends RefCounted
## Naval rules: ships and fleets, shipbuilding, sailing through sea zones, upkeep. Fleets
## live in GameState.fleets and change only through commands and step_day. All constants live
## in data/navy.json; the zones themselves are in MapData (tools/build_sea_zones.py).

const CONFIG_PATH := "res://data/navy.json"
const KM_PER_PX := 0.6928

static var cfg: Dictionary = {}


static func load_config() -> void:
	cfg = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	assert(cfg is Dictionary, "navy.json is invalid")


static func type_ids() -> Array:
	return cfg.types.keys()


# ------------------------------------------------------------------ queries

static func fleets_of(gs: Node, tag: String) -> Array[Fleet]:
	var out: Array[Fleet] = []
	for f: Fleet in gs.fleets.values():
		if f.tag == tag:
			out.append(f)
	out.sort_custom(func(a: Fleet, b: Fleet) -> bool: return a.id < b.id)
	return out


static func fleets_in_port(gs: Node, province: int) -> Array[Fleet]:
	var out: Array[Fleet] = []
	for f: Fleet in gs.fleets.values():
		if f.port == province:
			out.append(f)
	out.sort_custom(func(a: Fleet, b: Fleet) -> bool: return a.id < b.id)
	return out


## Fleets at sea in a zone (not those in a port that opens on it).
static func fleets_in_zone(gs: Node, zone: int) -> Array[Fleet]:
	var out: Array[Fleet] = []
	for f: Fleet in gs.fleets.values():
		if f.zone == zone:
			out.append(f)
	out.sort_custom(func(a: Fleet, b: Fleet) -> bool: return a.id < b.id)
	return out


## Port level for the navy: the better of the commercial port and the naval base.
static func port_level(gs: Node, province: int) -> int:
	return maxi(gs.province_buildings[province].get("port", 0), gs.naval_bases.get(province, 0))


## Whether ships of a nation may lie in a province's port: it has a port, and the nation holds
## it or an ally (or a treaty) lets it use it.
static func can_dock(gs: Node, tag: String, province: int) -> bool:
	if province < 1 or province >= gs.province_owner.size() or port_level(gs, province) < 1:
		return false
	if MapData.zones_of_port(province).is_empty():
		return false
	var o: String = gs.province_owner[province]
	var c: String = gs.province_controller[province]
	if o == tag or c == tag:
		return true
	if gs.at_war(tag, o) or gs.at_war(tag, c):
		return false
	return Diplomacy.has_passage(gs, o, tag) and Diplomacy.has_passage(gs, c, tag)


## Days to sail from one zone to a neighbouring one at a speed in km per day.
static func zone_days(speed: float, from: int, to: int) -> float:
	var km := (MapData.sea_zones[from].center as Vector2).distance_to(MapData.sea_zones[to].center) * KM_PER_PX
	return maxf(ceilf(km / maxf(speed, 1.0)), cfg.min_hop_days)


## Cheapest route through the zones from any of `from_zones` to any of `to_zones`, as the zones
## to enter in order, starting with the first of `from_zones` it begins in (so a fleet already
## in its zone drops path[0]). Empty if there is none.
static func find_path(speed: float, from_zones: Array, to_zones: Array) -> Array[int]:
	var path: Array[int] = []
	if from_zones.is_empty() or to_zones.is_empty():
		return path
	var dist := {}
	var prev := {}
	var open: Array[int] = []
	for z: int in from_zones:
		dist[z] = 0.0
		open.append(z)
	var goal := 0
	while not open.is_empty():
		var best := 0
		for i in open.size():
			if dist[open[i]] < dist[open[best]] or (dist[open[i]] == dist[open[best]] and open[i] < open[best]):
				best = i
		var z: int = open[best]
		open.remove_at(best)
		if to_zones.has(z):
			goal = z
			break
		for n: int in MapData.sea_adjacency[z]:
			var d: float = dist[z] + zone_days(speed, z, n)
			if not dist.has(n) or d < dist[n]:
				dist[n] = d
				prev[n] = z
				if not open.has(n):
					open.append(n)
	if goal == 0:
		return path
	var at := goal
	path.append(at)
	while prev.has(at):
		at = prev[at]
		path.push_front(at)
	return path


static func new_fleet(gs: Node, tag: String, fleet_name: String, port: int) -> Fleet:
	var f := Fleet.new()
	f.id = gs.next_fleet_id
	gs.next_fleet_id += 1
	f.tag = tag
	f.display_name = fleet_name
	f.port = port
	gs.fleets[f.id] = f
	return f


# ------------------------------------------------------------------ shipbuilding

## What building `count` squadrons of a type would cost, shaped like Economy.build_plan: gold,
## materials from the stockpile and the shortfall bought at a markup (impossible under blockade).
static func ship_plan(gs: Node, tag: String, type: String, count: int) -> Dictionary:
	var def: Dictionary = cfg.types[type]
	var n: Nation = gs.nations[tag]
	var plan := {"gold": def.cost * count, "materials": {}, "from_stock": {}, "buy": {}, "purchase": 0.0, "total": 0.0, "blocked": ""}
	for r in def.materials:
		var need: float = def.materials[r] * count
		var use := minf(need, n.stock.get(r, 0.0))
		plan.materials[r] = need
		plan.from_stock[r] = use
		plan.buy[r] = need - use
		if need - use > 0.0:
			if n.blockade >= 0.5:
				plan.blocked = "Blockade stops %s imports" % Economy.cfg.resources[r].name.to_lower()
			plan.purchase += (need - use) * Economy.cfg.resources[r].price / 1000.0 * Economy.cfg.import_markup
	plan.total = plan.gold + plan.purchase
	return plan


## Squadrons being built in a province for a nation.
static func building_in(gs: Node, tag: String, province: int) -> int:
	var n := 0
	for job in gs.nations[tag].shipbuilding:
		if job.province == province:
			n += 1
	return n


## Largest number of squadrons a port can have on the slips at once.
static func yard_slots(gs: Node, province: int) -> int:
	return port_level(gs, province) * cfg.slots_per_port_level


## Why ships cannot be built now, or "" if they can.
static func build_problem(gs: Node, tag: String, province: int, type: String, count: int, check_money := true) -> String:
	var n: Nation = gs.nations.get(tag)
	if n == null or not cfg.types.has(type) or count < 1:
		return "Invalid order."
	if province < 1 or province >= gs.province_owner.size() or gs.province_owner[province] != tag:
		return "Not your province"
	if gs.province_controller[province] != tag:
		return "Province is occupied"
	if MapData.zones_of_port(province).is_empty():
		return "Needs a coastal province"
	var level := port_level(gs, province)
	if level < 1:
		return "Needs a port"
	if level < cfg.types[type].min_port:
		return "Needs a level %d port" % cfg.types[type].min_port
	if building_in(gs, tag, province) + count > yard_slots(gs, province):
		return "The yard is full"
	var plan := ship_plan(gs, tag, type, count)
	if not plan.blocked.is_empty():
		return plan.blocked
	if check_money and n.treasury < plan.total:
		return "Not enough money (£%.1fM)" % plan.total
	return ""


# ------------------------------------------------------------------ upkeep

## Yearly cost of the ships a nation has afloat.
static func ship_upkeep(gs: Node, tag: String) -> float:
	var total := 0.0
	for f in fleets_of(gs, tag):
		for s in f.ships:
			total += s.def().upkeep
	return total


## Sets every nation's yearly naval cost: the shore establishment (what the scenario's
## historical budget does not spend on ships) plus the upkeep of its ships.
static func refresh_upkeep(gs: Node) -> void:
	var sums := {}
	for f: Fleet in gs.fleets.values():
		for s in f.ships:
			sums[f.tag] = sums.get(f.tag, 0.0) + s.def().upkeep
	for tag in gs.nations:
		var n: Nation = gs.nations[tag]
		n.naval_budget = n.naval_overhead + sums.get(tag, 0.0)


# ------------------------------------------------------------------ scenario

## Places the starting fleets (navy.tsv), gives each base the level its biggest ship
## needs (as a naval base, apart from the commercial port), and works out each nation's naval
## overhead so that its yearly cost at the start is
## the scenario's historical naval budget.
static func deploy_starting(gs: Node, dir: String) -> void:
	gs.fleets.clear()
	gs.naval_bases = {}
	gs.next_fleet_id = 1
	var by_name := {}
	var need := {}
	for row in MapData.read_table(dir + "navy.tsv"):
		var tag: String = row.tag
		var province := int(row.province)
		assert(gs.nations.has(tag) and cfg.types.has(row.type), "bad navy.tsv row for %s" % tag)
		assert(not MapData.zones_of_port(province).is_empty(), "navy.tsv base %d has no port zone" % province)
		var key := "%s|%d|%s" % [tag, province, row.fleet]
		if not by_name.has(key):
			by_name[key] = new_fleet(gs, tag, row.fleet, province)
		for i in int(row.count):
			by_name[key].ships.append(Ship.new(row.type))
		need[province] = maxi(need.get(province, 1), cfg.types[row.type].min_port)
	gs.naval_bases = need
	for tag in gs.nations:
		var n: Nation = gs.nations[tag]
		n.shipbuilding.clear()
		n.naval_overhead = maxf(0.0, n.naval_budget - ship_upkeep(gs, tag))
	refresh_upkeep(gs)


# ------------------------------------------------------------------ daily step

static func step_day(gs: Node) -> void:
	var built := _build(gs)
	for f: Fleet in gs.fleets.values():
		_sail(f)
	NavalCombat.step_day(gs)
	Blockade.step_day(gs)
	if built:
		Economy.recompute(gs)
		gs.economy_updated.emit()
	gs.fleets_changed.emit()


## Finishes ships whose building is over and puts them in the yard's port.
static func _build(gs: Node) -> bool:
	var finished := false
	for tag in gs.nations:
		var n: Nation = gs.nations[tag]
		for i in range(n.shipbuilding.size() - 1, -1, -1):
			var job: Dictionary = n.shipbuilding[i]
			job.days_left -= 1
			if job.days_left > 0:
				continue
			n.shipbuilding.remove_at(i)
			# A yard that has changed hands launches nothing.
			if gs.province_controller[job.province] != tag:
				continue
			var host: Fleet = null
			for f in fleets_in_port(gs, job.province):
				if f.tag == tag and not f.is_moving() and not f.fighting and (host == null or f.ships.size() < host.ships.size()):
					host = f
			if host == null:
				host = new_fleet(gs, tag, "New squadrons at %s" % MapData.provinces[job.province].name, job.province)
			host.ships.append(Ship.new(job.type))
			gs.ship_built.emit(tag, job.province, job.type)
			finished = true
	return finished


static func _sail(f: Fleet) -> void:
	if not f.path.is_empty():
		f.move_days_left -= 1.0
		if f.move_days_left > 0.0:
			return
		f.zone = f.path.pop_front()
		f.port = 0
		if not f.path.is_empty():
			f.move_days_left = zone_days(f.speed(), f.zone, f.path[0])
		elif f.dest_port > 0:
			f.entering = true
			f.move_days_left = cfg.port_days
		else:
			f.move_days_left = 0.0
		return
	if f.entering:
		f.move_days_left -= 1.0
		if f.move_days_left > 0.0:
			return
		f.entering = false
		f.port = f.dest_port
		f.dest_port = 0
		f.zone = 0
