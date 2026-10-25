class_name AILanding
extends RefCounted
## The AI landing from the sea. A nation whose enemy cannot be reached over a land border, and
## which has transports in port and armies to spare, picks a coastal province the enemy holds,
## gathers the armies and the transports in one port, waits until its ships hold the landing zone
## and the route, then sends them with SendOverseas. After the landing the armies are ordinary
## ones: once the beachhead is taken the land offence carries on from it. A nation with no
## transports asks the budget for one (GameState.ai_navy_need).
##
## State: GameState.ai_landing, tag -> {enemy, target, port, fleet, armies, phase, started, zone};
## phase is "gather", "escort" or "sail". Constants are in ai.json ("navy" > "landing").


static func cfg() -> Dictionary:
	return AI.cfg.navy.landing


## Whether an army is part of a landing being prepared by the nation.
static func involves(gs: Node, tag: String, army_id: int) -> bool:
	var c: Variant = gs.ai_landing.get(tag)
	return c != null and army_id in c.armies


static func step(gs: Node, tag: String) -> void:
	var c: Variant = gs.ai_landing.get(tag)
	if c != null:
		if not _alive(gs, tag, c):
			_end(gs, tag)
			return
		_run(gs, tag, c)
		return
	if Clock.days_elapsed < gs.ai_landing_wait.get(tag, 0) or AI.enemies(gs, tag).is_empty():
		return
	c = _start(gs, tag)
	if c == null:
		gs.ai_landing_wait[tag] = Clock.days_elapsed + int(cfg().retry_days)
		return
	gs.ai_landing[tag] = c


static func _end(gs: Node, tag: String) -> void:
	gs.ai_landing.erase(tag)
	gs.ai_landing_wait[tag] = Clock.days_elapsed + int(cfg().retry_days)


static func _alive(gs: Node, tag: String, c: Dictionary) -> bool:
	var live: Array[int] = []
	for id in c.armies:
		if gs.armies.has(id):
			live.append(id)
	c.armies = live
	return not live.is_empty() and gs.fleets.has(c.fleet) and gs.at_war(tag, c.enemy)


# --- Choosing a landing --------------------------------------------------------------------------------

## Enemy coast that could be landed on.
static func _coast(gs: Node, tag: String, enemy: String) -> Array[int]:
	var out: Array[int] = []
	for id in range(1, gs.province_controller.size()):
		if gs.province_controller[id] == enemy and not MapData.zones_of_port(id).is_empty() and Military.can_enter(gs, tag, id):
			out.append(id)
	return out


static func _transports(gs: Node, tag: String) -> Array[Fleet]:
	var out: Array[Fleet] = []
	for f in Navy.fleets_of(gs, tag):
		if AINavy.role(f) == "transport" and AINavy._free(gs, f) and f.capacity() > 0:
			out.append(f)
	out.sort_custom(func(a: Fleet, b: Fleet) -> bool: return a.capacity() > b.capacity() or (a.capacity() == b.capacity() and a.id < b.id))
	return out


## The armies, nearest first by land, that a transport fleet can take from its port.
static func _force(gs: Node, tag: String, tf: Fleet, armies: Array[Army]) -> Dictionary:
	var reach := AI.hops_from(tf.port, int(cfg().reach_hops))
	var near: Array[Army] = []
	for a in armies:
		if reach.has(a.province) and not a.embarked():
			near.append(a)
	near.sort_custom(func(x: Army, y: Army) -> bool:
		var dx := AIOffense._km(x.province, tf.port)
		var dy := AIOffense._km(y.province, tf.port)
		return dx < dy or (dx == dy and x.id < y.id))
	var out: Array[Army] = []
	var power := 0.0
	var men := 0.0
	var units := 0
	for a in near:
		if men + a.men() > tf.capacity():
			continue
		out.append(a)
		men += a.men()
		power += a.power()
		units += a.units.size()
	return {"armies": out, "power": power, "units": units}


