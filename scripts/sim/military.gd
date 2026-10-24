class_name Military
extends RefCounted
## Military rules: terrain, pathfinding, daily movement, combat, entrenchment, supply and
## occupation. Armies live in GameState.armies and change only through commands and
## step_day. All constants live in data/military.json.

const CONFIG_PATH := "res://data/military.json"
const TERRAIN_PATH := "res://data/map/terrain.tsv"
## Ground distance of one bitmap pixel in km (sqrt of MapData.KM2_PER_PX).
const KM_PER_PX := 0.6928

static var cfg: Dictionary = {}
## Terrain type by province id (element 0 unused).
static var terrain: PackedStringArray = []
## Land neighbours by province (the map never changes, so they are worked out once). Callers
## must not modify the arrays.
static var _neighbor_cache: Dictionary = {}
## Answers of home_connected, kept for one day.
static var _home_cache: Dictionary = {}
static var _home_day := -1


static func load_config() -> void:
	cfg = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	assert(cfg is Dictionary, "military.json is invalid")
	_neighbor_cache.clear()
	terrain = PackedStringArray()
	terrain.resize(MapData.provinces.size())
	for i in terrain.size():
		terrain[i] = "plains"
	for row in MapData.read_table(TERRAIN_PATH):
		terrain[int(row.id)] = row.terrain


static func unit_type_ids() -> Array:
	return cfg.unit_types.keys()


static func terrain_of(id: int) -> Dictionary:
	return cfg.terrain[terrain[id]]


# ------------------------------------------------------------------ queries

## Land provinces (and strait crossings) one step away. Open-sea links need a navy.
static func neighbors(id: int) -> Array:
	var cached: Variant = _neighbor_cache.get(id)
	if cached != null:
		return cached
	var out := []
	for n in MapData.adjacency.get(id, PackedInt32Array()):
		if MapData.sea_links.get(Vector2i(mini(id, n), maxi(id, n)), "") == "sea":
			continue
		out.append(n)
	_neighbor_cache[id] = out
	return out


## Neighbours an army of `tag` can reach from a province: the land and strait neighbours, and
## across short stretches of sea (the Irish Sea, Corsica, Sardinia) the provinces on the other
## side, as long as no enemy holds the water between.
static func neighbors_for(gs: Node, tag: String, id: int) -> Array:
	var out: Array = neighbors(id)
	var extra: Array = []
	for n in MapData.adjacency.get(id, PackedInt32Array()):
		if MapData.sea_links.get(Vector2i(mini(id, n), maxi(id, n)), "") == "sea" and crossing_open(gs, tag, id, n):
			extra.append(n)
	return out + extra if not extra.is_empty() else out


## Whether a short sea crossing between two provinces is free of enemy ships.
static func crossing_open(gs: Node, tag: String, a: int, b: int) -> bool:
	var zones: Array[int] = MapData.zones_of_port(a)
	for z in MapData.zones_of_port(b):
		if not zones.has(z):
			zones.append(z)
	for z in zones:
		if not Blockade.blockaders(gs, tag, z).is_empty():
			return false
	return true


## Whether armies of a nation may stand in a province: its own ground, ground it holds, or
## ground of a nation it is at war with, or ground whose owner and holder both let it cross
## (an ally, or a passage treaty; see Diplomacy.has_passage).
static func can_enter(gs: Node, tag: String, id: int) -> bool:
	var o: String = gs.province_owner[id]
	var c: String = gs.province_controller[id]
	if not gs.restrictions.is_empty() and Peace.restricted(gs, tag, id):
		return false
	if o == tag or c == tag or gs.at_war(tag, o) or gs.at_war(tag, c):
		return true
	return Diplomacy.has_passage(gs, o, tag) and Diplomacy.has_passage(gs, c, tag)


static func armies_at(gs: Node, id: int) -> Array[Army]:
	var out: Array[Army] = []
	for a: Army in gs.armies.values():
		if a.province == id and not a.embarked():
			out.append(a)
	return out


static func armies_of(gs: Node, tag: String) -> Array[Army]:
	var out: Array[Army] = []
	for a: Army in gs.armies.values():
		if a.tag == tag:
			out.append(a)
	out.sort_custom(func(x: Army, y: Army) -> bool: return x.id < y.id)
	return out


## Men in the field plus recruits in training.
static func men_in_service(gs: Node, tag: String) -> int:
	var total := 0.0
	for a: Army in gs.armies.values():
		if a.tag == tag:
			total += a.men()
	for job in gs.nations[tag].recruiting:
		total += cfg.unit_types[job.type].size
	return roundi(total)


## Whether a nation's railways run: with under half of the raw materials its industry needs
## (see Economy.materials_of) the engines stop and they help neither movement nor supply.
static func railway_ok(gs: Node, tag: String) -> bool:
	var n: Nation = gs.nations.get(tag)
	if n == null or not n.budget.has("materials"):
		return true
	return float(n.budget.materials.ratio) >= 0.5


## The cost of a supply hop into province `id` for `tag`: 1, or less where a railway runs (each
## level beyond the first makes it cheaper still).
static func hop_cost(gs: Node, tag: String, id: int) -> float:
	var level: int = gs.province_buildings[id].get("railway", 0)
	if level <= 0 or not railway_ok(gs, tag):
		return 1.0
	return maxf(0.2, float(cfg.supply.railway_hop_cost) * (1.0 - float(cfg.supply.railway_level_gain) * (level - 1)))


## Days an army of the given speed needs to walk from one province into a neighbour.
static func move_days(gs: Node, tag: String, speed: float, from: int, to: int) -> float:
	var km := (MapData.provinces[from].center as Vector2).distance_to(MapData.provinces[to].center) * KM_PER_PX
	var days: float = km / speed * terrain_of(to).move
	if gs.province_controller[to] == tag and railway_ok(gs, tag):
		days /= 1.0 + cfg.movement.railway_speedup * gs.province_buildings[to].get("railway", 0)
	var link: String = MapData.sea_links.get(Vector2i(mini(from, to), maxi(from, to)), "")
	if link == "sea":
		days += cfg.movement.sea_link_days
	elif link != "":
		days += cfg.movement.strait_days
	return maxf(ceilf(days), cfg.movement.min_days)


