class_name Offensives
extends RefCounted
## The rules of plans of attack (see Offensive, docs/FRONTLINES.md stage F5). Each day:
##   - planning: a stack of an army with a plan, standing still on its front, builds planning; one marching or
##     fighting spends it (and with no plan it fades);
##   - a launched plan whose stacks have planned enough (or an aggressive one) attacks: on a broad push every stack goes
##     for the enemy province next to it that leads toward the target line; a spearhead gathers its army next to the next
##     enemy province on the way to its target and strikes it together. A stack attacks only at the odds and morale its
##     aggressiveness asks for;
##   - an invasion gathers the army in its port and, once enough of it is there and a fleet in the port has room for it,
##     sails it to the target (SendOverseas); the plan is then done;
##   - a phase whose provinces are all held is done: the plan turns to the next phase and plans for it again (the army's
##     border front has followed the ground taken, so the line it attacks from is the one it reached).
## Constants are in data/military.json "offensive".


static func cfg() -> Dictionary:
	return Military.cfg.get("offensive", {})


## The plan of an army (its army, if `a` is a detachment), or null.
static func of_army(gs: Node, a: Army) -> Offensive:
	var root := FrontSolver.root_of(gs, a)
	if root == null:
		return null
	for o: Offensive in gs.offensives.values():
		if o.army_id == root.id and not o.done:
			return o
	return null


## Whether a plan has the army's stacks in hand (a launched spearhead or invasion): the front does not spread them
## meanwhile.
static func controls(gs: Node, root: Army) -> bool:
	var o := of_army(gs, root)
	return o != null and o.active and o.kind != "broad"


## The mean planning of an army's stacks, weighted by divisions.
static func planning_of(gs: Node, root: Army) -> float:
	var total := 0.0
	var units := 0
	for s in FrontSolver.stacks_of(gs, root):
		total += s.planning * s.units.size()
		units += s.units.size()
	return total / units if units > 0 else 0.0


static func step_day(gs: Node) -> void:
	_plan(gs)
	for o: Offensive in gs.offensives.values().duplicate():
		var root: Army = gs.armies.get(o.army_id)
		if root == null:
			gs.offensives.erase(o.id)
			continue
		if o.done or not o.active:
			continue
		if o.kind == "invasion":
			_invasion(gs, o, root)
			continue
		var targets := o.targets()
		while not targets.is_empty() and targets.all(func(p: int) -> bool: return gs.province_controller[p] == o.tag):
			_next_phase(gs, o, root)
			targets = o.targets()
		if o.done:
			continue
		if not o.launched:
			if o.aggressiveness == "aggressive" or planning_of(gs, root) >= float(cfg().get("planning_ready", 0.5)):
				o.launched = true
			else:
				continue
		# What is left to take: a province of the line already held is no longer aimed at.
		var left := targets.filter(func(p: int) -> bool: return gs.province_controller[p] != o.tag)
		if o.kind == "spearhead":
			_spearhead(gs, o, root, targets[0])
		else:
			_push(gs, o, root, left)


## Planning goes up for stacks with a plan standing still on their front, and down for the rest.
static func _plan(gs: Node) -> void:
	var up := 1.0 / maxf(float(cfg().get("planning_days", 14)), 1.0)
	var down := 1.0 / maxf(float(cfg().get("planning_decay_days", 5)), 1.0)
	for a: Army in gs.armies.values():
		var root := FrontSolver.root_of(gs, a)
		var planned := root != null and of_army(gs, root) != null
		var on_front := false
		if planned and root.front_id != 0 and gs.fronts.has(root.front_id):
			on_front = (gs.fronts[root.front_id] as Front).provinces.has(a.province)
		if planned and on_front and a.path.is_empty() and not a.fighting:
			a.planning = minf(1.0, a.planning + up)
		else:
			a.planning = maxf(0.0, a.planning - down)


