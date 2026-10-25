class_name AI
extends RefCounted
## The computer players. Every nation but the player's plays through the same commands the
## player uses (GameState.issue_quiet), by utility scoring with the weights in data/ai.json.
## It is deterministic (no random numbers; ties go to the lower province id or tag), it
## sees what the rules show everyone and it obeys the same rules of movement and supply.
##
## This file holds the entry point, the stagger and the shared queries. Behaviour is added
## in steps: defence, offence, force management, diplomacy.

const CONFIG_PATH := "res://data/ai.json"

static var cfg: Dictionary = {}
## Parameter sets of single nations (tag -> a complete copy of the config): used when AIs are trained and tried
## against each other, so that one nation can play by other numbers than the rest. A nation with none uses `cfg`.
static var overrides: Dictionary = {}
static var _base: Dictionary = {}


## Makes `cfg` the nation's own parameters and returns what it was, for `leave`. Everything the AI does for a nation
## (its turn, its answers to peace offers and calls to arms) runs between the two.
static func enter(tag: String) -> Dictionary:
	var previous := cfg
	if overrides.has(tag):
		if _base.is_empty():
			_base = cfg
		cfg = overrides[tag]
	return previous


static func leave(previous: Dictionary) -> void:
	cfg = previous


static func load_config() -> void:
	cfg = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	assert(cfg is Dictionary, "ai.json is invalid")
	for type: String in cfg.forces.mix:
		assert(Military.cfg.unit_types.has(type), "ai.json forces.mix names an unknown unit type: %s" % type)


# --- Setup ---------------------------------------------------------------------------------

## Reads and checks `ai_traits` from the scenario. Called by
## GameState.load_scenario once the nations exist.
##
## ai_traits: {tag: {aggression, caution}}, any key may be left out (the default fills in).
## (The plans in GameState.ai_plans are the AI's own: AIAmbition makes them as it picks its targets.)
static func load_scenario(gs: Node) -> void:
	gs.ai_traits.clear()
	gs.ai_plans.clear()
	gs.ai_ambition.clear()
	gs.ai_ambition_wait.clear()
	gs.ai_reserve.clear()
	gs.ai_campaign.clear()
	gs.ai_campaign_extra.clear()
	gs.ai_diplo_stamp.clear()
	gs.ai_budget_stamp.clear()
	gs.ai_campaign_wait.clear()
	gs.ai_anchor_stamp.clear()
	gs.ai_seed = 0
	gs.ai_navy.clear()
	gs.ai_landing.clear()
	gs.ai_landing_wait.clear()
	gs.ai_navy_need.clear()
	gs.ai_declarations = {"total": 0, "unjustified": 0}
	var s: Dictionary = gs.scenario
	var base: Dictionary = cfg.temperament.default
	for tag: String in s.get("ai_traits", {}):
		assert(gs.nations.has(tag), "ai_traits names an unknown nation: %s" % tag)
		var entry: Dictionary = s.ai_traits[tag]
		var traits := base.duplicate()
		for key: String in entry:
			assert(base.has(key), "ai_traits for %s has an unknown trait: %s" % [tag, key])
			var v := float(entry[key])
			assert(v >= 0.0 and v <= 1.0, "ai_traits %s.%s must be between 0 and 1" % [tag, key])
			traits[key] = v
		gs.ai_traits[tag] = traits


## The id of the province with this name, or 0 if there is none.
static func province_named(province_name: String) -> int:
	for id in range(1, MapData.provinces.size()):
		if MapData.provinces[id].name == province_name:
			return id
	return 0


# --- Who plays, and when -------------------------------------------------------------------

## Whether the AI plays this nation: not the player's, and still on the map.
static func is_ai(gs: Node, tag: String) -> bool:
	var n: Nation = gs.nations.get(tag)
	return n != null and tag != gs.player_tag and not n.provinces.is_empty()


## A repeatable number between -1 and 1 for a key, from the game's seed (0 without one): the same seed and key always
## give the same number, another seed gives another.
static func noise(gs: Node, key: String) -> float:
	if gs.ai_seed == 0:
		return 0.0
	return float(("%d|%s" % [gs.ai_seed, key]).hash() % 20001) / 10000.0 - 1.0


## The nation's own temperament: the default, or the scenario's, bent a little by the game's seed so each game
## gives each nation its own character (`variety.temperament`).
static func base_temperament(gs: Node, tag: String) -> Dictionary:
	var t: Dictionary = gs.ai_traits.get(tag, cfg.temperament.default)
	if gs.ai_seed == 0:
		return t
	var v := float(cfg.variety.temperament)
	return {"aggression": clampf(float(t.aggression) + v * noise(gs, tag + "agg"), 0.0, 1.0),
			"caution": clampf(float(t.caution) + v * noise(gs, tag + "cau"), 0.0, 1.0)}


