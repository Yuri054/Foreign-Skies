class_name Pressure
extends RefCounted
## Historical pressure: how close Europe is to a great war, and the events that push it there or hold
## it off. There is no score and no scripted outcome; the pressure is a number (tension, 0 to 100) made of
## the arms race, mobilization, hostile great powers and wars, plus the lasting force of events. Tension
## makes the AI bolder and hardens the rivalries between the great powers. Events (data/events.json) are
## the crises of 1900 to 1914; the player answers those that concern their nation, the rest happen by
## the AI's choice and are news. Static, like Diplomacy; the state lives in GameState (tension, events_fired,
## pending_events, chronicle).

const CONFIG_PATH := "res://data/events.json"
const GREAT := ["GBR", "FRA", "GER", "RUS", "AUH", "ITA"]
const CHRONICLE_MAX := 40

static var cfg: Dictionary = {}
static var events: Array = []


static func load_config() -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	assert(data is Dictionary, "events.json is invalid")
	cfg = data.tension
	events = data.events


## Starts a scenario: no events fired, tension at what the world's armies and quarrels make it.
static func load_scenario(gs: Node) -> void:
	gs.events_fired.clear()
	gs.appeal_ready.clear()
	gs.pending_events.clear()
	gs.chronicle.clear()
	gs.tension_history.clear()
	gs.pressure_start = _month_index()
	gs.pressure_ai = bool(gs.scenario.get("pressure_ai", false))
	gs.tension_impulse = float(gs.scenario.get("start_tension", 0.0))
	gs.next_event_uid = 1
	gs.tension_arms_base = maxf(_great_men(gs), 1.0)
	_update(gs)
	gs.tension_history.append(gs.tension)


static func _great_men(gs: Node) -> float:
	var total := 0.0
	for tag: String in GREAT:
		if gs.nations.has(tag):
			total += float(gs.nations[tag].men_in_units)
	return total


## The parts of tension, for the screen: {base, arms, mobilization, wars, rivalry, events, total}.
static func parts(gs: Node) -> Dictionary:
	var arms := clampf((_great_men(gs) / gs.tension_arms_base - 1.0) * float(cfg.arms_weight), 0.0, float(cfg.arms_max))
	var mob := 0.0
	for tag: String in GREAT:
		if gs.nations.has(tag):
			mob += maxf(0.0, gs.nations[tag].mobilization - float(cfg.mobilization_from))
	mob = clampf(mob * float(cfg.mobilization_weight), 0.0, float(cfg.mobilization_max))
	var wars := 0
	for w: War in gs.wars.values():
		if w.a in GREAT or w.b in GREAT:
			wars += 1
	var war_part := minf(float(cfg.war_max), wars * float(cfg.war_each))
	var hostility := 0.0
	var pairs := 0
	for i in GREAT.size():
		for j in range(i + 1, GREAT.size()):
			if gs.nations.has(GREAT[i]) and gs.nations.has(GREAT[j]):
				hostility += clampf(-Diplomacy.relation(gs, GREAT[i], GREAT[j]) / 100.0, 0.0, 1.0)
				pairs += 1
	var rivalry := hostility / maxf(pairs, 1) * float(cfg.rivalry_weight)
	rivalry += float(cfg.bloc_weight) if _two_blocs(gs) else 0.0
	var total := clampf(float(cfg.base) + arms + mob + war_part + rivalry + gs.tension_impulse, 0.0, 100.0)
	return {"base": float(cfg.base), "arms": arms, "mobilization": mob, "wars": war_part, "rivalry": rivalry,
			"events": gs.tension_impulse, "total": total}


## Whether the AI may start a war of its own choosing: Europe must be tense enough.
static func ai_may_declare(gs: Node) -> bool:
	return not gs.pressure_ai or gs.tension >= float(cfg.ai_war_gate)


## Whether the great powers stand in two alliance circles of at least two each, the shape of 1914.
static func _two_blocs(gs: Node) -> bool:
	var circles := 0
	var seen: Array[String] = []
	for tag: String in GREAT:
		if tag in seen or not gs.nations.has(tag):
			continue
		var members: Array[String] = Diplomacy.alliance_circle(gs, tag).filter(func(t: String) -> bool: return t in GREAT)
		seen.append_array(members)
		if members.size() >= 2:
			circles += 1
	return circles >= 2


static func _update(gs: Node) -> void:
	gs.tension = parts(gs).total
	var from := float(cfg.aggression_from)
	gs.tension_bonus = 0.0 if not gs.pressure_ai else float(cfg.aggression_gain) * clampf((gs.tension - from) / (100.0 - from), 0.0, 1.0)