## Cheapest route for an army, as the provinces to enter (empty if there is none).
static func find_path(gs: Node, tag: String, speed: float, from: int, to: int) -> Array[int]:
	var path: Array[int] = []
	if from == to or not can_enter(gs, tag, to):
		return path
	var dist := {from: 0.0}
	var prev := {}
	# A binary heap of [days, order, province] (lazy deletion): the nearest first, and among equals
	# the one that was queued first.
	var heap: Array = [[0.0, 0, from]]
	var queued := {from: 0}
	var seq := 1
	while not heap.is_empty():
		var top: Array = _heap_pop(heap)
		var cur: int = top[2]
		if top[0] > dist[cur]:
			continue
		if cur == to:
			break
		queued.erase(cur)
		for n: int in neighbors_for(gs, tag, cur):
			if not can_enter(gs, tag, n):
				continue
			var nd: float = dist[cur] + move_days(gs, tag, speed, cur, n)
			if not dist.has(n) or nd < dist[n]:
				dist[n] = nd
				prev[n] = cur
				if not queued.has(n):
					queued[n] = seq
					seq += 1
				_heap_push(heap, [nd, queued[n], n])
	if not prev.has(to):
		return path
	var step := to
	while step != from:
		path.push_front(step)
		step = prev[step]
	return path


static func _heap_less(x: Array, y: Array) -> bool:
	return x[0] < y[0] or (x[0] == y[0] and x[1] < y[1])


static func _heap_push(heap: Array, item: Array) -> void:
	heap.append(item)
	var i := heap.size() - 1
	while i > 0:
		var parent := (i - 1) >> 1
		if not _heap_less(heap[i], heap[parent]):
			break
		var tmp: Array = heap[i]
		heap[i] = heap[parent]
		heap[parent] = tmp
		i = parent


static func _heap_pop(heap: Array) -> Array:
	var top: Array = heap[0]
	var last: Array = heap.pop_back()
	if not heap.is_empty():
		heap[0] = last
		var i := 0
		var n := heap.size()
		while true:
			var l := 2 * i + 1
			var r := l + 1
			var m := i
			if l < n and _heap_less(heap[l], heap[m]):
				m = l
			if r < n and _heap_less(heap[r], heap[m]):
				m = r
			if m == i:
				break
			var tmp: Array = heap[i]
			heap[i] = heap[m]
			heap[m] = tmp
			i = m
	return top


# ------------------------------------------------------------------ city aura

static var _aura: Dictionary = {}
static var _aura_day := -1
static var _aura_owner := 0
static var _aura_version := -1
static var _aura_control := -1


## The strength of the cities' aura (0 to 1) over a province for the nation that holds it: the
## strongest of the cities near enough that the nation owns and controls, itself and the ground
## between. 0 for ground that is not the nation's own. Worked out again only when who owns or holds what changes.
static func city_aura(gs: Node, tag: String, id: int) -> float:
	if _aura_day < 0 or _aura_owner != gs.get_instance_id() or _aura_version != gs.owner_version or _aura_control != gs.control_version:
		_aura = _build_aura(gs)
		_aura_day = Clock.days_elapsed
		_aura_owner = gs.get_instance_id()
		_aura_version = gs.owner_version
		_aura_control = gs.control_version
	return float(_aura.get(tag, {}).get(id, 0.0))


## Forgets the day's aura (a city was captured or freed, or another game was loaded).
static func invalidate_aura() -> void:
	_aura_day = -1
	_aura.clear()


static func _build_aura(gs: Node) -> Dictionary:
	var out := {}
	var power: Dictionary = cfg.cities.power
	var radius: Dictionary = cfg.cities.radius
	for city: Dictionary in gs.cities:
		var home: int = city.province
		var owner: String = gs.province_owner[home]
		if gs.province_controller[home] != owner:
			continue
		var strength := float(power[str(city.rank)])
		var reach := int(radius[str(city.rank)])
		var by_tag: Dictionary = out.get(owner, {})
		out[owner] = by_tag
		var dist := {home: 0}
		var open := [home]
		while not open.is_empty():
			var cur: int = open.pop_front()
			var here := strength * (1.0 - float(dist[cur]) / float(reach + 1))
			if here > float(by_tag.get(cur, 0.0)):
				by_tag[cur] = here
			if dist[cur] >= reach:
				continue
			for nb: int in neighbors(cur):
				if dist.has(nb) or gs.province_owner[nb] != owner or gs.province_controller[nb] != owner:
					continue
				dist[nb] = dist[cur] + 1
				open.append(nb)
	return out


## Supply distance in hops from the nearest province the nation controls (railways make a hop
## cheaper); INF if it is farther than the supply range.
static func supply_cost(gs: Node, tag: String, from: int) -> float:
	if gs.province_controller[from] == tag and home_connected(gs, tag, from):
		return 0.0
	# Asked again and again over a day (every army, every order), and the answer moves only when the day or
	# who holds what does: kept until then.
	var stamp := [Clock.days_elapsed, gs.control_version, gs.get_instance_id()]
	if stamp != _supply_stamp:
		_supply_cache.clear()
		_supply_stamp = stamp
	var key := "%s:%d" % [tag, from]
	if _supply_cache.has(key):
		return _supply_cache[key]
	var cost := _supply_search(gs, tag, from)
	_supply_cache[key] = cost
	return cost


static var _supply_cache: Dictionary = {}
static var _supply_stamp: Array = []


static func _supply_search(gs: Node, tag: String, from: int) -> float:
	var limit: float = cfg.supply.range + float(cfg.cities.supply_range) * city_aura(gs, tag, from)
	var dist := {from: 0.0}
	var open := [from]
	while not open.is_empty():
		var bi := 0
		for i in open.size():
			if dist[open[i]] < dist[open[bi]]:
				bi = i
		var cur: int = open.pop_at(bi)
		if gs.province_controller[cur] == tag and home_connected(gs, tag, cur):
			return dist[cur]
		for n: int in neighbors(cur):
			var step := hop_cost(gs, tag, n)
			var nd: float = dist[cur] + step
			if nd > limit + 0.001 or (dist.has(n) and dist[n] <= nd):
				continue
			dist[n] = nd
			if not open.has(n):
				open.append(n)
	return INF


