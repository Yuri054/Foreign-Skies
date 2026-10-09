class_name Blockade
extends RefCounted
## Control of the sea and the blockade that follows from it. Each day every zone gets its
## holders (the nations with fighting ships there, none if enemies are both present), and each
## nation at war gets a blockade target from the share of its port trade that enemy-held zones
## cut off from the open sea. Nation.blockade drifts toward the target, so a single sortie changes little.
## Constants are in data/navy.json under "blockade".


static func step_day(gs: Node) -> void:
	update_control(gs)
	var cfg: Dictionary = Navy.cfg.blockade
	for tag in gs.nations:
		var n: Nation = gs.nations[tag]
		var target := n.blockade_target
		if n.blockade_pinned >= 0.0:
			target = n.blockade_pinned
			n.blockade = target
			n.blockade_target = target
			continue
		if not _has_enemy(gs, tag):
			target = 0.0
			n.blockade_by = []
		elif (Clock.days_elapsed + tag.hash()) % int(cfg.assess_days) == 0:
			var info := assess(gs, tag)
			target = info.target
			n.blockade_by = info.by
		n.blockade_target = target
		var before := n.blockade
		if target > n.blockade:
			n.blockade = minf(target, n.blockade + cfg.rise_per_day)
		elif target < n.blockade:
			n.blockade = maxf(target, n.blockade - cfg.fall_per_day)
		if absf(n.blockade - n.blockade_applied) >= cfg.recompute_step or (n.blockade == 0.0 and n.blockade_applied > 0.0):
			n.blockade_applied = n.blockade
			gs.economy_dirty = true
		if before != n.blockade:
			gs.blockade_changed.emit(tag, n.blockade)


static func _has_enemy(gs: Node, tag: String) -> bool:
	for other in gs.nations:
		if other != tag and gs.at_war(tag, other):
			return true
	return false


## Fills GameState.sea_control: zone id -> {holders: Array of tags, contested: bool, power: {tag: float}}.
## Only fleets at sea with real firepower count; ships in port and transports hold nothing.
## Where hostile nations both have such ships the zone is contested and nobody holds it.
static func update_control(gs: Node) -> void:
	var power := {}
	for f: Fleet in gs.fleets.values():
		if f.zone <= 0 or f.port > 0:
			continue
		if not power.has(f.zone):
			power[f.zone] = {}
		power[f.zone][f.tag] = power[f.zone].get(f.tag, 0.0) + f.power()
	var control := {}
	for zone: int in power:
		var tags: Array = []
		for tag: String in power[zone]:
			if power[zone][tag] >= Navy.cfg.blockade.min_power:
				tags.append(tag)
		if tags.is_empty():
			continue
		tags.sort()
		var contested := false
		for a: String in tags:
			for b: String in tags:
				if a != b and gs.at_war(a, b):
					contested = true
		control[zone] = {"holders": [] if contested else tags, "contested": contested, "power": power[zone]}
	gs.sea_control = control


## Whether a nation (or its friends) holds a zone: it has fighting ships there and no enemy does.
static func holds(gs: Node, tag: String, zone: int) -> bool:
	var c: Dictionary = gs.sea_control.get(zone, {})
	if c.is_empty() or c.contested:
		return false
	for h: String in c.holders:
		if h == tag or not gs.at_war(h, tag):
			return true
	return false


## The nations whose ships hold a zone against `tag`: enemies of `tag` and nobody else.
static func blockaders(gs: Node, tag: String, zone: int) -> Array:
	var out := []
	var c: Dictionary = gs.sea_control.get(zone, {})
	if c.is_empty() or c.contested:
		return out
	for h: String in c.holders:
		if gs.at_war(h, tag):
			out.append(h)
	return out


## How much each sea zone matters to a nation's trade: {zone: weight}. Every coastal province
## it holds counts by its output, more for ports and trading houses; a province opening on two
## zones gives most of its weight to the first.
static func port_weights(gs: Node, tag: String) -> Dictionary:
	var cfg: Dictionary = Navy.cfg.blockade
	var out := {}
	for id: int in gs.nations[tag].provinces:
		if gs.province_controller[id] != tag:
			continue
		var zones := MapData.zones_of_port(id)
		if zones.is_empty():
			continue
		var b: Dictionary = gs.province_buildings[id]
		var w: float = gs.province_gdp[id] * (cfg.base_weight + cfg.per_port_level * b.get("port", 0) + cfg.per_market_level * b.get("market", 0))
		if zones.size() == 1:
			out[zones[0]] = out.get(zones[0], 0.0) + w
		else:
			out[zones[0]] = out.get(zones[0], 0.0) + w * (1.0 - cfg.second_zone_share)
			out[zones[1]] = out.get(zones[1], 0.0) + w * cfg.second_zone_share
	return out


## Share of a nation's land border that does not face an enemy: trade that a blockade cannot
## reach because it crosses a neutral or friendly frontier.
static func open_border_share(gs: Node, tag: String) -> float:
	var total := 0
	var open := 0
	for id: int in gs.nations[tag].provinces:
		for nb: int in Military.neighbors(id):
			var other: String = gs.province_owner[nb]
			if other == tag:
				continue
			total += 1
			if not gs.at_war(tag, other):
				open += 1
	return float(open) / float(total) if total > 0 else 0.0


## Zones where the world's shipping enters and leaves the map (see "outlets" in navy.json).
static func outlet_zones() -> Array[int]:
	var out: Array[int] = []
	for z in range(1, MapData.sea_zones.size()):
		if Navy.cfg.blockade.outlets.has(MapData.sea_zones[z].name):
			out.append(z)
	return out


## Zones from which a nation's ships can still reach an outlet without crossing a zone an
## enemy holds. A port in any other zone has lost its trade.
static func open_zones(gs: Node, tag: String) -> Dictionary:
	var seen := {}
	var todo: Array[int] = []
	for z in outlet_zones():
		if blockaders(gs, tag, z).is_empty():
			seen[z] = true
			todo.append(z)
	while not todo.is_empty():
		var z: int = todo.pop_back()
		for n: int in MapData.sea_adjacency[z]:
			if not seen.has(n) and blockaders(gs, tag, n).is_empty():
				seen[n] = true
				todo.append(n)
	return seen


## What the enemy's grip on the sea cuts off: {target: 0..max, share, cap, by: [tags],
## zones: {zone: share of the nation's port trade}}. A port is cut off when no route from its
## zone reaches an outlet except through water an enemy holds, so a cordon of the right zones
## (the North Sea and the Channel against Germany) is enough without entering its harbours.
static func assess(gs: Node, tag: String) -> Dictionary:
	var cfg: Dictionary = Navy.cfg.blockade
	var weights := port_weights(gs, tag)
	var total := 0.0
	for z in weights:
		total += weights[z]
	var open := open_zones(gs, tag)
	var cut := 0.0
	var by := []
	var zones := {}
	for z: int in weights:
		if open.has(z):
			continue
		cut += weights[z]
		zones[z] = weights[z] / total
	if cut > 0.0:
		for z: int in gs.sea_control:
			for e in blockaders(gs, tag, z):
				if not by.has(e):
					by.append(e)
	by.sort()
	var share := cut / total if total > 0.0 else 0.0
	var cap: float = cfg.max * (1.0 - cfg.land_leak * open_border_share(gs, tag))
	return {"target": share * cap, "share": share, "cap": cap, "by": by, "zones": zones}