static func step_month(gs: Node) -> void:
	gs.tension_impulse = minf(gs.tension_impulse * (1.0 - float(cfg.impulse_decay)), float(cfg.impulse_max))
	_fire_events(gs)
	_update(gs)
	if gs.tension >= float(cfg.harden_above):
		for i in GREAT.size():
			for j in range(i + 1, GREAT.size()):
				var a: String = GREAT[i]
				var b: String = GREAT[j]
				if gs.nations.has(a) and gs.nations.has(b) and not Diplomacy.are_allied(gs, a, b) and Diplomacy.relation(gs, a, b) < 0.0:
					Diplomacy._shift_baseline(gs, a, b, -float(cfg.harden_per_month))
	gs.tension_history.append(gs.tension)
	if gs.tension_history.size() > 240:
		gs.tension_history.remove_at(0)


# --- Events ----------------------------------------------------------------------------------

static func _month_index() -> int:
	return Clock.year * 12 + Clock.month


static func _index_of(date: Array) -> int:
	return int(date[0]) * 12 + int(date[1])


static func _fire_events(gs: Node) -> void:
	var now := _month_index()
	for e: Dictionary in events:
		if now < _index_of(e.date) or (e.has("until") and now > _index_of(e.until)):
			continue
		# A dated event from before the scenario began has already happened (its effects are in the start).
		if _index_of(e.date) < gs.pressure_start and not e.has("repeat_months"):
			continue
		var last: int = gs.events_fired.get(e.id, -1)
		if last >= 0 and (not e.has("repeat_months") or now - last < int(e.repeat_months)):
			continue
		if e.has("requires_event") and not gs.events_fired.has(e.requires_event):
			continue
		if not _condition_ok(gs, e):
			continue
		var roles := _roles(gs, e)
		if roles.is_empty() and not e.actors.is_empty():
			continue
		gs.events_fired[e.id] = now
		_post(gs, e, roles)


static func _condition_ok(gs: Node, e: Dictionary) -> bool:
	var c: Dictionary = e.get("condition", {})
	if c.has("tension_min") and gs.tension < float(c.tension_min):
		return false
	if c.has("tension_max") and gs.tension > float(c.tension_max):
		return false
	if c.has("relation_above") and Diplomacy.relation(gs, c.relation_above[0], c.relation_above[1]) < float(c.relation_above[2]):
		return false
	if c.has("peace") and (gs.at_war(c.peace[0], c.peace[1]) or not _alive(gs, c.peace[0]) or not _alive(gs, c.peace[1])):
		return false
	if c.get("pressure_ai", false) and not gs.pressure_ai:
		return false
	if c.get("player_great_power", false) and gs.player_tag not in GREAT:
		return false
	for tag: String in e.actors.values():
		if tag != "$player" and not gs.nations.has(tag):
			return false
	return true


static func _alive(gs: Node, tag: String) -> bool:
	return gs.nations.has(tag) and not gs.nations[tag].provinces.is_empty()


## The event's actors by role (a, b, c), `$player` filled in; {} if one of them is gone from the map.
static func _roles(gs: Node, e: Dictionary) -> Dictionary:
	var roles := {}
	for role: String in e.actors:
		var tag: String = e.actors[role]
		roles[role] = gs.player_tag if tag == "$player" else tag
		if not gs.nations.has(roles[role]):
			return {}
	return roles


static func _swapped(roles: Dictionary) -> Dictionary:
	var out := roles.duplicate()
	out["a"] = roles.get("b", roles.get("a", ""))
	out["b"] = roles.get("a", "")
	return out


static func _pick(gs: Node, choice: Variant) -> int:
	if choice is Dictionary:
		return int(choice.yes) if gs.tension >= float(choice.tension_min) else int(choice.no)
	return int(choice)


## An event comes up. The player is asked if it concerns them; otherwise the AI's choice is made.
static func _post(gs: Node, e: Dictionary, roles: Dictionary) -> void:
	var me: String = gs.player_tag
	var mirrored: bool = e.get("mirror", false) and roles.get("b", "") == me
	var seen := _swapped(roles) if mirrored else roles
	var player_is_a: bool = seen.get("a", "") == me
	var player_is_b: bool = seen.get("b", "") == me and e.has("b_options")
	if player_is_a or player_is_b:
		var view := seen if player_is_a else _swapped(roles)
		var deferred: Array = []
		if player_is_b:
			# The other side has decided already; a war it chose waits for the player's answer.
			var chosen: Dictionary = e.options[_pick(gs, e.ai_option)]
			for fx: Dictionary in chosen.effects:
				if fx.has("war"):
					deferred.append({"fx": fx, "roles": roles})
				else:
					_apply(gs, fx, roles)
		var options: Array = e.options if player_is_a else e.b_options
		var decision := {"id": gs.next_event_uid, "event": e.id, "title": e.title, "text": _fill(gs, e.text, view),
				"roles": view, "options": options, "deferred": deferred, "date": Clock.date_string(), "as_b": player_is_b}
		gs.next_event_uid += 1
		gs.pending_events.append(decision)
		Clock.paused = true
		gs.event_posted.emit(decision)
		return
	var effects: Array = e.options[_pick(gs, e.ai_option)].effects
	for fx: Dictionary in effects:
		_apply(gs, fx, roles)
	if e.has("b_options") and e.has("b_ai_option"):
		for fx: Dictionary in e.b_options[_pick(gs, e.b_ai_option)].effects:
			_apply(gs, fx, _swapped(roles))
	_record(gs, e.title, _fill(gs, e.text, roles), 1)


