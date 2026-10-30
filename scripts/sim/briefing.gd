class_name Briefing
extends RefCounted
## The cabinet briefing: what a nation should look at now, worst first, each with the reason in a line and the
## tab to open. Read-only: it reads the same state and numbers the panels and the AI use, and changes nothing.
## An issue is {id, severity (0 to 100), title, why, page} where `page` is the Nation screen tab to go to.

const MAX_ISSUES := 3


## Every issue of the nation, worst first.
static func issues(gs: Node, tag: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not gs.nations.has(tag):
		return out
	var n: Nation = gs.nations[tag]
	var b: Dictionary = n.budget
	var at_war: bool = not gs.wars_of(tag).is_empty()
	# The state of the war.
	if at_war and n.capital > 0 and gs.province_controller[n.capital] != tag:
		var holder: String = gs.province_controller[n.capital]
		_add(out, "capital", 96.0, "The capital has fallen", "%s holds %s. Retake it or make peace." % [gs.nations[holder].display_name, MapData.provinces[n.capital].name], "Military")
	var lost := 0
	for id: int in n.provinces:
		if gs.province_controller[id] != tag:
			lost += 1
	if at_war and lost > 0:
		_add(out, "occupied", minf(50.0 + lost * 3.0, 85.0), "%d of your provinces are occupied" % lost, "Their output and people are not yours while an enemy holds them. Push them out or negotiate.", "Military")
	if at_war and n.war_support <= 35.0:
		_add(out, "war_support", 80.0 - n.war_support * 0.5, "War support is %d" % roundi(n.war_support), "Below 25 the government accepts any peace; defeats and blockade wear it down, victories raise it.", "Diplomacy")
	for w: War in gs.wars_of(tag):
		if w.a == tag and not w.goal.is_empty() and WarGoal.progress(gs, w) < 0.5 and w.days_lasted(Clock.days_elapsed) > 120:
			_add(out, "goal_" + w.b, 45.0, "The war on %s is not reaching its goal" % gs.nations[w.b].display_name, "%s Take the ground or make a limited peace." % WarGoal.line(gs, w), "Military")
	# Money and building.
	if not b.is_empty():
		if n.treasury < 0.0:
			_add(out, "debt", 90.0, "The treasury is in debt: %s gold" % Fmt.money(-n.treasury), "Interest takes %s gold a month. Cut spending (the army, the navy, building upkeep) or raise income." % Fmt.money(b.interest), "Economy")
		elif b.net < 0.0 and n.treasury < -b.net * 6.0:
			var months := maxi(1, ceili(n.treasury / maxf(-b.net, 0.01)))
			_add(out, "deficit", 70.0 if months <= 6 else 50.0, "A deficit of %s gold a month" % Fmt.money(-b.net), "The treasury is empty in about %d months." % months, "Economy")
		if n.blockade > 0.1:
			_add(out, "blockade", 55.0 + n.blockade * 20.0, "A blockade cuts %d%% of your port income" % roundi(n.blockade * 100.0), "Break it with your fleet or make peace with the nation enforcing it.", "Navy")
		var cp_month := float(b.get("cp", 0.0)) * 30.0
		var factory: Dictionary = Economy.build_plan(gs, 0, "civilian_factory")
		if n.construction.is_empty() and n.cp >= factory.cp and n.treasury >= factory.gold:
			_add(out, "idle_industry", 35.0, "Nothing is being built", "You have %s gold and %d construction points (%d a month): enough for a civilian factory, which earns %s gold a month. Queue buildings." % [
					Fmt.money(n.treasury), roundi(n.cp), roundi(cp_month), Fmt.money(float(Economy.cfg.buildings.civilian_factory.income))], "Build")
		# Gold piling up in peace buys nothing: say what it could.
		var income: float = float(b.income)
		if not at_war and income > 0.0 and n.treasury > income * 12.0 and b.net > 0.0:
			var war_cost := Economy.mobilization_cost(gs, n, 1.0)
			var decade: float = Economy.division_upkeep(gs, n) * 120.0 + float(Military.cfg.unit_types.infantry.cost)
			var chest := "a war chest for %d months of full mobilization" % floori(n.treasury / war_cost) if war_cost > 0.01 else "a war chest"
			_add(out, "idle_money", 28.0, "%s gold lies idle in the treasury" % Fmt.money(n.treasury), "It could begin buildings, or raise and keep %d more divisions for ten years; as it is, it is %s." % [floori(n.treasury / maxf(decade, 0.001)), chest], "Economy")
	# Neighbours and Europe.
	for key: String in gs.alarms:
		if key.ends_with(">" + tag):
			var other := key.get_slice(">", 0)
			if gs.nations.has(other) and not gs.at_war(other, tag):
				_add(out, "alarm_" + other, 45.0, "%s is mobilizing near you" % gs.nations[other].display_name, "Its armies are drawing up on your border.", "Diplomacy")
	for c: Dictionary in gs.crises:
		if c.b == tag:
			_add(out, "crisis_%d" % c.id, 88.0, c.title, "Answer by %s: yield, refuse, mobilize or appeal." % Clock.date_after(c.deadline_day - Clock.days_elapsed), "Diplomacy")
		elif c.a != tag:
			var close: bool = Diplomacy.are_allied(gs, tag, c.a) or Diplomacy.are_allied(gs, tag, c.b) or c.a in Diplomacy.neighbor_nations(gs, tag) or c.b in Diplomacy.neighbor_nations(gs, tag)
			if close:
				_add(out, "crisis_%d" % c.id, 50.0, c.title, "You may mediate or stand behind a side before the answer is due.", "Diplomacy")
	var rival := AIDiplomacy.strongest_rival(gs, tag)
	if not rival.is_empty() and rival.ratio >= 1.0:
		_add(out, "rival", minf(40.0 + rival.ratio * 15.0, 75.0), "%s outweighs you %.1f to 1" % [gs.nations[rival.tag].display_name, rival.ratio], "It is a neighbour that does not like you. Make an alliance or a guarantee before it moves.", "Diplomacy")
	if gs.tension >= 45.0:
		var big := biggest_tension_part(gs)
		_add(out, "tension", gs.tension * 0.6, "Europe's tension is %d of 100" % roundi(gs.tension), "Mostly %s. The nearer it gets to war, the bolder the AI nations grow." % big.name.to_lower(), "Overview")
	# What is not being done.
	if n.focus.is_empty() and Focus.tree_of(tag).any(func(f: Dictionary) -> bool: return Focus.block(gs, tag, f.id) == ""):
		_add(out, "focus", 30.0, "No national focus chosen", "A focus is one lasting effort, such as an arms drive or a reform. Pick one.", "Focus")
	var points := Diplomacy.points(gs, tag)
	if points >= 60.0:
		_add(out, "points", 25.0, "%d diplomacy points are unspent" % roundi(points), "Spend them on treaties, gifts, improving relations or building a case.", "Diplomacy")
	out.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x.severity > y.severity or (x.severity == y.severity and x.id < y.id))
	return out