static func _next_phase(gs: Node, o: Offensive, root: Army) -> void:
	o.phase += 1
	o.launched = false
	if o.phase >= o.phases.size():
		o.done = true
		o.active = false
	# The push to the next line is planned afresh from the line reached.
	for s in FrontSolver.stacks_of(gs, root):
		s.planning = 0.0


## The odds of an attack on a province by this much power: it over what defends the province (each enemy stack's power
## times its terrain, trenches and works); INF where nobody defends.
static func odds(gs: Node, tag: String, power: float, province: int) -> float:
	var theirs := 0.0
	for b: Army in Military.armies_at(gs, province):
		if gs.at_war(tag, b.tag):
			theirs += b.power() * Military.defense_multiplier(b)
	return INF if theirs <= 0.0 else power / theirs


## Whether a stack with this power and morale may attack at these odds, by the plan's aggressiveness.
static func may_attack(o: Offensive, chances: float, morale: float) -> bool:
	var rule: Dictionary = cfg().get(o.aggressiveness, {"odds": 1.3, "morale": 0.5})
	return chances >= float(rule.odds) and morale >= float(rule.morale)


## A stack's power as it would attack: with its planning.
static func attack_power(a: Army) -> float:
	var was := a.attacking
	a.attacking = true
	var p := a.power()
	a.attacking = was
	return p


## Whether a stack is free to be given an attack: standing, not fighting, not sent somewhere by hand, on land.
static func _free(a: Army) -> bool:
	return a.path.is_empty() and not a.fighting and a.pin == 0 and not a.embarked() and not a.units.is_empty()


static func _hostile(gs: Node, tag: String, p: int) -> bool:
	var holder: String = gs.province_controller[p]
	return holder != tag and gs.at_war(tag, holder)


## How far a province is from the nearest of the targets (map pixels).
static func _to_targets(p: int, targets: Array[int]) -> float:
	var best := INF
	var at: Vector2 = MapData.provinces[p].center
	for t in targets:
		best = minf(best, at.distance_to(MapData.provinces[t].center))
	return best


## Sends a stack into a province (to attack it, or to gather next to the objective). The front leaves it alone until it
## gets there (pin).
static func _send(gs: Node, a: Army, to: int) -> bool:
	var route := Military.find_path(gs, a.tag, a.speed(), a.province, to)
	if route.is_empty():
		return false
	a.path = route
	a.move_days_left = Military.move_days(gs, a.tag, a.speed(), a.province, route[0])
	a.still_days = 0
	a.pin = to
	return true


## A broad push: every free stack picks the enemy province next to it that leads toward the targets (the one with the
## best odds), and the stacks that picked the same province attack it together when their power together gives good
## enough odds.
static func _push(gs: Node, o: Offensive, root: Army, targets: Array[int]) -> void:
	var by_target := {}
	for s in FrontSolver.stacks_of(gs, root):
		if not _free(s) or not may_attack(o, INF, s.morale()):
			continue
		var here := _to_targets(s.province, targets)
		var best := 0
		var best_odds := -1.0
		for n: int in Military.neighbors(s.province):
			if not _hostile(gs, o.tag, n) or _to_targets(n, targets) >= here:
				continue
			var chances := odds(gs, o.tag, attack_power(s), n)
			if chances > best_odds:
				best_odds = chances
				best = n
		if best != 0:
			if not by_target.has(best):
				by_target[best] = []
			by_target[best].append(s)
	for target: int in by_target:
		var power := 0.0
		var morale := 1.0
		for s: Army in by_target[target]:
			power += attack_power(s)
			morale = minf(morale, s.morale())
		if may_attack(o, odds(gs, o.tag, power, target), morale):
			for s: Army in by_target[target]:
				_send(gs, s, target)


