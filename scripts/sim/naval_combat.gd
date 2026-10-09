class_name NavalCombat
extends RefCounted
## Fighting at sea: fleets of nations at war that share a zone may find each other, then fight
## every day until one leaves, breaks or is sunk. Also the daily upkeep of fleets: repair and
## morale in port, attrition beyond their range. Constants are in data/navy.json.


static func step_day(gs: Node) -> void:
	for f: Fleet in gs.fleets.values():
		f.fighting = false
	_fight(gs)
	for f: Fleet in gs.fleets.values():
		if f.ships.is_empty():
			gs.fleets.erase(f.id)
	_upkeep(gs)


## Deterministic stand-in for a dice roll: 0..999 from the zone, the day and the two fleets.
static func roll(zone: int, a: int, b: int) -> int:
	var lo := mini(a, b)
	var hi := maxi(a, b)
	var h := (zone * 73856093) ^ (Clock.days_elapsed * 19349663) ^ (lo * 83492791) ^ (hi * 40503)
	h = (h ^ (h >> 13)) * 1274126177
	return ((h ^ (h >> 16)) & 0x7fffffff) % 1000


## Mean detection of a fleet's ships, weighted by strength.
static func detection(f: Fleet) -> float:
	var total := 0.0
	var weight := 0.0
	for s in f.ships:
		total += s.def().detection * s.strength
		weight += s.strength
	return total / weight if weight > 0.0 else 0.0


## Whether two hostile fleets in one zone find each other today. Fleets already in a fight
## stay in it; otherwise each side has a chance by how well it sees.
static func contact(a: Fleet, b: Fleet) -> bool:
	if a.engaged and b.engaged:
		return true
	var base: float = Navy.cfg.combat.contact_base
	var pa := clampf(base * detection(a), 0.0, 1.0)
	var pb := clampf(base * detection(b), 0.0, 1.0)
	var p := 1.0 - (1.0 - pa) * (1.0 - pb)
	return roll(a.zone, a.id, b.id) < int(p * 1000.0)


## Firepower a fleet brings against another: its ships' power, with submarines blunted by the
## target's destroyer screen.
static func firepower(f: Fleet, target: Fleet) -> float:
	var screen := float(target.count_of("destroyer"))
	var sub_mult: float = 1.0 / (1.0 + Navy.cfg.combat.submarine_screen * screen)
	var total := 0.0
	for s in f.ships:
		var p := s.power()
		total += p * sub_mult if s.type == "submarine" else p
	return total


static func _fight(gs: Node) -> void:
	var by_zone := {}
	for f: Fleet in gs.fleets.values():
		if f.zone > 0 and f.port == 0:
			if not by_zone.has(f.zone):
				by_zone[f.zone] = []
			by_zone[f.zone].append(f)
	var routed: Array[Fleet] = []
	for zone: int in by_zone:
		var here: Array = by_zone[zone]
		var foes := {}
		if here.size() >= 2:
			for i in here.size():
				for j in range(i + 1, here.size()):
					var a: Fleet = here[i]
					var b: Fleet = here[j]
					if a.tag != b.tag and gs.at_war(a.tag, b.tag) and contact(a, b):
						foes[a] = foes.get(a, [])
						foes[a].append(b)
						foes[b] = foes.get(b, [])
						foes[b].append(a)
		if foes.is_empty():
			continue
		# Everyone's shots are fired before anyone's losses are counted.
		var incoming := {}
		for a in foes:
			incoming[a] = 0.0
		for b in foes:
			var share: float = WarSupport.morale_mult(gs, b.tag) / foes[b].size()
			for a in foes[b]:
				var shot: float = firepower(b, a) * share
				incoming[a] += shot
		var battle := _engagement(gs, zone, foes)
		var today := {}
		for a: Fleet in foes:
			a.fighting = true
			a.engaged = true
			var enemies := []
			for b: Fleet in foes[a]:
				if not enemies.has(b.tag):
					enemies.append(b.tag)
			var report := _damage(gs, a, incoming[a], enemies, battle)
			today[a.tag] = today.get(a.tag, 0.0) + report
		battle.timeline.append({"day": battle.days, "lost": today})
		gs.sea_battle_fought.emit(zone, foes.keys().map(func(f: Fleet) -> String: return f.tag))
		for a: Fleet in foes:
			if not a.ships.is_empty() and a.morale() < Navy.cfg.combat.rout_morale and not a.retreating:
				routed.append(a)
	for f in routed:
		_retreat(gs, f)
	# A fleet that no longer shares its zone with an enemy it can fight is free again, and a
	# battle with no hostile fleets left in the zone is over.
	for f: Fleet in gs.fleets.values():
		if f.ships.is_empty():
			continue
		if not f.fighting:
			f.engaged = false
	for zone: int in gs.sea_battles.keys():
		var hostile := false
		var here := Navy.fleets_in_zone(gs, zone)
		for a in here:
			for b in here:
				hostile = hostile or (a.engaged and b.engaged and gs.at_war(a.tag, b.tag))
		if not hostile:
			_finish_engagement(gs, zone)