## Whether ground a nation holds is tied to its homeland: it joins ground the nation owns by
## land, or a port in its region has a clear sea route to a home port (no enemy-held zone on
## the way). Ground that is neither (a pocket cut off by the enemy) supplies nobody. Answers are
## kept for the day.
static func home_connected(gs: Node, tag: String, id: int) -> bool:
	if gs.province_owner[id] == tag:
		return true
	if _home_day != Clock.days_elapsed:
		_home_cache.clear()
		_home_day = Clock.days_elapsed
	var key := "%s:%d" % [tag, id]
	if _home_cache.has(key):
		return _home_cache[key]
	# The region of ground the nation holds around this province.
	var seen := {id: true}
	var queue := [id]
	var home := false
	var ports: Array[int] = []
	while not queue.is_empty() and not home:
		var cur: int = queue.pop_back()
		if gs.province_owner[cur] == tag:
			home = true
			break
		if not MapData.zones_of_port(cur).is_empty():
			ports.append(cur)
		for n: int in neighbors(cur):
			if not seen.has(n) and gs.province_controller[n] == tag:
				seen[n] = true
				queue.append(n)
	if not home:
		for p in ports:
			if Navy.sea_route_home(gs, tag, p):
				home = true
				break
	for k in seen:
		_home_cache["%s:%d" % [tag, k]] = home
	return home


## Defence multiplier for an army that is holding the province: terrain times entrenchment.
static func defense_multiplier(a: Army) -> float:
	return terrain_of(a.province).defense * (1.0 + cfg.combat.entrench_defense_per_level * a.entrenchment() + works_defense(GameState, a))


## The province's own works help the nation that owns it: trenches and heavy fortifications add
## their defense bonus for every level (see data/economy.json, buildings).
static func works_defense(gs: Node, a: Army) -> float:
	if gs.province_owner[a.province] != a.tag:
		return 0.0
	var built: Dictionary = gs.province_buildings[a.province]
	var b: Dictionary = Economy.cfg.buildings
	return b.trench.defense * built.get("trench", 0) + b.fortification.defense * built.get("fortification", 0)


## Share of the damage the province's works take off an attack on an army that holds it: shelling
## is cut by the trenches (`shell_reduction` a level), assault by the fortifications
## (`hard_reduction` a level). `shelling` is the share of the attacker's power that comes from guns.
static func works_reduction(gs: Node, a: Army, shelling: float) -> float:
	if gs.province_owner[a.province] != a.tag:
		return 0.0
	var built: Dictionary = gs.province_buildings[a.province]
	var b: Dictionary = Economy.cfg.buildings
	var shell := minf(0.9, b.trench.shell_reduction * built.get("trench", 0))
	var hard := minf(0.9, b.fortification.hard_reduction * built.get("fortification", 0))
	return shelling * shell + (1.0 - shelling) * hard


# ------------------------------------------------------------------ setup

## Puts the starting armies on the map from each nation's peacetime army.
static func deploy_starting(gs: Node) -> void:
	gs.armies.clear()
	gs.next_army_id = 1
	gs.generals.clear()
	gs.next_general_id = 1
	gs.army_groups.clear()
	gs.next_group_id = 1
	gs.attack_lines.clear()
	gs.next_attack_line_id = 1
	var plans: Dictionary = gs.scenario.get("deployment", {})
	for tag in gs.nations:
		var n: Nation = gs.nations[tag]
		if n.peacetime_army <= 0:
			continue
		var units := _starting_units(int(n.peacetime_army * cfg.field_share))
		var stacks := _stack_plan(gs, tag, plans.get(tag, []), units.size())
		var generals: Array = cfg.generals.get(tag, [])
		var armies: Array[Army] = []
		for i in stacks.size():
			var a := new_army(gs, tag, stacks[i].name, stacks[i].province)
			armies.append(a)
		# Every general in the nation's list joins its pool; the first ones lead the armies.
		for i in generals.size():
			var g := new_general(gs, tag, generals[i][0], generals[i][1])
			if i < armies.size():
				set_general(gs, g, armies[i])
		# Deal the units out so each stack holds men in proportion to its weight.
		var dealt := PackedFloat32Array()
		dealt.resize(stacks.size())
		for u in units:
			var best := 0
			for i in stacks.size():
				if dealt[i] / stacks[i].weight < dealt[best] / stacks[best].weight:
					best = i
			armies[best].units.append(u)
			dealt[best] += u.men()
		for a in armies:
			if a.units.is_empty():
				gs.armies.erase(a.id)
	refresh_men(gs)
	for tag in gs.nations:
		var n: Nation = gs.nations[tag]
		n.manpower = maxi(0, n.peacetime_army - n.men_in_units)


static func _starting_units(men: int) -> Array[Unit]:
	var out: Array[Unit] = []
	for type in unit_type_ids():
		var def: Dictionary = cfg.unit_types[type]
		var left: float = men * def.share
		while left >= def.size:
			out.append(Unit.new(type))
			left -= def.size
		# A part-strength unit for the remainder, unless it is only a handful of men.
		if left / def.size >= 0.02:
			out.append(Unit.new(type, left / def.size))
	return out


## Where a nation's stacks stand: the scenario's list, or its most populous provinces.
static func _stack_plan(gs: Node, tag: String, listed: Array, unit_count: int) -> Array:
	var plan: Array = []
	for entry in listed:
		var id := _province_named(gs, entry.at, tag)
		assert(id > 0, "deployment: %s has no province %s" % [tag, entry.at])
		plan.append({"name": entry.name, "province": id, "weight": float(entry.get("weight", 1.0))})
	if plan.is_empty():
		var owned: Array = Array(gs.nations[tag].provinces)
		owned.sort_custom(func(x: int, y: int) -> bool: return gs.province_population[x] > gs.province_population[y])
		for i in mini(owned.size(), clampi(roundi(sqrt(unit_count)), 1, 8)):
			plan.append({"name": "Army of %s" % MapData.provinces[owned[i]].name, "province": owned[i], "weight": 1.0})
	return plan


static func _province_named(gs: Node, province_name: String, tag: String) -> int:
	for id in range(1, MapData.provinces.size()):
		if MapData.provinces[id].name == province_name and gs.province_owner[id] == tag:
			return id
	return 0