## The same, with tension's push (a tense Europe makes every nation bolder and less careful; see Pressure).
static func temperament(gs: Node, tag: String) -> Dictionary:
	var t: Dictionary = base_temperament(gs, tag)
	if gs.tension_bonus <= 0.0:
		return t
	return {"aggression": clampf(float(t.aggression) + gs.tension_bonus, 0.0, 1.0), "caution": clampf(float(t.caution) - gs.tension_bonus * 0.5, 0.0, 1.0)}


## The day (0 to think_days - 1) on which a nation thinks: its place in tag order, so the
## nations are spread evenly over the interval.
static func think_offset(gs: Node, tag: String) -> int:
	var tags: Array = gs.nations.keys()
	tags.sort()
	return tags.find(tag) % int(cfg.think_days)


## The AI nations whose turn it is to think today, in tag order.
static func due_nations(gs: Node) -> Array[String]:
	var out: Array[String] = []
	var tags: Array = gs.nations.keys()
	tags.sort()
	var interval := int(cfg.think_days)
	for i in tags.size():
		if (Clock.days_elapsed + i) % interval == 0 and is_ai(gs, tags[i]):
			out.append(tags[i])
	return out


## Daily entry point, called by GameState after Diplomacy.step_day. Each AI nation thinks
## once every `think_days` days.
static func step_day(gs: Node) -> void:
	if not gs.ai_enabled:
		return
	for tag in due_nations(gs):
		think(gs, tag)


## One nation's turn: the war (defence, offence, recruiting) when it is at war, and always
## diplomacy and the budget.
static func think(gs: Node, tag: String) -> void:
	var previous := enter(tag)
	_think(gs, tag)
	leave(previous)


static func _think(gs: Node, tag: String) -> void:
	if not gs.wars_of(tag).is_empty():
		_timed("defence", func() -> void: AIDefense.step(gs, tag))
		_timed("offence", func() -> void: AIOffense.step(gs, tag))
		_timed("forces", func() -> void: AIForces.step(gs, tag))
		_timed("navy", func() -> void: AINavy.step(gs, tag))
		_timed("landing", func() -> void: AILanding.step(gs, tag))
	else:
		_timed("rebuild", func() -> void: AIForces.rebuild(gs, tag))
	_timed("diplomacy", func() -> void: AIDiplomacy.step(gs, tag))
	_timed("budget", func() -> void: AIBudget.step(gs, tag))
	_timed("focus", func() -> void: AIFocus.step(gs, tag))
	_timed("ambition", func() -> void: AIAmbition.step(gs, tag))


## Microseconds spent in each part of the AI, by name, while `profile` is true (tools/ai_report.gd).
static var profile := false
static var timings: Dictionary = {}


static func _timed(part: String, work: Callable) -> void:
	if not profile:
		work.call()
		return
	var t := Time.get_ticks_usec()
	work.call()
	timings[part] = timings.get(part, 0) + Time.get_ticks_usec() - t


# --- Shared queries ------------------------------------------------------------------------

static var _hops_cache: Dictionary = {}
static var _index: Dictionary = {}
static var _index_key := -1
static var _index_gs := 0
static var _threat_cache: Dictionary = {}
static var _worth_cache: Dictionary = {}


## Forgets what was kept for the day (another game was loaded, or a scenario began).
static func invalidate_caches() -> void:
	_index.clear()
	_index_key = -1
	_threat_cache.clear()
	_worth_cache.clear()


## Provinces within `hops` steps of `id` (itself included), as province id -> hops. The map
## never changes, so each answer is worked out once; callers must not modify it.
static func hops_from(id: int, hops: int) -> Dictionary:
	var key := id * 16 + hops
	var cached: Variant = _hops_cache.get(key)
	if cached != null:
		return cached
	var seen := {id: 0}
	var frontier := [id]
	for step in range(1, hops + 1):
		var next := []
		for cur: int in frontier:
			for n: int in Military.neighbors(cur):
				if not seen.has(n):
					seen[n] = step
					next.append(n)
		frontier = next
	_hops_cache[key] = seen
	return seen