static func _record(gs: Node, title: String, text: String, level: int) -> void:
	gs.chronicle.push_front({"date": Clock.date_string(), "title": title, "text": text})
	if gs.chronicle.size() > CHRONICLE_MAX:
		gs.chronicle.pop_back()
	gs.news_posted.emit("%s: %s." % [title, text.split(". ")[0].trim_suffix(".")], level)


static func _fill(gs: Node, text: String, roles: Dictionary) -> String:
	for role: String in roles:
		text = text.replace("{%s}" % role, gs.nations[roles[role]].display_name)
	return text


## The player's answer to a waiting event. Returns false if there is no such decision or option.
static func answer(gs: Node, decision_id: int, option: int) -> bool:
	for i in gs.pending_events.size():
		var d: Dictionary = gs.pending_events[i]
		if d.id != decision_id:
			continue
		if option < 0 or option >= d.options.size():
			return false
		gs.pending_events.remove_at(i)
		var chosen: Dictionary = d.options[option]
		for fx: Dictionary in chosen.effects:
			_apply(gs, fx, d.roles)
		if not chosen.get("defuse", false):
			for item: Dictionary in d.deferred:
				_apply(gs, item.fx, item.roles)
		var e := _event(d.event)
		if e.has("b_options") and e.has("b_ai_option") and not d.as_b:
			for fx: Dictionary in e.b_options[_pick(gs, e.b_ai_option)].effects:
				_apply(gs, fx, _swapped(d.roles))
		_record(gs, d.title, "%s %s." % [gs.nations[gs.player_tag].display_name, chosen.label.to_lower()], 1)
		_update(gs)
		gs.event_resolved.emit(d, option)
		return true
	return false


static func _event(id: String) -> Dictionary:
	for e: Dictionary in events:
		if e.id == id:
			return e
	return {}


## Applies one effect with the roles of its event.
static func _apply(gs: Node, fx: Dictionary, roles: Dictionary) -> void:
	if fx.has("tension"):
		gs.tension_impulse += float(fx.tension)
	elif fx.has("relation"):
		var r: Array = fx.relation
		if _both(gs, roles, r[0], r[1]):
			Diplomacy.change_relation(gs, roles[r[0]], roles[r[1]], float(r[2]))
	elif fx.has("grievance"):
		var g: Array = fx.grievance
		if _both(gs, roles, g[0], g[1]):
			Diplomacy.add_grievance(gs, roles[g[0]], roles[g[1]], float(g[2]))
	elif fx.has("treaty"):
		var t: Array = fx.treaty
		if _both(gs, roles, t[1], t[2]):
			Diplomacy.add_treaty(gs, t[0], roles[t[1]], roles[t[2]], -1, t[3].duplicate(), t[4])
	elif fx.has("end_treaty"):
		var e: Array = fx.end_treaty
		if _both(gs, roles, e[1], e[2]):
			var held := Diplomacy.find_treaty(gs, e[0], roles.get(e[1], e[1]), roles.get(e[2], e[2]))
			if held != null:
				Diplomacy.end_treaty(gs, held)
	elif fx.has("war"):
		var w: Array = fx.war
		var a := _tag(roles, w[0])
		var b := _tag(roles, w[1])
		if _alive(gs, a) and _alive(gs, b) and not gs.at_war(a, b):
			Diplomacy.start_war(gs, a, b, w.size() > 2)
	else:
		for key: String in ["treasury", "prestige", "war_support", "points", "manpower", "mobilize"]:
			if fx.has(key):
				var tag := _tag(roles, fx[key][0])
				if gs.nations.has(tag):
					_apply_to(gs, key, gs.nations[tag], float(fx[key][1]))


static func _tag(roles: Dictionary, role: String) -> String:
	return roles.get(role, role)


static func _both(gs: Node, roles: Dictionary, a: String, b: String) -> bool:
	return gs.nations.has(_tag(roles, a)) and gs.nations.has(_tag(roles, b)) and _tag(roles, a) != _tag(roles, b)