static func new_army(gs: Node, tag: String, army_name: String, province: int) -> Army:
	var a := Army.new()
	a.id = gs.next_army_id
	gs.next_army_id += 1
	a.tag = tag
	a.display_name = army_name
	a.province = province
	gs.armies[a.id] = a
	return a


static func new_general(gs: Node, tag: String, general_name: String, skill: float) -> General:
	var g := General.new()
	g.id = gs.next_general_id
	gs.next_general_id += 1
	g.tag = tag
	g.display_name = general_name
	g.skill = skill
	gs.generals[g.id] = g
	return g


## Puts `g` in command of `a`. Whoever led `a` goes back to the pool, and `g` leaves the army he
## led before. With `g` null the army is left without a general; with `a` null `g` is only taken
## off his army.
static func set_general(gs: Node, g: General, a: Army) -> void:
	if g != null and g.army_id != 0:
		_clear_command(gs.armies.get(g.army_id), g)
	if a != null:
		var old: General = gs.generals.get(a.general_id)
		if old != null:
			old.army_id = 0
		a.general_id = 0
		a.general_name = ""
		a.general_skill = 1.0
	if g == null or a == null:
		return
	g.army_id = a.id
	a.general_id = g.id
	a.general_name = g.display_name
	a.general_skill = g.skill


static func _clear_command(a: Army, g: General) -> void:
	g.army_id = 0
	if a != null and a.general_id == g.id:
		a.general_id = 0
		a.general_name = ""
		a.general_skill = 1.0


## Frees generals whose army is gone (destroyed, cut off, disbanded or merged away).
static func release_orphan_generals(gs: Node) -> void:
	for g: General in gs.generals.values():
		if g.army_id != 0 and (not gs.armies.has(g.army_id) or gs.armies[g.army_id].general_id != g.id):
			g.army_id = 0
	# The AI keeps its best free general in command of its biggest army without one.
	for tag in gs.nations:
		if tag == gs.player_tag:
			continue
		var pool := pool_of(gs, tag)
		if pool.is_empty():
			continue
		var unled: Array[Army] = []
		for a: Army in gs.armies.values():
			if a.tag == tag and a.general_id == 0 and not a.units.is_empty():
				unled.append(a)
		unled.sort_custom(func(x: Army, y: Army) -> bool: return x.men() > y.men() or (x.men() == y.men() and x.id < y.id))
		for i in mini(pool.size(), unled.size()):
			set_general(gs, pool[i], unled[i])


## The nation's generals who lead no army and no group, best first.
static func pool_of(gs: Node, tag: String) -> Array[General]:
	var out: Array[General] = []
	for g: General in gs.generals.values():
		if g.tag == tag and g.army_id == 0 and g.group_id == 0:
			out.append(g)
	out.sort_custom(func(x: General, y: General) -> bool: return x.skill > y.skill or (x.skill == y.skill and x.id < y.id))
	return out


static func new_group(gs: Node, tag: String, group_name: String) -> ArmyGroup:
	var g := ArmyGroup.new()
	g.id = gs.next_group_id
	gs.next_group_id += 1
	g.tag = tag
	g.display_name = group_name if not group_name.is_empty() else "Army Group %d" % g.id
	gs.army_groups[g.id] = g
	return g


## Moves armies into `group` (null takes them out of their groups).
static func put_in_group(gs: Node, group: ArmyGroup, army_ids: Array[int]) -> void:
	for id in army_ids:
		var a: Army = gs.armies.get(id)
		if a == null:
			continue
		var old: ArmyGroup = gs.army_groups.get(a.group_id)
		if old != null:
			old.army_ids.erase(a.id)
		a.group_id = 0
		if group != null:
			a.group_id = group.id
			group.army_ids.append(a.id)


## Sets the group's marshal (null relieves him); the old marshal goes back to the pool.
static func set_marshal(gs: Node, group: ArmyGroup, g: General) -> void:
	var old: General = gs.generals.get(group.marshal_id)
	if old != null:
		old.group_id = 0
	group.marshal_id = 0
	if g != null:
		g.group_id = group.id
		group.marshal_id = g.id


static func remove_group(gs: Node, group: ArmyGroup) -> void:
	for id in group.army_ids:
		if gs.armies.has(id):
			gs.armies[id].group_id = 0
	group.army_ids.clear()
	set_marshal(gs, group, null)
	gs.army_groups.erase(group.id)


## Drops armies that no longer exist from their groups and dissolves groups left empty.
static func prune_groups(gs: Node) -> void:
	for group: ArmyGroup in gs.army_groups.values().duplicate():
		for i in range(group.army_ids.size() - 1, -1, -1):
			var a: Army = gs.armies.get(group.army_ids[i])
			if a == null or a.group_id != group.id:
				group.army_ids.remove_at(i)
		if group.army_ids.is_empty():
			remove_group(gs, group)


## What an army's power is multiplied by for the marshal over its group.
static func marshal_mult(a: Army) -> float:
	if a.group_id == 0:
		return 1.0
	var group: ArmyGroup = GameState.army_groups.get(a.group_id)
	if group == null:
		return 1.0
	var m: General = GameState.generals.get(group.marshal_id)
	if m == null:
		return 1.0
	return 1.0 + (m.skill - 1.0) * float(cfg.army_group.marshal_share)


## Recomputes the men each nation has under arms (used for upkeep and the manpower cap).
static func refresh_men(gs: Node) -> void:
	for tag in gs.nations:
		gs.nations[tag].men_in_units = men_in_service(gs, tag)


## Days at which an army walking `path` from `from` reaches each province on it, counted from
## now. `first_left` is what remains of the step it is already taking.
static func path_etas(gs: Node, tag: String, speed: float, from: int, path: Array, first_left: float) -> Array[float]:
	var out: Array[float] = []
	var total := 0.0
	var prev := from
	for i in path.size():
		total += first_left if i == 0 else move_days(gs, tag, speed, prev, path[i])
		out.append(total)
		prev = path[i]
	return out


static func army_etas(gs: Node, a: Army) -> Array[float]:
	return path_etas(gs, a.tag, a.speed(), a.province, a.path, maxf(1.0, ceilf(a.move_days_left)))


# ------------------------------------------------------------------ fronts