## A spearhead: the army gathers next to the next enemy province on the way to the target and strikes it together once
## enough of it has gathered and the odds are good enough.
static func _spearhead(gs: Node, o: Offensive, root: Army, target: int) -> void:
	var objective := next_objective(gs, o.tag, target)
	if objective == 0:
		return
	var staging: Array[int] = []
	for n: int in Military.neighbors(objective):
		if gs.province_controller[n] == o.tag:
			staging.append(n)
	if staging.is_empty():
		return
	var stacks := FrontSolver.stacks_of(gs, root)
	var gathered: Array[Army] = []
	var total := 0
	var near := 0
	for s in stacks:
		total += s.units.size()
		if staging.has(s.province) and s.path.is_empty():
			gathered.append(s)
			near += s.units.size()
		elif _free(s):
			# Not there yet: to the nearest staging province.
			var best := staging[0]
			for p in staging:
				if MapData.provinces[p].center.distance_to(MapData.provinces[s.province].center) < MapData.provinces[best].center.distance_to(MapData.provinces[s.province].center):
					best = p
			_send(gs, s, best)
	var enough := float(near) >= float(total) * float(cfg().get("gather", 0.7)) or o.aggressiveness == "aggressive"
	if not enough or gathered.is_empty():
		return
	var power := 0.0
	var morale := 0.0
	for s in gathered:
		power += attack_power(s)
		morale += s.morale() * s.units.size()
	morale /= maxf(near, 1.0)
	if may_attack(o, odds(gs, o.tag, power, objective), morale):
		for s in gathered:
			if _free(s) or (s.pin == s.province and s.path.is_empty()):
				s.pin = 0
				_send(gs, s, objective)


## An invasion: the army's stacks march to the port; once `gather` of its divisions are there (all of them unless
## aggressive) and a fleet of the nation in the port has room for them, they sail to land on the target.
static func _invasion(gs: Node, o: Offensive, root: Army) -> void:
	var target := o.targets()[0] if not o.targets().is_empty() else 0
	if target == 0:
		return
	var total := 0
	var there: Array[int] = []
	var near := 0
	var men := 0.0
	for s in FrontSolver.stacks_of(gs, root):
		total += s.units.size()
		if s.province == o.port and s.path.is_empty() and not s.embarked():
			there.append(s.id)
			near += s.units.size()
			men += s.men()
		elif _free(s) and s.province != o.port:
			_send(gs, s, o.port)
	var share := 1.0 if o.aggressiveness != "aggressive" else float(cfg().get("gather", 0.7))
	if there.is_empty() or float(near) < float(total) * share:
		return
	for f: Fleet in Navy.fleets_in_port(gs, o.port):
		if f.tag == o.tag and Navy.free_capacity(gs, f) >= men:
			var sail := SendOverseas.new(o.tag, f.id, there, target)
			if sail.execute(gs):
				o.done = true
				o.active = false
				return


## Why an invasion is waiting, or "" (for the plan's label).
static func invasion_wait(gs: Node, o: Offensive) -> String:
	var root: Army = gs.armies.get(o.army_id)
	if root == null:
		return ""
	var men := 0.0
	for s in FrontSolver.stacks_of(gs, root):
		men += s.men()
	for f: Fleet in Navy.fleets_in_port(gs, o.port):
		if f.tag == o.tag and Navy.free_capacity(gs, f) >= men:
			return ""
	return "waiting for transports in %s" % MapData.provinces[o.port].name


## The enemy province a spearhead strikes next on its way to `target`: the target itself if it borders the nation's
## ground, else the enemy province next to the nation's ground nearest to the target.
static func next_objective(gs: Node, tag: String, target: int) -> int:
	if not _hostile(gs, tag, target) and gs.province_controller[target] == tag:
		return 0
	var best := 0
	var best_d := INF
	var at: Vector2 = MapData.provinces[target].center
	for id in range(1, gs.province_controller.size()):
		if not _hostile(gs, tag, id):
			continue
		var touches := false
		for n: int in Military.neighbors(id):
			if gs.province_controller[n] == tag:
				touches = true
				break
		if not touches:
			continue
		var d := at.distance_to(MapData.provinces[id].center)
		if d < best_d:
			best_d = d
			best = id
	return best
