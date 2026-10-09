class_name AINavy
extends RefCounted
## The AI at sea. A nation at war sorts its fleets by role in port (transports and submarines
## apart, cruisers and destroyers detached as patrols), then gives every warfleet a sea zone:
## the cordon that would seal an enemy's ports from the open sea, the waters by its own ports
## where enemy ships lie, and the zone a landing needs an escort in. A fleet goes only where its
## power, with what is already sent there, is at least the nation's required odds times the
## enemy's power in and around the zone; otherwise it stays in port (a fleet in being). Worn
## fleets go home to repair. Building ships is part of the monthly budget (build). Landings are
## AILanding. Constants are in ai.json ("navy").
##
## State: GameState.ai_navy, tag -> {assign: {fleet id: zone}}.


## Fleets with armies aboard, refreshed at the start of each nation's turn.
static var _carrying := {}




static func cfg() -> Dictionary:
	return AI.cfg.navy


static func step(gs: Node, tag: String) -> void:
	if AI.enemies(gs, tag).is_empty():
		return
	var mem: Dictionary = gs.ai_navy.get(tag, {})
	if mem.is_empty():
		mem = {"assign": {}}
		gs.ai_navy[tag] = mem
	_carrying = Navy.fleets_with_armies(gs)
	_organize(gs, tag)
	_station(gs, tag, mem)


# --- Roles -------------------------------------------------------------------------------------

## "transport" (carries men, does not fight), "raider" (only submarines) or "warfleet".
static func role(f: Fleet) -> String:
	var war := 0
	var subs := 0
	for s in f.ships:
		if s.type == "submarine":
			subs += 1
		elif s.type != "transport":
			war += 1
	if war == 0 and subs == 0:
		return "transport"
	if war == 0:
		return "raider"
	return "warfleet"


static func _free(gs: Node, f: Fleet) -> bool:
	return f.is_in_port() and not f.is_moving() and not f.fighting and f.landing == 0 and not _carrying.has(f.id)


## Splits mixed fleets in port: transports and submarines go apart, and a big fleet sends half
## of its cruisers and destroyers out as a patrol.
static func _organize(gs: Node, tag: String) -> void:
	var c := cfg()
	var splits := 0
	var patrols := 0
	for f in Navy.fleets_of(gs, tag):
		if f.display_name.ends_with("patrol"):
			patrols += 1
	for f in Navy.fleets_of(gs, tag):
		# A fleet may need more than one split (transports, then submarines, then a patrol).
		for _i in 3:
			if splits >= int(c.max_splits):
				return
			if not _free(gs, f) or f.ships.size() < 2:
				break
			var picked: Array[int] = []
			var label := ""
			var carry := f.count_of("transport")
			var subs := f.count_of("submarine")
			if carry > 0 and carry < f.ships.size():
				picked = SplitFleet.indices_of_type(f, "transport", carry)
				label = "%s transports" % f.display_name
			elif subs > 0 and subs < f.ships.size():
				picked = SplitFleet.indices_of_type(f, "submarine", subs)
				label = "%s submarines" % f.display_name
			elif f.count_of("dreadnought") > 0 and patrols < int(c.max_patrols) 					and f.count_of("cruiser") + f.count_of("destroyer") >= int(c.patrol_min_screen):
				picked = SplitFleet.indices_of_type(f, "cruiser", f.count_of("cruiser") >> 1)
				picked.append_array(SplitFleet.indices_of_type(f, "destroyer", f.count_of("destroyer") >> 1))
				label = "%s patrol" % f.display_name
				patrols += 1
			if picked.is_empty() or picked.size() >= f.ships.size():
				break
			var cmd := SplitFleet.new(tag, f.id, picked)
			if not gs.issue_quiet(cmd):
				break
			gs.fleets[cmd.new_fleet_id].display_name = label
			splits += 1


# --- Where the enemy is ---------------------------------------------------------------------------