## Provinces a nation holds that touch ground held by another nation, in province order.
static func border_provinces(gs: Node, tag: String, other: String) -> Array[int]:
	var out: Array[int] = []
	for id in range(1, gs.province_controller.size()):
		if gs.province_controller[id] != tag:
			continue
		for n: int in neighbors(id):
			if gs.province_controller[n] == other:
				out.append(id)
				break
	return out


static func leave_front(gs: Node, a: Army) -> void:
	if a.front_id == 0:
		return
	var f: Front = gs.fronts.get(a.front_id)
	if f != null:
		f.army_ids.erase(a.id)
		f.slots.erase(a.id)
		f.dirty = true
	a.front_id = 0


## Spreads each front's armies along its line and sends idle ones to their province.
static func step_fronts(gs: Node) -> void:
	var routes_left := int(cfg.front_pathing.paths_per_day)
	for f: Front in gs.fronts.values():
		if not f.against.is_empty() and f.line_stamp != gs.control_version:
			# A border front follows the war: re-read the line from who holds what (when anything
			# has changed hands since it was last read).
			f.line_stamp = gs.control_version
			var t0 := Time.get_ticks_usec() if profile else 0
			var line := border_provinces(gs, f.tag, f.against)
			_note("front_line", t0)
			if line != f.provinces:
				f.provinces = line
				f.dirty = true
				gs.fronts_changed.emit()
		var live: Array[int] = []
		for id in f.army_ids:
			if gs.armies.has(id):
				live.append(id)
		if live.size() != f.army_ids.size():
			f.army_ids = live
			f.dirty = true
		if f.provinces.is_empty():
			f.slots.clear()
			continue
		if f.dirty:
			var t1 := Time.get_ticks_usec() if profile else 0
			_deal_slots(gs, f)
			_note("front_slots", t1)
			f.dirty = false
		for id in f.army_ids:
			var a: Army = gs.armies[id]
			var slot: int = f.slots.get(id, 0)
			if slot == 0 or a.province == slot or not a.path.is_empty() or a.fighting:
				continue
			if Clock.days_elapsed < f.retry.get(id, -1) or routes_left <= 0:
				continue
			routes_left -= 1
			var t2 := Time.get_ticks_usec() if profile else 0
			var route := find_path(gs, a.tag, a.speed(), a.province, slot)
			_note("front_path", t2)
			if route.is_empty():
				f.retry[id] = Clock.days_elapsed + 10
				continue
			a.move_days_left = move_days(gs, a.tag, a.speed(), a.province, route[0])
			a.path = route
			a.still_days = 0


## Gives every army a province of the line to hold, keeping the men spread evenly.
static func _deal_slots(gs: Node, f: Front) -> void:
	f.slots.clear()
	f.retry.clear()
	var held := {}
	for p in f.provinces:
		held[p] = 0.0
	var list: Array[Army] = []
	for id in f.army_ids:
		list.append(gs.armies[id])
	list.sort_custom(func(x: Army, y: Army) -> bool: return x.men() > y.men() or (x.men() == y.men() and x.id < y.id))
	for a in list:
		var best := 0
		for p in f.provinces:
			if best == 0 or held[p] < held[best] - 0.5 or (absf(held[p] - held[best]) <= 0.5 and _dist(a.province, p) < _dist(a.province, best)):
				best = p
		f.slots[a.id] = best
		held[best] += a.men()


static func _dist(a: int, b: int) -> float:
	return (MapData.provinces[a].center as Vector2).distance_to(MapData.provinces[b].center)


# ------------------------------------------------------------------ daily step

static func step_day(gs: Node) -> void:
	_timed("fronts", func() -> void: step_fronts(gs))
	prune_groups(gs)
	AttackLines.step_day(gs)
	release_orphan_generals(gs)
	_train(gs)
	var armies: Array = gs.armies.values()
	for a: Army in armies:
		a.fighting = false
	_timed("move", func() -> void: _move(gs, armies))
	_timed("fight", func() -> void: _fight(gs))
	var t_occupy := Time.get_ticks_usec() if profile else 0
	var captured := _upkeep_and_occupy(gs)
	_note("occupy", t_occupy)
	_collapse_nations(gs)
	refresh_men(gs)
	if captured:
		_timed("recompute", func() -> void: Economy.request(gs))
	gs.armies_changed.emit()


## Microseconds spent in the parts of the daily step, by name, and the worst single day of each,
## while `profile` is true (tools/profile_days.gd).
static var profile := false
static var timings: Dictionary = {}
static var worst: Dictionary = {}


static func _note(part: String, started: int) -> void:
	if profile:
		var dt := Time.get_ticks_usec() - started
		timings[part] = timings.get(part, 0) + dt
		worst[part] = maxi(worst.get(part, 0), dt)


static func _timed(part: String, work: Callable) -> void:
	if not profile:
		work.call()
		return
	var t := Time.get_ticks_usec()
	work.call()
	var dt := Time.get_ticks_usec() - t
	timings[part] = timings.get(part, 0) + dt
	worst[part] = maxi(worst.get(part, 0), dt)


## Finishes units whose training is over and puts them in the province they were raised in.
static func _train(gs: Node) -> void:
	for tag in gs.nations:
		var n: Nation = gs.nations[tag]
		for i in range(n.recruiting.size() - 1, -1, -1):
			var job: Dictionary = n.recruiting[i]
			job.days_left -= 1
			if job.days_left > 0:
				continue
			n.recruiting.remove_at(i)
			var host: Army = null
			for a in armies_at(gs, job.province):
				if a.tag == tag and a.path.is_empty() and not a.fighting and (host == null or a.units.size() < host.units.size()):
					host = a
			if host == null:
				host = new_army(gs, tag, "New levies at %s" % MapData.provinces[job.province].name, job.province)
			host.units.append(Unit.new(job.type))
			gs.unit_trained.emit(tag, job.province, job.type)


static func _move(gs: Node, armies: Array) -> void:
	for a: Army in armies:
		if a.path.is_empty() or a.embarked():
			continue
		a.still_days = 0
		a.move_days_left -= 1.0
		if a.move_days_left > 0.0:
			continue
		var dest: int = a.path[0]
		if not can_enter(gs, a.tag, dest):
			a.path.clear()
			continue
		a.path.pop_front()
		a.province = dest
		a.attacking = false
		for b: Army in armies:
			if b != a and b.province == dest and gs.at_war(a.tag, b.tag):
				a.attacking = true
				break
		if a.attacking:
			a.path.clear()
		elif not a.path.is_empty():
			a.move_days_left = move_days(gs, a.tag, a.speed(), dest, a.path[0])


