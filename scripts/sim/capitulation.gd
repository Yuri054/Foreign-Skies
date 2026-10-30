class_name Capitulation
extends RefCounted
## Capitulation, the moving of a capital, and the peace that follows (docs/REWORK.md, R1). Static, like Peace; the state
## is on Nation (capitulated, home_capital), on War (capitulated) and GameState.capital_choice. Constants are in
## data/diplomacy.json under "capitulation".
##
## Every province has a value (Peace.province_value: its people, its city, its buildings); the capital carries a bonus on
## top, sized so that it is capital_share of the nation's whole value. A nation's capitulation progress is the share of
## that whole its enemies hold. Each day, for every nation at war:
##   - at capitulate_share it capitulates;
##   - when it loses its capital, a nation still holding relocation_share of its value moves its capital (the AI to its
##     most valuable city, or town if it has no city left; the player picks from a list, the game waiting) and fights on; the new capital
##     carries relocated_bonus of the capital bonus. One that cannot, capitulates.
##   - retaking the home capital moves the capital back.
## A capitulated nation's armies lay down their arms (their men go back to the reserve), it raises no more, its enemies
## gain capitulation_score in war score against it, and each AI enemy dictates its peace at once (the player gets the
## peace screen). Its allies fight on.


static func cfg() -> Dictionary:
	return Diplomacy.cfg.capitulation


## The capital bonus of a nation: what the home capital adds to its province value so that it is capital_share of the
## nation's whole.
static func capital_bonus(gs: Node, tag: String) -> float:
	var n: Nation = gs.nations[tag]
	var home := home_capital(gs, tag)
	var total := _provinces_value(gs, tag)
	var own: float = Peace.province_value(gs, home) if home > 0 else 0.0
	var share := float(cfg().capital_share)
	return maxf(0.0, (share * total - own) / (1.0 - share))


## The sum of a nation's province values, kept for the day (the AI asks for it for every province it weighs).
static func _provinces_value(gs: Node, tag: String) -> float:
	var n: Nation = gs.nations[tag]
	var stamp := [Clock.days_elapsed, gs.get_instance_id()]
	if stamp != _stamp:
		_totals.clear()
		_stamp = stamp
	var key := [tag, n.provinces.size()]
	if not _totals.has(key):
		var total := 0.0
		for id: int in n.provinces:
			total += Peace.province_value(gs, id)
		_totals[key] = total
	return _totals[key]


static var _totals := {}
static var _stamp: Array = []


## The capital the nation started the war with (its capital when it is not relocated).
static func home_capital(gs: Node, tag: String) -> int:
	var n: Nation = gs.nations[tag]
	return n.home_capital if n.home_capital > 0 else n.capital


static func relocated(gs: Node, tag: String) -> bool:
	var n: Nation = gs.nations[tag]
	return n.capital > 0 and n.capital != home_capital(gs, tag)


## The nation's whole value: its provinces and the capital bonus.
static func whole_value(gs: Node, tag: String) -> float:
	return capital_bonus(gs, tag) + _provinces_value(gs, tag)


## The value one province carries for its owner, capital bonuses included.
static func value_of(gs: Node, id: int, tag: String) -> float:
	var v := Peace.province_value(gs, id)
	if id == home_capital(gs, tag):
		v += capital_bonus(gs, tag)
	elif relocated(gs, tag) and id == gs.nations[tag].capital:
		v += capital_bonus(gs, tag) * float(cfg().relocated_bonus)
	return v


## The share of the nation's whole value its enemies (every nation at war with it), or one of them, hold: 0..1.
static func progress(gs: Node, tag: String, holder := "") -> float:
	var whole := whole_value(gs, tag)
	if whole <= 0.0:
		return 0.0
	var lost := 0.0
	for id: int in gs.nations[tag].provinces:
		var c: String = gs.province_controller[id]
		if c == tag or (holder != "" and c != holder) or not gs.at_war(tag, c):
			continue
		lost += value_of(gs, id, tag)
	return minf(1.0, lost / whole)


static func capitulated(gs: Node, tag: String) -> bool:
	var n: Nation = gs.nations.get(tag)
	return n != null and n.capitulated


## Where a nation could move its capital: the provinces it owns and holds, those with a city first, each kind most
## valuable first (a country with no other city moves to its best town).
static func capital_candidates(gs: Node, tag: String) -> Array[int]:
	var out: Array[int] = []
	var cities := {}
	for c in gs.cities:
		cities[int(c.province)] = true
	for id: int in gs.nations[tag].provinces:
		if gs.province_controller[id] == tag and id != gs.nations[tag].capital:
			out.append(id)
	out.sort_custom(func(a: int, b: int) -> bool:
		if cities.has(a) != cities.has(b):
			return cities.has(a)
		return Peace.province_value(gs, a) > Peace.province_value(gs, b))
	return out


## Whether the nation still holds enough to move its capital: relocation_share of its whole value, and somewhere to go.
static func can_relocate(gs: Node, tag: String) -> bool:
	return 1.0 - progress(gs, tag) >= float(cfg().relocation_share) and not capital_candidates(gs, tag).is_empty()


## The parts of a war score (Peace.score_parts) in words.
static func parts_text(parts: Dictionary) -> String:
	var text := "ground %+.1f, capital %+.1f, battles %+.1f" % [parts.occupation, parts.capital, parts.battles]
	if parts.get("capitulation", 0.0) != 0.0:
		text += ", capitulation %+.1f" % parts.capitulation
	return text


