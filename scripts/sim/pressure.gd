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


## Whether a war between two great powers has been fought and ended: the world after the war.
static func great_war_fought(gs: Node) -> bool:
	for w: War in gs.war_history:
		if w.a in GREAT and w.b in GREAT and w.end_day >= 0:
			return true
	return false


## Whether the AI may start a war of its own choosing: Europe must be tense enough (see war_gate).
static func ai_may_declare(gs: Node) -> bool:
	return not gs.pressure_ai or gs.tension >= war_gate(gs)


## The tension below which the AI starts no war of its own choosing. A scenario may set its own `ai_war_gate`: a
## number, or {start, end, from, to} falling evenly from `start` in year `from` to `end` in year `to` (so the long
## 1900 game does not reach for war in its first years); otherwise data/events.json's tension.ai_war_gate.
static func war_gate(gs: Node) -> float:
	var g: Variant = gs.scenario.get("ai_war_gate", null)
	if g == null:
		return float(cfg.ai_war_gate)
	if g is Dictionary:
		var t := inverse_lerp(float(g.from), float(g.to), Clock.year + (Clock.month - 1) / 12.0)
		return lerpf(float(g.start), float(g.end), clampf(t, 0.0, 1.0))
	return float(g)


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
	# Once the great powers have fought each other, what counts as armed follows the armies slowly, both ways: a lasting
	# army becomes the norm, a new arms race above it shows, and armies sent home ease it. (Before that, the arms race is
	# measured from the scenario's armies, as the road to 1914 was.)
	if great_war_fought(gs):
		gs.tension_arms_base = maxf(1.0, gs.tension_arms_base + (_great_men(gs) - gs.tension_arms_base) * float(cfg.get("arms_drift", 0.0)))
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
	if c.get("player_minor", false) and (gs.player_tag == "" or gs.player_tag in GREAT or not _alive(gs, gs.player_tag)):
		return false
	if c.has("months_from_start") and _month_index() - gs.pressure_start < int(c.months_from_start):
		return false
	if c.get("after_great_war", false) and not great_war_fought(gs):
		return false
	if c.get("no_great_war", false):
		for w: War in gs.wars.values():
			if w.a in GREAT and w.b in GREAT:
				return false
	for tag: String in e.actors.values():
		if not tag.begins_with("$") and not gs.nations.has(tag):
			return false
	return true


static func _alive(gs: Node, tag: String) -> bool:
	return gs.nations.has(tag) and not gs.nations[tag].provinces.is_empty()


## The event's actors by role (a, b, c), `$player` and the other picks filled in (see _pick_role); {} if one of them
## is gone from the map or nobody fits.
static func _roles(gs: Node, e: Dictionary) -> Dictionary:
	var roles := {}
	for role: String in e.actors:
		var tag: String = e.actors[role]
		roles[role] = _pick_role(gs, tag) if tag.begins_with("$") else tag
		if not gs.nations.has(roles[role]):
			return {}
	return roles


## A role named by what a nation is now, not by its tag (events.json picks):
##   $player       the player's nation
##   $lost_ground  the nation that most lately gave up ground at a peace (in the last picks.recent_months, alive and at
##                 peace), and $winner the nation it gave it to
##   $empire       the most troubled of picks.empires at peace: one with war support under picks.empire_support, or
##                 that lost ground lately
##   $most_armed   the great power with the most men under arms, and $second_armed the next
##   $suitor       the great power the player's nation is on best terms with (not allied, not at war)
##   $trade_partner the player's richest land neighbour at peace with it, or else its suitor
##   $great_neighbour the great power on the player's border it is on worst terms with
static func _pick_role(gs: Node, sel: String) -> String:
	var p: Dictionary = cfg.get("picks", {})
	match sel:
		"$player":
			return gs.player_tag
		"$lost_ground", "$winner":
			var loss := _recent_loss(gs, int(p.get("recent_months", 24)) * 30)
			if loss.is_empty():
				return ""
			return loss.holder if sel == "$lost_ground" else loss.against
		"$empire":
			var best := ""
			for tag: String in p.get("empires", []):
				if not _alive(gs, tag) or not gs.wars_of(tag).is_empty():
					continue
				var n: Nation = gs.nations[tag]
				var lost := not _recent_loss(gs, int(p.get("recent_months", 24)) * 30, tag).is_empty()
				if (n.war_support < float(p.get("empire_support", 40.0)) or lost) and (best == "" or n.war_support < gs.nations[best].war_support):
					best = tag
			return best
		"$suitor", "$trade_partner", "$great_neighbour":
			return _player_partner(gs, sel)
		"$most_armed", "$second_armed":
			var powers: Array = GREAT.filter(func(t: String) -> bool: return _alive(gs, t))
			powers.sort_custom(func(x: String, y: String) -> bool:
				return gs.nations[x].men_in_units > gs.nations[y].men_in_units or (gs.nations[x].men_in_units == gs.nations[y].men_in_units and x < y))
			var i := 0 if sel == "$most_armed" else 1
			return powers[i] if powers.size() > i else ""
	return ""