static func _by_province(armies: Array) -> Dictionary:
	var at := {}
	for a: Army in armies:
		if a.embarked():
			continue
		if not at.has(a.province):
			at[a.province] = []
		at[a.province].append(a)
	return at


static func _fight(gs: Node) -> void:
	var armies: Array = gs.armies.values()
	var at := _by_province(armies)
	var routed: Array[Army] = []
	for id: int in at:
		var here: Array = at[id]
		if here.size() < 2:
			continue
		var foes := {}
		for a: Army in here:
			var list: Array[Army] = []
			for b: Army in here:
				if a.tag != b.tag and gs.at_war(a.tag, b.tag):
					list.append(b)
			if not list.is_empty():
				foes[a] = list
		if foes.is_empty():
			continue
		var incoming := {}
		var parts := {}
		for a in foes:
			incoming[a] = 0.0
			parts[a] = {}
		for b in foes:
			var share: float = b.power() * WarSupport.morale_mult(gs, b.tag) / foes[b].size()
			var shelling: float = b.shelling_share()
			for a in foes[b]:
				var dealt: float = share * (1.0 - works_reduction(gs, a, shelling))
				incoming[a] += dealt
				parts[a][b] = dealt
		var battle := _engagement(gs, id, foes)
		var tags := {}
		var today := {}
		for a: Army in foes:
			a.fighting = true
			tags[a.tag] = true
			var mult := 1.0 if a.attacking else defense_multiplier(a)
			var lost := _apply_casualties(a, incoming[a] * cfg.combat.casualties_per_point / mult)
			battle.lost[a.tag] = battle.lost.get(a.tag, 0.0) + lost
			gs.nations[a.tag].men_lost_month += lost
			gs.nations[a.tag].deaths_month += lost
			today[a.tag] = today.get(a.tag, 0.0) + lost
			if incoming[a] > 0.0:
				# Charge the loss to the wars with the armies that inflicted it.
				for b: Army in foes[a]:
					var war: War = gs.war_between(a.tag, b.tag)
					if war != null:
						war.losses[a.tag] += lost * parts[a][b] / incoming[a]
		_log_day(battle, foes, today)
		gs.battle_fought.emit(id, tags.keys())
		for a: Army in foes:
			if a.units.is_empty() or a.morale() < cfg.combat.rout_morale:
				routed.append(a)
	for a in routed:
		_retreat(gs, a, at)
	for a: Army in gs.armies.values():
		if a.units.is_empty():
			gs.armies.erase(a.id)
		elif not a.fighting:
			a.attacking = false
	# A battle is over once no hostile armies share the province.
	for id: int in gs.engagements.keys():
		var hostile := false
		var here := armies_at(gs, id)
		for a in here:
			for b in here:
				hostile = hostile or gs.at_war(a.tag, b.tag)
		if not hostile:
			_finish_engagement(gs, id)


## Men lost by the army in this call.
static func _apply_casualties(a: Army, casualties: float) -> float:
	var total := a.men()
	if total <= 0.0:
		return 0.0
	var frac := minf(casualties / total, 1.0)
	var morale_loss: float = frac * cfg.combat.morale_loss_per_casualty + cfg.combat.morale_loss_base
	for i in range(a.units.size() - 1, -1, -1):
		var u := a.units[i]
		u.strength *= 1.0 - frac
		u.morale = maxf(0.0, u.morale - morale_loss)
		if u.strength < cfg.combat.min_strength:
			a.units.remove_at(i)
	return total - a.men()


## A beaten army falls back to the best neighbouring province that its nation still holds.
## With none, it is cut off and lost: it cannot slip into land the enemy has taken and win
## it back for free.
static func _retreat(gs: Node, a: Army, at: Dictionary) -> void:
	if a.units.is_empty():
		return
	var enemies := _enemy_tags(gs, a, at)
	var best := 0
	for n: int in neighbors(a.province):
		if gs.province_controller[n] != a.tag:
			continue
		var blocked := false
		for b: Army in at.get(n, []):
			if gs.at_war(a.tag, b.tag):
				blocked = true
		if not blocked:
			best = n
			break
	if best == 0:
		var men := a.men()
		a.units.clear()
		_battle_event(gs, a.province, "%s's %s broke and was cut off (%dk men lost)." % [
				gs.nations[a.tag].display_name, a.display_name, roundi(men / 1000.0)])
		_add_loss(gs, a.tag, enemies, men, "surrendered")
		for e in enemies:
			var war: War = gs.war_between(a.tag, e)
			if war != null:
				war.add_log(Clock.date_string(), "surrender", "%s's %s was cut off at %s and lost (%dk men)." % [
						gs.nations[a.tag].display_name, a.display_name, MapData.provinces[a.province].name, roundi(men / 1000.0)], a.province)
		return
	_battle_event(gs, a.province, "%s's %s routed and fell back to %s." % [
			gs.nations[a.tag].display_name, a.display_name, MapData.provinces[best].name])
	var before := a.men()
	for u in a.units:
		u.strength *= 1.0 - cfg.combat.routed_loss
	_add_loss(gs, a.tag, enemies, before - a.men(), "losses")
	a.province = best
	a.path.clear()
	a.still_days = 0
	a.attacking = false
	a.fighting = false


static func _enemy_tags(gs: Node, a: Army, at: Dictionary) -> Array:
	var tags := []
	for b: Army in at.get(a.province, []):
		if gs.at_war(a.tag, b.tag) and not tags.has(b.tag):
			tags.append(b.tag)
	return tags


## Adds men to a war's tally for a nation ("losses", "attrition" or "surrendered"), split
## between the wars with the given enemies (or all its wars when none are given).
static func _add_loss(gs: Node, tag: String, enemies: Array, men: float, field: String) -> void:
	if men <= 0.0:
		return
	gs.nations[tag].men_lost_month += men
	gs.nations[tag].deaths_month += men
	var wars: Array[War] = []
	if enemies.is_empty():
		wars = gs.wars_of(tag)
	else:
		for e in enemies:
			var w: War = gs.war_between(tag, e)
			if w != null:
				wars.append(w)
	for w in wars:
		w[field][tag] += men / wars.size()