## Damages a fleet by `points` of enemy fire. Hits fall on ships in proportion to their size
## and what is left of them; submarines are hard to hit unless the enemy has destroyers.
## Returns the squadrons' worth of strength lost.
static func _damage(gs: Node, f: Fleet, points: float, enemies: Array, battle: Dictionary) -> float:
	var c: Dictionary = Navy.cfg.combat
	var asw := false
	for b in gs.fleets.values():
		if b.zone == f.zone and enemies.has(b.tag) and b.count_of("destroyer") > 0:
			asw = true
	var weights := []
	var total_weight := 0.0
	for s in f.ships:
		var w: float = s.def().exposure * s.strength
		if s.type == "submarine" and not asw:
			w *= c.submarine_evasion
		weights.append(w)
		total_weight += w
	if total_weight <= 0.0 or points <= 0.0:
		return 0.0
	var lost := 0.0
	var crew_lost := 0.0
	var sunk: Array[Ship] = []
	var damage_frac := 0.0
	for i in f.ships.size():
		var s: Ship = f.ships[i]
		var hit: float = points * c.damage_per_point * weights[i] / total_weight / s.def().hull
		hit = minf(hit, s.strength)
		s.strength -= hit
		lost += hit
		crew_lost += hit * s.def().crew
		damage_frac = maxf(damage_frac, hit)
		s.morale = maxf(0.0, s.morale - (hit * c.morale_loss_per_damage + c.morale_loss_base))
		if s.strength < c.min_strength:
			sunk.append(s)
	for s in sunk:
		f.ships.erase(s)
		crew_lost += s.strength * s.def().crew
		battle.sunk[f.tag] = battle.sunk.get(f.tag, 0) + 1
		gs.nations[f.tag].ships_lost += 1
		gs.ship_sunk.emit(f.tag, f.zone, s.type)
		var text := "%s's %s lost a %s." % [gs.nations[f.tag].display_name, f.display_name, s.def().name.to_lower()]
		battle.events.append("Day %d: %s" % [battle.days, text])
		for e in enemies:
			var war: War = gs.war_between(f.tag, e)
			if war != null:
				war.add_log(Clock.date_string(), "sinking", "%s in the %s." % [text.trim_suffix("."), MapData.sea_zones[f.zone].name])
	battle.lost[f.tag] = battle.lost.get(f.tag, 0.0) + lost
	Military._add_loss(gs, f.tag, enemies, crew_lost, "losses")
	return lost


## A beaten fleet runs for the nearest port its nation may use. With none in reach it fights on.
static func _retreat(gs: Node, f: Fleet) -> void:
	var targets: Array = []
	var port_of := {}
	for z in range(1, MapData.sea_zones.size()):
		for p in MapData.ports_in_zone(z):
			if Navy.can_dock(gs, f.tag, p):
				targets.append(z)
				if not port_of.has(z):
					port_of[z] = p
				break
	var path := Navy.find_path(f.speed(), [f.zone], targets)
	if path.is_empty():
		return
	f.retreating = true
	var route := path.duplicate()
	route.pop_front()
	f.path.assign(route)
	f.dest_port = port_of[path[-1]]
	f.entering = false
	if f.path.is_empty():
		f.entering = true
		f.move_days_left = Navy.cfg.port_days
	else:
		f.move_days_left = Navy.zone_days(f.speed(), f.zone, f.path[0])
	var battle: Dictionary = gs.sea_battles.get(f.zone, {})
	if not battle.is_empty():
		battle.events.append("Day %d: %s's %s breaks and runs for %s." % [battle.days, gs.nations[f.tag].display_name,
				f.display_name, MapData.provinces[f.dest_port].name])