## Enemy fighting power bearing on each sea zone: in full where its ships are at sea, and cut by
## adj_decay in the zones next to them; fleets in port count port_share in the zones the port
## opens on, and less beyond.
static func enemy_map(gs: Node, tag: String) -> Dictionary:
	var c := cfg()
	var out := {}
	for f: Fleet in gs.fleets.values():
		if f.tag == tag or not gs.at_war(tag, f.tag):
			continue
		var p := f.power()
		if p <= 0.0:
			continue
		var bases: Array = []
		var weight := 1.0
		if f.port > 0:
			bases = MapData.zones_of_port(f.port)
			weight = float(c.port_share)
		elif f.zone > 0:
			bases = [f.zone]
		for z: int in bases:
			out[z] = out.get(z, 0.0) + p * weight
			for n: int in MapData.sea_adjacency[z]:
				out[n] = out.get(n, 0.0) + p * weight * float(c.adj_decay)
	return out


## Enemy power bearing on a zone (see enemy_map).
static func enemy_power_at(gs: Node, tag: String, zone: int) -> float:
	return enemy_map(gs, tag).get(zone, 0.0)


## Blockade.port_weights, kept for the day: every nation's station and cordon ask for the same
## few nations' trade over and over, and it walks all their provinces.
static var _weight_day := -1
static var _weight_gs := 0
static var _weight_cache: Dictionary = {}


static func _weights(gs: Node, tag: String) -> Dictionary:
	if _weight_day != Clock.days_elapsed or _weight_gs != gs.get_instance_id():
		_weight_cache.clear()
		_weight_day = Clock.days_elapsed
		_weight_gs = gs.get_instance_id()
	if not _weight_cache.has(tag):
		_weight_cache[tag] = Blockade.port_weights(gs, tag)
	return _weight_cache[tag]


# --- Cordons ----------------------------------------------------------------------------------------

## The zones that, held together, would cut an enemy's ports off from the open sea: the shortest
## route from its port zones to an outlet is blocked at its narrowest zone, again and again, up to
## cordon_max zones. Fewer than that if the enemy's trade goes through few zones.
static func cordon_zones(gs: Node, enemy: String) -> Array[int]:
	# A cordon changes only as ground changes hands: it is kept for a few days.
	var key := "%s:%d:%d" % [enemy, gs.owner_version, Clock.days_elapsed / 6]
	var kept: Variant = _cordons.get(key)
	if kept != null and _cordon_gs == gs.get_instance_id():
		return kept
	if _cordon_gs != gs.get_instance_id() or _cordons.size() > 200:
		_cordons.clear()
		_cordon_gs = gs.get_instance_id()
	var out := _cordon_search(gs, enemy)
	_cordons[key] = out
	return out


static var _cordons: Dictionary = {}
static var _cordon_gs := 0


static func _cordon_search(gs: Node, enemy: String) -> Array[int]:
	var out: Array[int] = []
	var starts: Array[int] = []
	for z in _weights(gs, enemy):
		starts.append(z)
	starts.sort()
	if starts.is_empty():
		return out
	var outlets := Blockade.outlet_zones()
	for _i in int(cfg().cordon_max):
		var path := _route(starts, outlets, out)
		if path.is_empty():
			return out
		var pick := 0
		var best := INF
		for z in path:
			var score := float(MapData.sea_adjacency[z].size()) + (4.0 if starts.has(z) else 0.0) + (3.0 if outlets.has(z) else 0.0)
			for n: int in MapData.sea_adjacency[z]:
				if starts.has(n):
					score += 1.5
					break
			if score < best - 0.000001:
				best = score
				pick = z
		out.append(pick)
	return out


## A shortest route (fewest zones) from any start to any goal avoiding the blocked zones.
static func _route(starts: Array[int], goals: Array[int], blocked: Array[int]) -> Array[int]:
	var prev := {}
	var seen := {}
	var queue: Array[int] = []
	for z in starts:
		if not blocked.has(z):
			seen[z] = true
			queue.append(z)
	var i := 0
	while i < queue.size():
		var z: int = queue[i]
		i += 1
		if goals.has(z):
			var path: Array[int] = [z]
			while prev.has(path[0]):
				path.push_front(prev[path[0]])
			return path
		for n: int in MapData.sea_adjacency[z]:
			if not seen.has(n) and not blocked.has(n):
				seen[n] = true
				prev[n] = z
				queue.append(n)
	return []


# --- Stationing -----------------------------------------------------------------------------------------