## How near each side of a war is to capitulating, in words: "Capitulation: France 34%, Germany 2% (80% capitulates)".
static func progress_text(gs: Node, war: War) -> String:
	var bits: PackedStringArray = []
	for tag: String in [war.a, war.b]:
		var n: Nation = gs.nations[tag]
		if n.capitulated:
			bits.append("%s has capitulated" % n.display_name)
		else:
			bits.append("%s %d%%%s" % [n.display_name, roundi(progress(gs, tag) * 100.0), " (capital moved)" if relocated(gs, tag) else ""])
	return "Capitulation: %s (at %d%% a nation capitulates)." % [", ".join(bits), roundi(float(cfg().capitulate_share) * 100.0)]


# --- The day ------------------------------------------------------------------------------

static func step_day(gs: Node) -> void:
	for tag: String in gs.nations:
		var n: Nation = gs.nations[tag]
		if n.provinces.is_empty():
			continue
		if gs.wars_of(tag).is_empty():
			# At peace: no longer capitulated; a capital moved in the war goes home if the home is still the nation's.
			n.capitulated = false
			var home := home_capital(gs, tag)
			if relocated(gs, tag) and home in n.provinces and gs.province_controller[home] == tag:
				move_capital(gs, tag, home)
			elif home not in n.provinces:
				n.home_capital = n.capital
			continue
		if n.capitulated:
			continue
		# The home capital retaken: the capital goes back.
		var home := home_capital(gs, tag)
		if relocated(gs, tag) and gs.province_controller[home] == tag:
			move_capital(gs, tag, home)
		if progress(gs, tag) >= float(cfg().capitulate_share):
			capitulate(gs, tag)
			continue
		if n.capital > 0 and gs.province_controller[n.capital] != tag and gs.at_war(tag, gs.province_controller[n.capital]):
			_capital_lost(gs, tag)


## The capital has fallen: move it if the nation can, else capitulate.
static func _capital_lost(gs: Node, tag: String) -> void:
	if gs.capital_choice.get("tag", "") == tag:
		return  # the player is choosing
	if not can_relocate(gs, tag):
		capitulate(gs, tag)
		return
	var candidates := capital_candidates(gs, tag)
	if tag == gs.player_tag:
		gs.capital_choice = {"tag": tag, "candidates": candidates, "lost": gs.nations[tag].capital}
		Clock.paused = true
		gs.capital_choice_posted.emit(gs.capital_choice)
		return
	move_capital(gs, tag, candidates[0])


## Moves a nation's capital (keeping the home capital it started the war with).
static func move_capital(gs: Node, tag: String, id: int) -> void:
	var n: Nation = gs.nations[tag]
	if n.home_capital <= 0:
		n.home_capital = n.capital
	var from := n.capital
	n.capital = id
	if gs.capital_choice.get("tag", "") == tag:
		gs.capital_choice = {}
	var going_home := id == n.home_capital
	var text := ("%s's government returns to %s." if going_home else "%s's government leaves %s for %s.") % (
			[n.display_name, MapData.provinces[id].name] if going_home else [n.display_name, MapData.provinces[from].name, MapData.provinces[id].name])
	for war in gs.wars_of(tag):
		war.add_log(Clock.date_string(), "capital", text, id)
	History.note(gs, "capital", text)
	gs.news_posted.emit(text, 1)
	gs.capital_moved.emit(tag, from, id)


## The nation capitulates: its armies lay down their arms, it raises no more, its enemies gain war score, and each AI
## enemy dictates its peace at once (the player gets the peace screen).
static func capitulate(gs: Node, tag: String) -> void:
	var n: Nation = gs.nations[tag]
	if n.capitulated:
		return
	n.capitulated = true
	if gs.capital_choice.get("tag", "") == tag:
		gs.capital_choice = {}
	var men := 0.0
	for a in Military.armies_of(gs, tag):
		men += a.men()
		gs.armies.erase(a.id)
	for job in n.recruiting:
		men += float(Military.cfg.unit_types[job.type].size)
	n.recruiting.clear()
	n.manpower += roundi(men)
	Military.refresh_men(gs)
	var text := "%s capitulates: its armies (%dk men) lay down their arms." % [n.display_name, roundi(men / 1000.0)]
	for war in gs.wars_of(tag):
		war.capitulated[tag] = Clock.date_string()
		war.add_log(Clock.date_string(), "capitulation", text)
	History.note(gs, "capitulation", text)
	gs.news_posted.emit(text, 2)
	gs.armies_changed.emit()
	gs.nation_capitulated.emit(tag)
	dictate(gs, tag)


## The peace after a capitulation: every AI enemy takes what its war score (and the capitulation) pays for; the
## player, if an enemy, gets the peace screen to dictate its own.
static func dictate(gs: Node, tag: String) -> void:
	for war: War in gs.wars_of(tag).duplicate():
		var enemy: String = war.other(tag)
		if enemy == gs.player_tag:
			gs.dictate_peace.emit(war.id)
			continue
		var terms := AIPeace.price_terms(gs, enemy, tag, war)
		if not Peace.check(gs, enemy, tag, "demand", terms).ok:
			terms = []
		Peace.propose(gs, enemy, tag, "demand", terms)