# ------------------------------------------------------------------ battle records

## The battle being fought in a zone, started if it is new. The dictionary is the full account
## of the battle, kept when it ends (GameState.sea_battle_by_id): id, zone, name, dates, winner,
## active, ships at the start and ships lost per nation, a timeline and a list of events.
static func _engagement(gs: Node, zone: int, foes: Dictionary) -> Dictionary:
	var battle: Dictionary = gs.sea_battles.get(zone, {})
	if battle.is_empty():
		battle = {"id": gs.next_battle_id, "zone": zone, "name": MapData.sea_zones[zone].name,
				"start_day": Clock.days_elapsed, "start_date": Clock.date_string(), "end_date": "", "days": 0,
				"winner": "", "active": true, "fleets": {}, "start_ships": {}, "lost": {}, "sunk": {},
				"timeline": [], "events": []}
		gs.next_battle_id += 1
		gs.sea_battles[zone] = battle
		var names: PackedStringArray = []
		for f: Fleet in foes:
			if not names.has(gs.nations[f.tag].display_name):
				names.append(gs.nations[f.tag].display_name)
		battle.events.append("Day 1: %s fleets meet in the %s." % [" and ".join(names), battle.name])
	battle.days = Clock.days_elapsed - battle.start_day + 1
	for f: Fleet in foes:
		if battle.fleets.has(f.id):
			continue
		battle.fleets[f.id] = true
		battle.start_ships[f.tag] = battle.start_ships.get(f.tag, 0) + f.ships.size()
		if battle.days > 1:
			battle.events.append("Day %d: %s's %s joins the battle." % [battle.days, gs.nations[f.tag].display_name, f.display_name])
	return battle


static func _finish_engagement(gs: Node, zone: int) -> void:
	var battle: Dictionary = gs.sea_battles[zone]
	gs.sea_battles.erase(zone)
	battle.active = false
	battle.end_date = Clock.date_string()
	# The winner is the side that lost the smaller share of what it brought.
	var best := ""
	var best_share := INF
	for tag in battle.start_ships:
		var share: float = battle.lost.get(tag, 0.0) / maxf(battle.start_ships[tag], 1)
		if share < best_share:
			best_share = share
			best = tag
	battle.winner = best
	battle.events.append("Day %d: the battle ends." % battle.days)
	gs.sea_battle_archive[battle.id] = battle
	for f: Fleet in gs.fleets.values():
		if f.zone == zone or f.port > 0:
			f.engaged = false
		if f.zone == zone and f.retreating and not f.is_moving():
			f.retreating = false


# ------------------------------------------------------------------ upkeep of fleets

## Repair and morale in port; attrition for fleets too long at sea.
static func _upkeep(gs: Node) -> void:
	var c: Dictionary = Navy.cfg
	for f: Fleet in gs.fleets.values():
		if f.is_in_port():
			f.days_out = 0
			f.retreating = false
			var level := Navy.port_level(gs, f.port)
			var held: bool = gs.province_controller[f.port] == f.tag or Navy.can_dock(gs, f.tag, f.port)
			for s in f.ships:
				s.morale = minf(1.0, s.morale + c.port_morale_regain)
				if held and not f.fighting:
					s.strength = minf(1.0, s.strength + c.repair_per_day * level)
			continue
		f.days_out += 1
		if f.fighting:
			continue
		for s in f.ships:
			s.morale = minf(1.0, s.morale + c.combat.morale_regain)
			if f.days_out > s.def().range_days:
				s.strength = maxf(c.range_floor, s.strength - c.range_attrition)
				s.morale = maxf(0.0, s.morale - c.range_attrition_morale)
		if f.retreating and not f.is_moving():
			f.retreating = false