# ------------------------------------------------------------------ battle records

## The battle being fought in a province, started if it is new. Armies that join later are
## added to its starting strengths. The dictionary is the full account of the battle, kept
## when it ends (GameState.battle_by_id): id, province, name, terrain, dates, attacker,
## winner, active, per-side details in "sides" (armies, generals, compositions, strength,
## morale), a day-by-day "timeline" and a list of "events".
static func _engagement(gs: Node, id: int, foes: Dictionary) -> Dictionary:
	var battle: Dictionary = gs.engagements.get(id, {})
	var fresh := battle.is_empty()
	if fresh:
		battle = {"id": gs.next_battle_id, "province": id, "name": MapData.provinces[id].name, "terrain": terrain[id],
				"start_day": Clock.days_elapsed, "start_date": Clock.date_string(), "end_date": "", "days": 0,
				"attacker": "", "winner": "", "active": true,
				"start_men": {}, "lost": {}, "armies": {}, "sides": {}, "timeline": [], "events": []}
		gs.next_battle_id += 1
		gs.engagements[id] = battle
	var day: int = Clock.days_elapsed - battle.start_day + 1
	for a: Army in foes:
		if battle.armies.has(a.id):
			continue
		battle.armies[a.id] = true
		battle.start_men[a.tag] = battle.start_men.get(a.tag, 0.0) + a.men()
		if a.attacking and battle.attacker.is_empty():
			battle.attacker = a.tag
		if not battle.sides.has(a.tag):
			battle.sides[a.tag] = {"armies": {}, "generals": [], "comp_start": {}, "comp_now": {}, "comp_end": {},
					"men_now": 0.0, "men_end": 0.0, "morale": 1.0, "defense": 1.0}
		var side: Dictionary = battle.sides[a.tag]
		side.armies[a.id] = a.display_name
		if not a.general_name.is_empty() and not side.generals.has(a.general_name):
			side.generals.append(a.general_name)
		for type in a.composition():
			side.comp_start[type] = side.comp_start.get(type, 0) + a.composition()[type]
		if not fresh:
			battle.events.append("Day %d: %s's %s joins the battle." % [day, gs.nations[a.tag].display_name, a.display_name])
	if fresh:
		var defenders: PackedStringArray = []
		for tag in battle.sides:
			if tag != battle.attacker:
				defenders.append(gs.nations[tag].display_name)
		if battle.attacker.is_empty():
			battle.events.append("Day 1: armies clash at %s (%s)." % [battle.name, cfg.terrain[battle.terrain].name.to_lower()])
		else:
			battle.events.append("Day 1: %s attacks %s at %s (%s)." % [
					gs.nations[battle.attacker].display_name, " and ".join(defenders), battle.name, cfg.terrain[battle.terrain].name.to_lower()])
	return battle


## Adds the day's figures to a battle's timeline: men left, morale, losses and the
## defender's advantage, per nation.
static func _log_day(battle: Dictionary, foes: Dictionary, today: Dictionary) -> void:
	var men := {}
	var morale := {}
	var comp := {}
	var defense := {}
	for a: Army in foes:
		men[a.tag] = men.get(a.tag, 0.0) + a.men()
		morale[a.tag] = morale.get(a.tag, 0.0) + a.morale() * a.men()
		if not comp.has(a.tag):
			comp[a.tag] = {}
		for type in a.composition():
			comp[a.tag][type] = comp[a.tag].get(type, 0) + a.composition()[type]
		if not a.attacking:
			defense[a.tag] = maxf(defense.get(a.tag, 1.0), defense_multiplier(a))
	for tag in morale:
		morale[tag] = morale[tag] / men[tag] if men[tag] > 0.0 else 0.0
	for tag in battle.sides:
		var side: Dictionary = battle.sides[tag]
		side.men_now = men.get(tag, 0.0)
		side.morale = morale.get(tag, 0.0)
		side.comp_now = comp.get(tag, {})
		side.defense = defense.get(tag, 1.0)
	battle.timeline.append({"day": Clock.days_elapsed - battle.start_day + 1, "date": Clock.date_string(),
			"men": men, "lost": today, "morale": morale, "defense": defense})


## Notes something that happened in the battle in progress at a province, if there is one.
static func _battle_event(gs: Node, province: int, text: String) -> void:
	var battle: Dictionary = gs.engagements.get(province, {})
	if not battle.is_empty():
		battle.events.append("Day %d: %s" % [Clock.days_elapsed - battle.start_day + 1, text])


## Writes a finished battle into the record of each war it was part of, and keeps the full
## account in the archive. The winner is the one side still standing in the province.
static func _finish_engagement(gs: Node, id: int) -> void:
	var battle: Dictionary = gs.engagements[id]
	gs.engagements.erase(id)
	var present := {}
	var here_comp := {}
	for a in armies_at(gs, id):
		present[a.tag] = true
		if not here_comp.has(a.tag):
			here_comp[a.tag] = {"men": 0.0, "comp": {}}
		here_comp[a.tag].men += a.men()
		for type in a.composition():
			here_comp[a.tag].comp[type] = here_comp[a.tag].comp.get(type, 0) + a.composition()[type]
	var standing := []
	for tag in battle.start_men:
		if present.has(tag):
			standing.append(tag)
	var winner: String = standing[0] if standing.size() == 1 else ""
	var days: int = Clock.days_elapsed - battle.start_day + 1
	battle.active = false
	battle.winner = winner
	battle.days = days
	battle.end_date = Clock.date_string()
	for tag in battle.sides:
		battle.sides[tag].men_end = here_comp.get(tag, {}).get("men", 0.0)
		battle.sides[tag].comp_end = here_comp.get(tag, {}).get("comp", {})
	battle.events.append("Day %d: %s" % [days, "%s holds the field." % gs.nations[winner].display_name if not winner.is_empty() else "The fighting ends without a clear winner."])
	gs.battle_archive[battle.id] = battle
	while gs.battle_archive.size() > gs.MAX_ARCHIVED_BATTLES:
		gs.battle_archive.erase(gs.battle_archive.keys()[0])
	var tags: Array = battle.start_men.keys()
	var place: String = battle.name
	for i in tags.size():
		for j in range(i + 1, tags.size()):
			var war: War = gs.war_between(tags[i], tags[j])
			if war == null:
				continue
			var pair := [tags[i], tags[j]]
			var record := {"id": battle.id, "province": id, "name": place, "date": battle.start_date, "end_date": battle.end_date,
					"days": days, "attacker": battle.attacker if pair.has(battle.attacker) else "",
					"winner": winner if pair.has(winner) else "", "strength": {}, "lost": {}}
			for t in pair:
				record.strength[t] = battle.start_men[t]
				record.lost[t] = battle.lost.get(t, 0.0)
			war.add_battle(record)
			Peace.record_battle(war, record)
			record["loser"] = pair[0] if record.winner == pair[1] else pair[1]
			WarSupport.on_battle(gs, record)
			var result := "%s won." % gs.nations[record.winner].display_name if not record.winner.is_empty() else "No clear winner."
			war.add_log(Clock.date_string(), "battle", "Battle of %s (%d day%s): %s lost %dk of %dk, %s lost %dk of %dk. %s" % [
					place, days, "" if days == 1 else "s",
					gs.nations[tags[i]].display_name, roundi(record.lost[tags[i]] / 1000.0), roundi(record.strength[tags[i]] / 1000.0),
					gs.nations[tags[j]].display_name, roundi(record.lost[tags[j]] / 1000.0), roundi(record.strength[tags[j]] / 1000.0),
					result], id, battle.id)