## The nations a small player's events turn to (see _pick_role), "" if none fits.
static func _player_partner(gs: Node, sel: String) -> String:
	var me: String = gs.player_tag
	if not _alive(gs, me):
		return ""
	var best := ""
	var best_v := -INF
	var near: Array[String] = Diplomacy.neighbor_nations(gs, me)
	var pool: Array = near if sel == "$trade_partner" else GREAT
	for tag: String in pool:
		if tag == me or not _alive(gs, tag) or gs.at_war(me, tag):
			continue
		var v: float
		match sel:
			"$suitor":
				if Diplomacy.are_allied(gs, me, tag):
					continue
				v = Diplomacy.relation(gs, tag, me)
			"$trade_partner":
				v = float(gs.nations[tag].budget.get("income", 0.0))
			_:
				if tag not in near:
					continue
				v = -Diplomacy.relation(gs, tag, me)
		if v > best_v or (v == best_v and tag < best):
			best = tag
			best_v = v
	if best == "" and sel == "$trade_partner":
		return _player_partner(gs, "$suitor")
	return best


## The latest claim made in play (ground lost at a peace) within `days`, by `holder` if given, whose holder is alive
## and at peace: {} if none.
static func _recent_loss(gs: Node, days: int, holder := "") -> Dictionary:
	var best := {}
	for c: Dictionary in gs.claims:
		if holder != "" and c.holder != holder:
			continue
		if Clock.days_elapsed - int(c.get("made_day", -999999)) > days or not _alive(gs, c.holder) or not gs.wars_of(c.holder).is_empty():
			continue
		if best.is_empty() or int(c.made_day) > int(best.made_day) or (int(c.made_day) == int(best.made_day) and str(c.holder) < str(best.holder)):
			best = c
	return best


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


static func _record(gs: Node, title: String, text: String, level: int, kind := "event") -> void:
	History.note(gs, kind, "%s: %s" % [title, text])
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
		# A crisis writes its own account of how it ended (see Crisis).
		if not str(d.event).begins_with("crisis:"):
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
	elif fx.has("crisis"):
		# [crisis id, answer, role of the nation answering] (see Crisis)
		Crisis.respond(gs, int(fx.crisis[0]), _tag(roles, fx.crisis[2]), fx.crisis[1])
	elif fx.has("war"):
		var w: Array = fx.war
		var a := _tag(roles, w[0])
		var b := _tag(roles, w[1])
		if _alive(gs, a) and _alive(gs, b) and not gs.at_war(a, b):
			Diplomacy.start_war(gs, a, b, w.size() > 2)
	else:
		for key: String in ["treasury", "revenue", "prestige", "war_support", "points", "manpower", "mobilize"]:
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
		"revenue": n.treasury += v * float(n.budget.get("income", 0.0))
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
	# An option that says in its own words what it does (a crisis answer) needs no reckoning.
	if option.has("tip"):
		return PackedStringArray(str(option.tip).split("\n"))
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
			for key: String in ["treasury", "revenue", "prestige", "war_support", "manpower", "mobilize"]:
				if fx.has(key) and _tag(roles, fx[key][0]) == gs.player_tag:
					out.append(_effect_text(key, float(fx[key][1]), gs.nations[gs.player_tag]))
	return out