## The worst `count` issues.
static func top(gs: Node, tag: String, count := MAX_ISSUES) -> Array[Dictionary]:
	var all := issues(gs, tag)
	var out: Array[Dictionary] = []
	for i in mini(count, all.size()):
		out.append(all[i])
	return out


static func _add(out: Array[Dictionary], id: String, severity: float, title: String, why: String, page: String) -> void:
	out.append({"id": id, "severity": severity, "title": title, "why": why, "page": page})


## The largest part of Europe's tension: {key, name, value}.
static func biggest_tension_part(gs: Node) -> Dictionary:
	var p := Pressure.parts(gs)
	var best := {"key": "base", "name": "the general unease", "value": p.base}
	for key: String in Pressure.PART_NAMES:
		if p[key] > best.value:
			best = {"key": key, "name": Pressure.PART_NAMES[key], "value": p[key]}
	return best


## The great powers' worst rivalries, `count` pairs by how much they dislike each other: [{a, b, hostility 0..1}].
static func rivalries(gs: Node, count := 3) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var great: Array = Pressure.GREAT
	for i in great.size():
		for j in range(i + 1, great.size()):
			if gs.nations.has(great[i]) and gs.nations.has(great[j]):
				var h := clampf(-Diplomacy.relation(gs, great[i], great[j]) / 100.0, 0.0, 1.0)
				if h > 0.0:
					out.append({"a": great[i], "b": great[j], "hostility": h})
	out.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x.hostility > y.hostility)
	return out.slice(0, count)