## What each sea zone is worth to the nation now: {importance: {zone: value}, cordon: {zone: true}}.
static func targets(gs: Node, tag: String, enemies_at: Dictionary) -> Dictionary:
	var c := cfg()
	var value := {}
	var cordon := {}
	var offence := {}
	# An enemy's trade is worth cutting in proportion to its size next to the biggest enemy's.
	var trade := {}
	var biggest := 0.0
	for e in AI.enemies(gs, tag):
		var sum := 0.0
		var weights := _weights(gs, e)
		for z in weights:
			sum += weights[z]
		trade[e] = sum
		biggest = maxf(biggest, sum)
	for e in AI.enemies(gs, tag):
		var zones := cordon_zones(gs, e)
		var share: float = trade[e] / biggest if biggest > 0.0 else 0.0
		for z in zones:
			value[z] = value.get(z, 0.0) + float(c.w_blockade) * share / zones.size()
			cordon[z] = true
			offence[z] = true
	var weights := _weights(gs, tag)
	var total := 0.0
	for z in weights:
		total += weights[z]
	for z: int in weights:
		if enemies_at.get(z, 0.0) > 0.0:
			value[z] = value.get(z, 0.0) + float(c.w_defend) * weights[z] / total
	for f: Fleet in gs.fleets.values():
		if f.tag != tag and gs.at_war(tag, f.tag) and f.zone > 0 and f.port == 0 and f.power() >= 1.0:
			value[f.zone] = value.get(f.zone, 0.0) + float(c.w_kill)
			offence[f.zone] = true
	var landing: Variant = gs.ai_landing.get(tag)
	if landing != null and landing.get("zone", 0) > 0:
		value[landing.zone] = value.get(landing.zone, 0.0) + float(c.w_escort)
		offence[landing.zone] = true
	return {"importance": value, "cordon": cordon, "offence": offence}


static func _mean_strength(f: Fleet) -> float:
	var total := 0.0
	for s in f.ships:
		total += s.strength
	return total / maxf(f.ships.size(), 1)


static func _shortest_range(f: Fleet) -> int:
	var shortest := 9999
	for s in f.ships:
		shortest = mini(shortest, s.def().range_days)
	return shortest


## Whether a fleet at sea is worn and should go home.
static func _worn(f: Fleet) -> bool:
	if f.is_in_port():
		return false
	return _mean_strength(f) < float(cfg().repair_below) or f.days_out > _shortest_range(f) * float(cfg().range_factor)


## Where a fleet is heading: its last zone, or 0 (see _heading_port).
static func _heading_zone(f: Fleet) -> int:
	return f.path.back() if not f.path.is_empty() and f.dest_port == 0 else 0


static func _go_zone(gs: Node, tag: String, f: Fleet, zone: int) -> void:
	if f.port == 0 and f.zone == zone and not f.is_moving():
		return
	if _heading_zone(f) == zone:
		return
	gs.issue_quiet(MoveFleet.new(tag, f.id, zone))


static func go_home(gs: Node, tag: String, f: Fleet) -> void:
	if f.is_in_port() and not f.is_moving():
		return
	if f.dest_port > 0:
		return
	var p := Navy.nearest_port(gs, f)
	if p > 0 and not (p == f.port and not f.is_moving()):
		gs.issue_quiet(MoveFleet.new(tag, f.id, 0, p))


static func _set_mission(gs: Node, tag: String, f: Fleet, mission: String) -> void:
	if f.mission != mission:
		gs.issue_quiet(SetFleetMission.new(tag, f.id, mission))


## The sea zones within `theatre_hops` of where a fleet is (or of the zones its port opens on).
static func _theatre(f: Fleet) -> Dictionary:
	var seen := {}
	var edge: Array = MapData.zones_of_port(f.port) if f.is_in_port() else [f.zone]
	for z: int in edge:
		seen[z] = true
	for _i in int(cfg().theatre_hops):
		var next: Array = []
		for z: int in edge:
			for n: int in MapData.sea_adjacency[z]:
				if not seen.has(n):
					seen[n] = true
					next.append(n)
		edge = next
	return seen


