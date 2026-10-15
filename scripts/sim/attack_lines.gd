class_name AttackLines
extends RefCounted
## The rules of attack lines (see AttackLine). Each day an active line either looks for a
## campaign for its group (AIOffense picks the target and the force, as it does for the AI) or
## runs the one it has. A line ends by itself when the war ends or its group is gone.


static func create(gs: Node, tag: String, group: ArmyGroup, enemy: String, front_id: int) -> AttackLine:
	var line := AttackLine.new()
	line.id = gs.next_attack_line_id
	gs.next_attack_line_id += 1
	line.tag = tag
	line.group_id = group.id
	line.enemy = enemy
	line.front_id = front_id
	line.display_name = "%s vs %s" % [group.display_name, gs.nations[enemy].display_name]
	gs.attack_lines[line.id] = line
	return line


static func of_group(gs: Node, group_id: int) -> AttackLine:
	for line: AttackLine in gs.attack_lines.values():
		if line.group_id == group_id:
			return line
	return null


## Why a line cannot be switched on, or "".
static func block(gs: Node, line: AttackLine) -> String:
	if not gs.army_groups.has(line.group_id):
		return "no_group"
	if not gs.at_war(line.tag, line.enemy):
		return "no_war"
	return ""


## Calls the attack off: armies on the march halt and the group's armies go back to the front.
static func stop(gs: Node, line: AttackLine) -> void:
	line.active = false
	var c: Dictionary = line.campaign
	line.campaign = {}
	line.wait = 0
	if c.is_empty():
		return
	var ids: Array[int] = []
	for id in c.get("armies", []):
		var a: Army = gs.armies.get(id)
		if a == null:
			continue
		ids.append(id)
		if not a.path.is_empty() and not a.embarked():
			gs.issue_quiet(MoveArmy.new(line.tag, id, a.province))
	_rejoin_front(gs, line, ids)


static func _rejoin_front(gs: Node, line: AttackLine, ids: Array[int]) -> void:
	if ids.is_empty() or not gs.fronts.has(line.front_id):
		return
	gs.issue_quiet(AssignToFront.new(line.tag, line.front_id, ids))


static func step_day(gs: Node) -> void:
	for line: AttackLine in gs.attack_lines.values().duplicate():
		var group: ArmyGroup = gs.army_groups.get(line.group_id)
		if group == null:
			gs.attack_lines.erase(line.id)
			continue
		if not line.active:
			continue
		if block(gs, line) != "":
			stop(gs, line)
			continue
		_step_line(gs, line, group)


static func _step_line(gs: Node, line: AttackLine, group: ArmyGroup) -> void:
	var c: Dictionary = line.campaign
	if not c.is_empty() and not AIOffense._alive(gs, line.tag, c):
		c = {}
		line.campaign = {}
		line.wait = Clock.days_elapsed + int(AI.cfg.offense.retry_days)
	if c.is_empty():
		if Clock.days_elapsed < line.wait:
			return
		c = _start(gs, line, group)
		if c.is_empty():
			line.wait = Clock.days_elapsed + int(AI.cfg.offense.retry_days)
			return
		line.campaign = c
	AIOffense._run(gs, line.tag, c)
	if c.get("done", false):
		var ids: Array[int] = []
		for id in c.armies:
			if gs.armies.has(id):
				ids.append(id)
		line.campaign = {}
		line.wait = Clock.days_elapsed + int(AI.cfg.offense.retry_days)
		_rejoin_front(gs, line, ids)


## The provinces the attack may aim at: enemy ground next to the front's line, or next to any
## ground the nation holds when the line is tied to no front.
static func _candidates(gs: Node, line: AttackLine) -> Array[int]:
	var front: Front = gs.fronts.get(line.front_id)
	if front == null:
		return AIOffense._frontier(gs, line.tag, line.enemy)
	var seen := {}
	for p in front.provinces:
		for n: int in Military.neighbors(p):
			if gs.province_controller[n] == line.enemy:
				seen[n] = true
	var out: Array[int] = []
	for n: int in seen:
		out.append(n)
	out.sort()
	return out


## Picks a target and the group's armies to send; returns the campaign ({} if nothing fits).
static func _start(gs: Node, line: AttackLine, group: ArmyGroup) -> Dictionary:
	var armies: Array[Army] = []
	for id in group.army_ids:
		var a: Army = gs.armies.get(id)
		if a != null and a.path.is_empty() and not a.fighting and not a.embarked() and gs.province_controller[a.province] == line.tag:
			armies.append(a)
	armies.sort_custom(func(x: Army, y: Army) -> bool: return x.power() > y.power() or (x.power() == y.power() and x.id < y.id))
	if armies.is_empty():
		return {}
	var pick := AIOffense._best_target(gs, line.tag, line.enemy, _candidates(gs, line), armies, INF, false)
	if pick.is_empty():
		return {}
	var ids: Array[int] = []
	for a: Army in pick.armies:
		ids.append(a.id)
	# The armies sent leave their front for the attack; they return to it afterwards.
	gs.issue_quiet(AssignToFront.new(line.tag, 0, ids))
	return {"enemy": line.enemy, "target": pick.target, "staging": pick.staging, "armies": ids,
			"phase": "gather", "started": Clock.days_elapsed, "line": line.id}