static func _apply_to(gs: Node, key: String, n: Nation, v: float) -> void:
	match key:
		"treasury": n.treasury += v
		"prestige": Diplomacy.gain_prestige(gs, n.tag, v)
		"war_support":
			n.war_support = clampf(n.war_support + v, 0.0, 100.0)
			gs.war_support_changed.emit(n.tag, n.war_support)
		"points": Diplomacy.gain(gs, n.tag, v)
		"manpower": n.manpower = maxi(0, n.manpower + int(n.manpower * v))
		"mobilize": n.mobilization = clampf(n.mobilization + v, 0.0, 1.0)


## What an option would do, in plain words, for the decision window.
static func effect_lines(gs: Node, option: Dictionary, roles: Dictionary) -> PackedStringArray:
	var out: PackedStringArray = []
	for fx: Dictionary in option.effects:
		if fx.has("tension"):
			if absf(float(fx.tension)) >= 0.5:
				out.append("Tension %+d" % roundi(float(fx.tension)))
		elif fx.has("relation"):
			var r: Array = fx.relation
			if _both(gs, roles, r[0], r[1]):
				out.append("Relations with %s %+d" % [_other_name(gs, roles, r[0], r[1]), roundi(float(r[2]))])
		elif fx.has("treaty"):
			var t: Array = fx.treaty
			out.append("%s: %s" % [t[4] if str(t[4]) != "" else "Treaty", _other_name(gs, roles, t[1], t[2])])
		elif fx.has("end_treaty"):
			out.append("The union ends" if fx.end_treaty[0] == "alliance" else "The treaty ends")
		elif fx.has("war"):
			out.append("War with %s" % _other_name(gs, roles, fx.war[0], fx.war[1]))
		elif fx.has("grievance"):
			pass
		else:
			for key: String in ["treasury", "prestige", "war_support", "manpower", "mobilize"]:
				if fx.has(key) and _tag(roles, fx[key][0]) == gs.player_tag:
					out.append(_effect_text(key, float(fx[key][1])))
	return out


## The name of the nation in the pair that is not the player's.
static func _other_name(gs: Node, roles: Dictionary, a: String, b: String) -> String:
	var ta := _tag(roles, a)
	var tb := _tag(roles, b)
	return gs.nations[tb if ta == gs.player_tag else ta].display_name


static func _effect_text(key: String, v: float) -> String:
	match key:
		"treasury": return "Treasury %+.0fM" % v
		"prestige": return "Prestige %+d" % roundi(v)
		"war_support": return "War support %+d" % roundi(v)
		"manpower": return "Reserve %+d%%" % roundi(v * 100.0)
		"mobilize": return "Mobilization %+d%%" % roundi(v * 100.0)
	return key


## What Europe's tension is made of, for a tooltip.
static func tip(gs: Node) -> String:
	var p := parts(gs)
	var lines: PackedStringArray = ["Europe's tension: %d of 100. The nearer it gets to war, the bolder the AI nations grow." % roundi(p.total)]
	var names := {"arms": "The arms race", "mobilization": "Mobilization", "wars": "Wars between the powers", "rivalry": "Rivalries and rival blocs", "events": "Recent crises"}
	for key: String in names:
		if p[key] >= 0.5:
			lines.append("%s  +%d" % [names[key], roundi(p[key])])
	return "\n".join(lines)


# --- Public stands ---------------------------------------------------------------------------

## Why a nation cannot take this stand now, or "".
static func appeal_block(gs: Node, tag: String, kind: String) -> String:
	var def: Dictionary = cfg.appeals.get(kind, {})
	if def.is_empty() or not gs.nations.has(tag):
		return "No such appeal."
	if Clock.days_elapsed < int(gs.appeal_ready.get(tag, 0)):
		return "Not again until %s." % Clock.date_after(int(gs.appeal_ready[tag]) - Clock.days_elapsed)
	if not Diplomacy.can_afford(gs, tag, float(def.cost)):
		return "Needs %d diplomacy points." % int(def.cost)
	return ""


## The nation takes the stand: points spent, tension moved, prestige and war support gained.
static func appeal(gs: Node, tag: String, kind: String) -> bool:
	if appeal_block(gs, tag, kind) != "":
		return false
	var def: Dictionary = cfg.appeals[kind]
	Diplomacy.spend(gs, tag, float(def.cost))
	gs.tension_impulse = clampf(gs.tension_impulse + float(def.tension), 0.0, float(cfg.impulse_max))
	_apply_to(gs, "prestige", gs.nations[tag], float(def.prestige))
	if float(def.war_support) != 0.0:
		_apply_to(gs, "war_support", gs.nations[tag], float(def.war_support))
	gs.appeal_ready[tag] = Clock.days_elapsed + int(cfg.appeals.wait_days)
	_record(gs, def.label, "%s: %s" % [gs.nations[tag].display_name, str(def.tip).to_lower().trim_suffix(".")], 0)
	_update(gs)
	return true