## Which of a nation's fleets belong to a force at least as strong as the enemy navies it could
## meet: {fleet id: bool}. Fleets within `theatre_hops` zones of each other form one force, and
## the enemy fleets within that distance of any of them are weighed against it (ships far away on
## other seas do not count, so Britain is not weighed against the Austrian fleet in the
## Adriatic). A navy that is not strong keeps to its own waters.
static func _strength(gs: Node, tag: String, fleets: Array[Fleet]) -> Dictionary:
	var theatres: Array[Dictionary] = []
	var parent: Array[int] = []
	for i in fleets.size():
		theatres.append(_theatre(fleets[i]))
		parent.append(i)
	for i in fleets.size():
		for j in range(i + 1, fleets.size()):
			if _in_theatre(theatres[i], fleets[j]):
				var a := i
				while parent[a] != a:
					a = parent[a]
				var b := j
				while parent[b] != b:
					b = parent[b]
				parent[maxi(a, b)] = mini(a, b)
	var own := {}
	var seen := {}
	for i in fleets.size():
		var root := i
		while parent[root] != root:
			root = parent[root]
		own[root] = own.get(root, 0.0) + fleets[i].power()
		if not seen.has(root):
			seen[root] = {}
		seen[root].merge(theatres[i])
	var theirs := {}
	for g: Fleet in gs.fleets.values():
		if g.tag == tag or not gs.at_war(tag, g.tag):
			continue
		for root: int in seen:
			if _in_theatre(seen[root], g):
				theirs[root] = theirs.get(root, 0.0) + g.power()
	var out := {}
	for i in fleets.size():
		var root := i
		while parent[root] != root:
			root = parent[root]
		out[fleets[i].id] = own[root] >= theirs.get(root, 0.0) * float(cfg().sortie_ratio)
	return out


static func _in_theatre(theatre: Dictionary, f: Fleet) -> bool:
	var zones: Array = MapData.zones_of_port(f.port) if f.is_in_port() else [f.zone]
	for z: int in zones:
		if theatre.has(z):
			return true
	return false


static func _station(gs: Node, tag: String, mem: Dictionary) -> void:
	var c := cfg()
	var odds := AI.required_odds(gs, tag)
	var enemies_at := enemy_map(gs, tag)
	var t := targets(gs, tag, enemies_at)
	var zones: Array = t.importance.keys()
	zones.sort()
	var committed := {}
	var fleets: Array[Fleet] = []
	for f in Navy.fleets_of(gs, tag):
		if role(f) == "transport":
			if not f.is_in_port() and not f.is_moving() and f.landing == 0 and not _carrying.has(f.id):
				go_home(gs, tag, f)
			continue
		fleets.append(f)
	fleets.sort_custom(func(a: Fleet, b: Fleet) -> bool: return a.power() > b.power() or (a.power() == b.power() and a.id < b.id))
	var day_cache := {}
	var strong := _strength(gs, tag, fleets)
	var assign: Dictionary = mem.assign
	for id: int in assign.keys():
		if not gs.fleets.has(id):
			assign.erase(id)
	for f in fleets:
		if f.fighting or f.retreating or _carrying.has(f.id):
			if f.zone > 0:
				committed[f.zone] = committed.get(f.zone, 0.0) + f.power()
			continue
		if _worn(f):
			assign.erase(f.id)
			go_home(gs, tag, f)
			continue
		if f.is_in_port() and _mean_strength(f) < float(c.ready_strength):
			assign.erase(f.id)
			continue
		var previous: int = assign.get(f.id, 0)
		var starts: Array = MapData.zones_of_port(f.port) if f.is_in_port() else [f.zone]
		var best := 0
		var best_score := -INF
		var day_key := [f.speed(), starts]
		if not day_cache.has(day_key):
			day_cache[day_key] = Navy.days_to_all(f.speed(), starts)
		var days: Dictionary = day_cache[day_key]
		for z: int in zones:
			if t.offence.has(z) and not t.importance.has(z):
				continue
			if t.offence.has(z) and role(f) != "raider" and not strong.get(f.id, false):
				continue
			var need := odds * float(enemies_at.get(z, 0.0))
			var have := f.power() + float(committed.get(z, 0.0))
			if need > 0.0 and have < need:
				continue
			if not days.has(z):
				continue
			# A zone already held is worth less to a second fleet, unless it is still outgunned.
			var worth := float(t.importance[z])
			if float(committed.get(z, 0.0)) >= maxf(need, float(Navy.cfg.blockade.min_power)):
				worth *= float(c.stack_decay)
			var score: float = worth - float(c.w_days) * float(days[z])
			if z == previous:
				score += float(c.hysteresis)
			if score > best_score + 0.000001:
				best = z
				best_score = score
		if best == 0 or best_score < float(c.min_score):
			assign.erase(f.id)
			go_home(gs, tag, f)
			continue
		assign[f.id] = best
		committed[best] = committed.get(best, 0.0) + f.power()
		# A fleet in a port that opens on a zone it only guards already does so; holding a zone
		# (a cordon, a hunt) means being at sea in it.
		if f.is_in_port() and not f.is_moving() and starts.has(best) and not t.offence.has(best):
			continue
		_go_zone(gs, tag, f, best)
		_set_mission(gs, tag, f, "raid" if role(f) == "raider" else ("blockade" if t.cordon.has(best) else "patrol"))