static func _start(gs: Node, tag: String) -> Variant:
	var armies := AIOffense._available(gs, tag)
	var enemies_by_coast := {}
	var any_coast := false
	for enemy in AI.enemies(gs, tag):
		if AIOffense._defensive(gs, tag, enemy) or not AIOffense._frontier(gs, tag, enemy).is_empty():
			continue
		var coast := _coast(gs, tag, enemy)
		if not coast.is_empty():
			enemies_by_coast[enemy] = coast
			any_coast = true
	if not any_coast or armies.is_empty():
		gs.ai_navy_need.erase(tag)
		return null
	var carriers := _transports(gs, tag)
	if carriers.is_empty():
		var have := false
		for f in Navy.fleets_of(gs, tag):
			have = have or AINavy.role(f) == "transport"
		if not have:
			gs.ai_navy_need[tag] = "transport"
		return null
	gs.ai_navy_need.erase(tag)
	var odds := AI.required_odds(gs, tag)
	var enemies_at := AINavy.enemy_map(gs, tag)
	var own_navy := 0.0
	for f in Navy.fleets_of(gs, tag):
		if AINavy.role(f) != "transport":
			own_navy += f.power()
	var best := {}
	for tf in carriers:
		var force := _force(gs, tag, tf, armies)
		if force.units < int(cfg().min_force):
			continue
		for enemy: String in enemies_by_coast:
			for target: int in enemies_by_coast[enemy]:
				var route := Navy.find_path(tf.speed(), MapData.zones_of_port(tf.port), MapData.zones_of_port(target))
				if route.is_empty() or not _clear(gs, tag, route):
					continue
				var zone: int = route[-1]
				if float(enemies_at.get(zone, 0.0)) * odds > own_navy * float(cfg().escort_share):
					continue
				var required := odds * AIOffense._resistance(gs, tag, target) / float(cfg().landing_penalty)
				if force.power < required:
					continue
				var margin := clampf(force.power / required - 1.0, 0.0, 2.0)
				var utility: float = AIOffense._worth(gs, tag, enemy, target) + float(cfg().w_margin) * margin \
						- float(cfg().w_days) * Navy.path_days(tf.speed(), route)
				if best.is_empty() or utility > best.utility + 0.000001:
					best = {"utility": utility, "target": target, "fleet": tf.id, "port": tf.port, "enemy": enemy,
							"armies": force.armies, "zone": zone}
	if best.is_empty() or best.utility < float(cfg().min_utility):
		return null
	var ids: Array[int] = []
	for a: Army in best.armies:
		ids.append(a.id)
	return {"enemy": best.enemy, "target": best.target, "port": best.port, "fleet": best.fleet, "armies": ids,
			"phase": "gather", "started": Clock.days_elapsed, "zone": best.zone}


## Whether no zone of a route is held against the nation.
static func _clear(gs: Node, tag: String, route: Array[int]) -> bool:
	for z in route:
		if not Blockade.blockaders(gs, tag, z).is_empty():
			return false
	return true


# --- Running a landing -----------------------------------------------------------------------------------------

static func _run(gs: Node, tag: String, c: Dictionary) -> void:
	var f: Fleet = gs.fleets[c.fleet]
	var age: int = Clock.days_elapsed - c.started
	match c.phase:
		"gather":
			var ready: bool = f.is_in_port() and f.port == c.port and not f.is_moving()
			if not ready and (not f.is_moving() or f.dest_port != c.port):
				gs.issue_quiet(MoveFleet.new(tag, f.id, 0, c.port))
			for id in c.armies.duplicate():
				var a: Army = gs.armies[id]
				if a.province == c.port and a.path.is_empty() and not a.fighting:
					continue
				ready = false
				if not a.path.is_empty() and a.path.back() == c.port:
					continue
				if not gs.issue_quiet(MoveArmy.new(tag, id, c.port)):
					c.armies.erase(id)
			if c.armies.is_empty() or age > int(cfg().gather_days):
				_end(gs, tag)
			elif ready:
				c.phase = "escort"
				c.started = Clock.days_elapsed
		"escort":
			var route := Navy.find_path(f.speed(), MapData.zones_of_port(c.port), MapData.zones_of_port(c.target))
			if route.is_empty() or age > int(cfg().escort_days) or gs.province_controller[c.target] == tag:
				_end(gs, tag)
				return
			c.zone = route[-1]
			var open: bool = _clear(gs, tag, route)
			var held: bool = Blockade.holds(gs, tag, c.zone) or AINavy.enemy_power_at(gs, tag, c.zone) <= 0.0
			if open and held:
				var ids: Array[int] = []
				ids.assign(c.armies)
				if gs.issue_quiet(SendOverseas.new(tag, f.id, ids, c.target)):
					c.phase = "sail"
					c.started = Clock.days_elapsed
				else:
					_end(gs, tag)
		"sail":
			var aboard: bool = false
			for id in c.armies:
				aboard = aboard or gs.armies[id].embarked()
			if aboard and f.is_in_port() and not f.is_moving():
				# Turned back by an enemy fleet and put into a port: the landing is off; the men go ashore there.
				for id in c.armies:
					gs.issue_quiet(DisembarkArmy.new(tag, id, f.port))
				_end(gs, tag)
			elif not aboard or age > int(cfg().sail_days):
				_end(gs, tag)