## A nation with no province left in its hands cannot keep an army: whatever it has in the
## field or in training breaks up.
static func _collapse_nations(gs: Node) -> void:
	var holding := {}
	for id in range(1, gs.province_controller.size()):
		holding[gs.province_controller[id]] = true
	for tag in gs.nations:
		if holding.has(tag):
			continue
		var n: Nation = gs.nations[tag]
		var men := 0.0
		var had_any := not n.recruiting.is_empty()
		for a in armies_of(gs, tag):
			men += a.men()
			had_any = true
			gs.armies.erase(a.id)
		n.recruiting.clear()
		if not had_any:
			continue
		_add_loss(gs, tag, [], men, "surrendered")
		for war in gs.wars_of(tag):
			war.add_log(Clock.date_string(), "collapse", "%s holds no land: its armies (%dk men) disband." % [
					n.display_name, roundi(men / 1000.0)])
		gs.nation_collapsed.emit(tag, roundi(men))


## Supply attrition, reinforcement, morale recovery, digging in, and taking provinces.
## Returns true if any province changed hands.
static func _upkeep_and_occupy(gs: Node) -> bool:
	var armies: Array = gs.armies.values()
	var t_a := Time.get_ticks_usec() if profile else 0
	for a: Army in armies:
		if a.embarked():
			a.supplied = true
			continue
		if a.landing_days > 0:
			a.landing_days -= 1
		a.supplied = supply_cost(gs, a.tag, a.province) < INF
		if not a.supplied and a.landed_supply > 0:
			a.supplied = true
		if a.landed_supply > 0:
			a.landed_supply -= 1
		if not a.supplied:
			var before := a.men()
			for i in range(a.units.size() - 1, -1, -1):
				var u := a.units[i]
				u.strength -= cfg.supply.attrition
				u.morale = maxf(0.0, u.morale - cfg.supply.attrition_morale)
				if u.strength < cfg.combat.min_strength:
					a.units.remove_at(i)
			_add_loss(gs, a.tag, [], before - a.men(), "attrition")
		elif not a.fighting:
			var n: Nation = gs.nations[a.tag]
			var aura := city_aura(gs, a.tag, a.province)
			for u in a.units:
				u.morale = minf(1.0, u.morale + cfg.combat.morale_regain * (1.0 + float(cfg.cities.morale) * aura))
				if u.strength < 1.0 and n.manpower > 0:
					var want := minf(1.0 - u.strength, cfg.supply.reinforce_rate * (1.0 + float(cfg.cities.reinforce) * aura))
					var taken := mini(n.manpower, ceili(want * u.full_size()))
					n.manpower -= taken
					u.strength = minf(1.0, u.strength + float(taken) / u.full_size())
		if a.fighting and not a.units.is_empty():
			# A city's aura steadies the men even in battle.
			var steady := city_aura(gs, a.tag, a.province) * float(cfg.cities.morale) * float(cfg.cities.morale_fighting)
			if steady > 0.0:
				for u in a.units:
					u.morale = minf(1.0, u.morale + cfg.combat.morale_regain * steady)
		if a.path.is_empty():
			a.still_days += 1
	for a: Army in armies:
		if a.units.is_empty():
			gs.armies.erase(a.id)
	_note("occupy.upkeep", t_a)
	var t_b := Time.get_ticks_usec() if profile else 0

	var captured := false
	var at := _by_province(gs.armies.values())
	for id: int in at:
		var here: Array = at[id]
		var holder: String = gs.province_controller[id]
		var occupier := ""
		for a: Army in here:
			if a.tag == holder or not gs.at_war(a.tag, holder):
				continue
			var contested := false
			for b: Army in here:
				if gs.at_war(a.tag, b.tag):
					contested = true
			if not contested:
				occupier = a.tag
				break
		if occupier.is_empty():
			gs.occupation.erase(id)
			continue
		var progress: Dictionary = gs.occupation.get(id, {})
		if progress.get("tag", "") != occupier:
			progress = {"tag": occupier, "days": 0}
		progress.days += 1
		gs.occupation[id] = progress
		if progress.days >= terrain_of(id).occupy_days:
			gs.occupation.erase(id)
			gs.set_controller(id, occupier)
			captured = true
			var war: War = gs.war_between(occupier, holder)
			if war != null:
				war.captured[occupier].provinces += 1
				war.captured[occupier].population += gs.province_population[id]
				war.add_log(Clock.date_string(), "capture", "%s occupied %s (%d people) from %s." % [
						gs.nations[occupier].display_name, MapData.provinces[id].name,
						gs.province_population[id], gs.nations[holder].display_name], id)
	for id: int in gs.occupation.keys():
		if not at.has(id):
			gs.occupation.erase(id)
	return captured