## The one effect of an option that matters most to the player, in words ("" for none): a war, a treaty, then the largest of
## the figures weighed by how much each is worth (tension, relations, money, prestige, war support, men). For the decision
## window's advisor line; the tooltip still lists everything.
static func advisor_line(gs: Node, option: Dictionary, roles: Dictionary) -> String:
	if option.has("tip"):
		return str(option.tip).split("\n")[0]
	var best := 0.0
	var text := ""
	for fx: Dictionary in option.effects:
		var weight := 0.0
		var line := ""
		if fx.has("war"):
			weight = 100.0
			line = "War with %s" % _other_name(gs, roles, fx.war[0], fx.war[1])
		elif fx.has("treaty"):
			var t: Array = fx.treaty
			weight = 60.0
			line = "%s with %s" % [t[4] if str(t[4]) != "" else "A treaty", _other_name(gs, roles, t[1], t[2])]
		elif fx.has("end_treaty"):
			weight = 50.0
			line = "A treaty ends"
		elif fx.has("tension"):
			weight = absf(float(fx.tension)) * 4.0
			line = "Tension %+d" % roundi(float(fx.tension))
		elif fx.has("relation"):
			var r: Array = fx.relation
			if _both(gs, roles, r[0], r[1]):
				weight = absf(float(r[2])) * 2.0
				line = "Relations with %s %+d" % [_other_name(gs, roles, r[0], r[1]), roundi(float(r[2]))]
		else:
			var scale := {"treasury": 3.0, "revenue": 15.0, "prestige": 3.0, "war_support": 2.0, "manpower": 50.0, "mobilize": 50.0}
			for key: String in scale:
				if fx.has(key) and _tag(roles, fx[key][0]) == gs.player_tag:
					var w: float = absf(float(fx[key][1])) * float(scale[key])
					if w > weight:
						weight = w
						line = _effect_text(key, float(fx[key][1]), gs.nations[gs.player_tag])
		if weight > best:
			best = weight
			text = line
	return text


## The name of the nation in the pair that is not the player's.
static func _other_name(gs: Node, roles: Dictionary, a: String, b: String) -> String:
	var ta := _tag(roles, a)
	var tb := _tag(roles, b)
	return gs.nations[tb if ta == gs.player_tag else ta].display_name


static func _effect_text(key: String, v: float, n: Nation = null) -> String:
	match key:
		"treasury": return "Treasury %s gold" % Fmt.money(v, true)
		"revenue":
			var m: float = v * float(n.budget.get("income", 0.0)) if n != null else 0.0
			return "Treasury %s gold (%s months of income)" % [Fmt.money(m, true), str(snappedf(v, 0.1))]
		"prestige": return "Prestige %+d" % roundi(v)
		"war_support": return "War support %+d" % roundi(v)
		"manpower": return "Reserve %+d%%" % roundi(v * 100.0)
		"mobilize": return "Mobilization %+d%%" % roundi(v * 100.0)
	return key


## The names of the parts of tension (see parts()).
const PART_NAMES := {"arms": "The arms race", "mobilization": "Mobilization", "wars": "Wars between the powers", "rivalry": "Rivalries and rival blocs", "events": "Recent crises"}


## What Europe's tension is made of, for a tooltip.
static func tip(gs: Node) -> String:
	var p := parts(gs)
	var lines: PackedStringArray = ["Europe's tension: %d of 100. The nearer it gets to war, the bolder the AI nations grow." % roundi(p.total)]
	for key: String in PART_NAMES:
		if p[key] >= 0.5:
			lines.append("%s  +%d" % [PART_NAMES[key], roundi(p[key])])
	return "\n".join(lines)


# --- Public stands ---------------------------------------------------------------------------

## What a stand does to tension now. A call for calm carries as much weight as the nation that makes it: its base, more
## for a great power and for prestige, and more the tenser Europe is, at most calm.tension_max; a rattled sabre is felt
## the same from anyone.
static func appeal_tension(gs: Node, tag: String, kind: String) -> float:
	var def: Dictionary = cfg.appeals[kind]
	if kind != "calm":
		return float(def.tension)
	var n: Nation = gs.nations[tag]
	var weight: float = float(def.tension) + (float(def.great_power) if tag in GREAT else 0.0) + float(def.per_prestige) * maxf(n.prestige, 0.0)
	return -minf(weight * (0.5 + gs.tension / 100.0), float(def.tension_max))


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
	gs.tension_impulse = clampf(gs.tension_impulse + appeal_tension(gs, tag, kind), 0.0, float(cfg.impulse_max))
	_apply_to(gs, "prestige", gs.nations[tag], float(def.prestige))
	if float(def.war_support) != 0.0:
		_apply_to(gs, "war_support", gs.nations[tag], float(def.war_support))
	# The sabre is rattled at someone: every land neighbour thinks less of the nation.
	if float(def.get("neighbour_relation", 0.0)) != 0.0:
		for other: String in Diplomacy.neighbor_nations(gs, tag):
			Diplomacy.change_relation(gs, other, tag, float(def.neighbour_relation))
	gs.appeal_ready[tag] = Clock.days_elapsed + int(cfg.appeals.wait_days)
	_record(gs, def.label, "%s: %s" % [gs.nations[tag].display_name, str(def.tip).to_lower().trim_suffix(".")], 0)
	_update(gs)
	return true