## The armies standing in each province, as province id -> Array[Army], rebuilt when the day or
## the number of armies changes (armies only change province in the day's military step).
static func armies_by_province(gs: Node) -> Dictionary:
	var key: int = Clock.days_elapsed * 1000003 + gs.armies.size() * 1009 + gs.next_army_id * 7 + gs.wars.size()
	if key != _index_key or gs.get_instance_id() != _index_gs:
		_index.clear()
		_threat_cache.clear()
		for a: Army in gs.armies.values():
			if not _index.has(a.province):
				_index[a.province] = [] as Array[Army]
			_index[a.province].append(a)
		_index_key = key
		_index_gs = gs.get_instance_id()
	return _index


## The fighting power of a nation's armies in a province and within `hops` of it.
static func local_power(gs: Node, tag: String, province: int, hops: int) -> float:
	var at := armies_by_province(gs)
	var total := 0.0
	var near := hops_from(province, hops)
	for id: int in near:
		for a: Army in at.get(id, []):
			if a.tag == tag:
				total += a.power()
	return total


## The nations `tag` is at war with, in tag order.
static func enemies(gs: Node, tag: String) -> Array[String]:
	var out: Array[String] = []
	for war: War in gs.wars_of(tag):
		out.append(war.other(tag))
	out.sort()
	return out


## The power of the armies of every nation `tag` is at war with, in full inside the province
## and cut by hop_decay per hop around it (as far as threat.hops).
static func enemy_power(gs: Node, tag: String, province: int) -> float:
	var t: Dictionary = cfg.threat
	var near := hops_from(province, int(t.hops))
	var at := armies_by_province(gs)
	var power := 0.0
	for id: int in near:
		for a: Army in at.get(id, []):
			if a.tag != tag and gs.at_war(tag, a.tag):
				power += a.power() * pow(float(t.hop_decay), near[id])
	return power


## The enemy power bearing on a province held by `tag`, times 1 + stakes * value(province),
## so a rich province or a capital is the more threatened.
static func threat(gs: Node, tag: String, province: int) -> float:
	armies_by_province(gs)
	var key := "%s%d" % [tag, province]
	var cached: Variant = _threat_cache.get(key)
	if cached != null:
		return cached
	var t := enemy_power(gs, tag, province) * (1.0 + float(cfg.threat.stakes) * value(gs, province))
	_threat_cache[key] = t
	return t


## The odds (own power over the defenders') a nation wants before it attacks: `bold` for the
## bold (high aggression, low caution), `cautious` for the cautious.
static func required_odds(gs: Node, tag: String) -> float:
	var t: Dictionary = temperament(gs, tag)
	var boldness := clampf((float(t.aggression) + 1.0 - float(t.caution)) / 2.0, 0.0, 1.0)
	return lerpf(float(cfg.odds.cautious), float(cfg.odds.bold), boldness)


## The odds a nation wants before it fights a battle it chooses (an advance, a retaking, a landing, a sortie): like
## required_odds but with its own numbers, so that how it fights can be tuned apart from how readily it goes to war.
static func battle_odds(gs: Node, tag: String) -> float:
	var t: Dictionary = temperament(gs, tag)
	var boldness := clampf((float(t.aggression) + 1.0 - float(t.caution)) / 2.0, 0.0, 1.0)
	return lerpf(float(cfg.offense.odds_cautious), float(cfg.offense.odds_bold), boldness)


## Whether an army of `tag` standing in the province could draw supply there.
static func supplied(gs: Node, tag: String, province: int) -> bool:
	return Military.supply_cost(gs, tag, province) < INF


## A nation's output (GDP plus industry), kept for the day and while its land is unchanged.
static func _output_total(gs: Node, tag: String) -> float:
	var key: int = Clock.days_elapsed * 1000003 + gs.owner_version
	var entry: Variant = _worth_cache.get(tag)
	if entry != null and entry.key == key and entry.gs == gs.get_instance_id():
		return entry.total
	var total := 0.0
	for id: int in gs.nations[tag].provinces:
		total += gs.province_gdp[id] + gs.province_industry[id]
	_worth_cache[tag] = {"key": key, "gs": gs.get_instance_id(), "total": total}
	return total


## What a province is worth to its owner, 0 to about 1.5: its share of the owner's people and
## of its output, with a bonus for the capital.
static func value(gs: Node, province: int) -> float:
	var v: Dictionary = cfg.value
	var owner: String = gs.province_owner[province]
	var n: Nation = gs.nations[owner]
	var people := 0.0
	var output := 0.0
	if n.population > 0:
		people = float(gs.province_population[province]) / n.population
	var total := _output_total(gs, owner)
	if total > 0.0:
		output = (gs.province_gdp[province] + gs.province_industry[province]) / total
	var score: float = float(v.people) * people + float(v.output) * output
	if province == n.capital:
		score += float(v.capital_bonus)
	return score