# --- Building ships ---------------------------------------------------------------------------------------

## Once a month, at war: one squadron if the nation's fleet is smaller than the enemies', the
## type furthest below its share, at the best yard, within the nation's means.
static func build(gs: Node, tag: String) -> void:
	var b: Dictionary = cfg().build
	if not b.enabled or gs.wars_of(tag).is_empty():
		return
	var n: Nation = gs.nations[tag]
	if n.shipbuilding.size() >= int(b.max_building):
		return
	var theirs := 0.0
	for f: Fleet in gs.fleets.values():
		if f.tag != tag and gs.at_war(tag, f.tag):
			theirs += f.power()
	var own := 0.0
	var have := {}
	for f in Navy.fleets_of(gs, tag):
		own += f.power()
		for s in f.ships:
			have[s.type] = have.get(s.type, 0) + 1
	for job in n.shipbuilding:
		own += float(Navy.cfg.types[job.type].attack)
		have[job.type] = have.get(job.type, 0) + 1
	var type := ""
	if gs.ai_navy_need.get(tag, "") == "transport":
		type = "transport"
	elif own < float(b.build_ratio) * theirs:
		type = _next_type(gs, tag, have)
	if type.is_empty():
		return
	var yard := _yard(gs, tag, type)
	if yard == 0:
		return
	var def: Dictionary = Navy.cfg.types[type]
	var plan: Dictionary = Navy.ship_plan(gs, tag, type, 1)
	if n.treasury - plan.total < float(b.build_floor):
		return
	var monthly_revenue := maxf(0.0, float(n.budget.get("revenue", 0.0))) / 12.0
	var in_hand: float = plan.total
	for job in n.shipbuilding:
		in_hand += float(Navy.cfg.types[job.type].cost)
	if in_hand > float(b.income_share) * monthly_revenue * float(b.horizon_months):
		return
	if float(n.budget.get("net", 0.0)) - float(def.upkeep) < -float(b.deficit_tolerance) * float(n.budget.get("revenue", 0.0)):
		return
	if gs.issue_quiet(RaiseShips.new(tag, yard, type, 1)) and type == "transport":
		gs.ai_navy_need.erase(tag)


## The ship type furthest below its share of the fleet that some yard of the nation can build.
static func _next_type(gs: Node, tag: String, have: Dictionary) -> String:
	var mix: Dictionary = cfg().build.mix
	var total := 0.0
	for k in have:
		total += have[k]
	var best := ""
	var best_gap := -INF
	var types: Array = mix.keys()
	types.sort()
	for type: String in types:
		if _yard(gs, tag, type) == 0:
			continue
		var gap: float = float(mix[type]) - (float(have.get(type, 0)) / total if total > 0.0 else 0.0)
		if gap > best_gap + 0.000001:
			best = type
			best_gap = gap
	return best


## The nation's best yard for a type (highest level, then lowest id), or 0.
static func _yard(gs: Node, tag: String, type: String) -> int:
	var best := 0
	var best_level := 0
	for id: int in gs.nations[tag].provinces:
		if not Navy.build_problem(gs, tag, id, type, 1, false).is_empty():
			continue
		var level := Navy.port_level(gs, id)
		if level > best_level or (level == best_level and (best == 0 or id < best)):
			best = id
			best_level = level
	return best
