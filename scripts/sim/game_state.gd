extends Node
## All mutable simulation state. Presentation (map, UI) reads from here and listens to
## its signals; it never owns game data. Static map data stays in MapData.

signal scenario_loaded
signal player_changed(tag: String)
signal province_owner_changed(id: int, old_owner: String, new_owner: String)
## Budgets or province output were recalculated.
signal economy_updated
signal building_completed(tag: String, province: int, type: String)
## An army moved, fought, was raised or was lost.
signal armies_changed
signal battle_fought(province: int, tags: Array)
signal unit_trained(tag: String, province: int, type: String)
## A province changed hands in war (occupation); the owner is unchanged.
signal province_controller_changed(id: int, old_controller: String, new_controller: String)
signal fronts_changed
signal fleets_changed
## A day of fighting at sea in a zone, with the nations that fought.
signal sea_battle_fought(zone: int, tags: Array)
signal ship_sunk(tag: String, zone: int, type: String)
signal blockade_changed(tag: String, value: float)
signal focus_changed(tag: String)
signal focus_completed(tag: String, id: String)
signal casus_belli_ready(holder: String, target: String)
signal ship_built(tag: String, province: int, type: String)
signal war_changed(a: String, b: String, at_war: bool)
## A nation lost its last province and its armies broke up.
signal nation_collapsed(tag: String, men: int)
## A treaty was signed (added is true) or ended.
signal treaty_changed(treaty: Treaty, added: bool)
signal relations_changed(a: String, b: String)
## The player must answer a join decision (see Diplomacy.offer_joins); time is held until then.
signal event_posted(decision: Dictionary)
signal event_resolved(decision: Dictionary, option: int)
## A line for the news feed from the historical pressure (level 0 plain, 1 a warning).
signal news_posted(text: String, level: int)
signal join_requested(decision: Dictionary)
## A join decision was settled, by the player or the AI.
signal join_resolved(decision: Dictionary, joined: bool)
## A nation's diplomacy points changed (spent or earned).
signal diplomacy_points_changed(tag: String, value: float)
## A nation's war support moved.
signal war_support_changed(tag: String, value: float)
## A peace offer is waiting for the player (see Peace.propose); time is held until it is answered.
signal peace_offered(offer: Dictionary)
## A peace offer was accepted or refused.
signal peace_resolved(offer: Dictionary, accepted: bool)
## An AI nation was called to join a war and is mobilizing for it.
signal join_called(decision: Dictionary)
## `nation` mobilized far enough to alarm `neighbor`.
signal mobilization_alarm(nation: String, neighbor: String)
## A command the player gave (through `issue`, not the AI's `issue_quiet`) was carried out; `type`
## is the command's class name. The tutorial listens for these.
signal command_issued(type: String)
signal game_saved(path: String)

const DEFAULT_SCENARIO := "res://data/scenarios/july_1914/"

var scenario: Dictionary = {}
## The folder the scenario was read from (a save names it, so a load starts from the same one).
var scenario_dir := ""
var player_tag := ""
## tag -> Nation
var nations: Dictionary = {}
## Indexed by province id (element 0 unused).
var province_owner: PackedStringArray = []
## Counts changes of ownership, so things worked out from the borders can be cached.
var owner_version := 0
var province_controller: PackedStringArray = []
var province_population := PackedInt32Array()
## What each province's people numbered when the scenario began (read again on every load; never saved):
## the cities grow and shrink with the ratio (see Cities).
var province_pop_base := PackedInt32Array()
## The part of a person each province's growth has not yet added (see Population).
var province_pop_frac := PackedFloat32Array()
## Province output before nation-wide modifiers; filled by Economy.recompute.
## The summed province output of each nation from the last Economy.recompute (kept so the daily
## refresh need not go through the provinces again).
var economy_sums: Dictionary = {}
var province_gdp := PackedFloat32Array()       # GBP millions per year
var province_industry := PackedFloat32Array()  # GBP millions per year
## Kt of raw materials a year one GBP million of industrial output needs (see Economy.calibrate_materials);
## worked out from the scenario at its start, not saved.
var materials_k := 0.0
var province_food := PackedFloat32Array()      # people the land can feed
var province_pool := PackedFloat32Array()      # recruitable men
## Indexed by province id: resource id -> potential output in thousand tonnes per year.
var province_deposit: Array[Dictionary] = []
## The major cities (data/scenarios/<scenario>/cities.tsv), biggest first: {id, name, province, pos
## (a point on the map), pop, rank (1 a capital, 2 a great city, 3 a large one), est}.
var cities: Array[Dictionary] = []
## Province id to the cities in it.
var cities_by_province: Dictionary = {}
## Indexed by province id: building type -> level.
var province_buildings: Array[Dictionary] = []
## army id -> Army.
var armies: Dictionary = {}
var next_army_id := 1
## The commanders each nation holds, by id (see General), and the next id.
var generals: Dictionary = {}
var next_general_id := 1
## Army groups by id (see ArmyGroup) and the next id.
var army_groups: Dictionary = {}
var next_group_id := 1
## Attack lines by id (see AttackLine) and the next id.
var attack_lines: Dictionary = {}
var next_attack_line_id := 1
## id -> Fleet.
var fleets: Dictionary = {}
var next_fleet_id := 1
## Naval bases (dockyards) from the scenario: province id -> level. They count as a port for
## the navy, but not for the economy, so the 1914 trade figures stay as calibrated.
var naval_bases: Dictionary = {}
## Fights at sea now, by zone, and the accounts of those that have ended, by id.
var sea_battles: Dictionary = {}
var sea_battle_archive: Dictionary = {}
## Who holds each sea zone today, by zone (see Blockade.update_control).
var sea_control: Dictionary = {}
## front id -> Front.
var fronts: Dictionary = {}
var next_front_id := 1
## Province id -> {tag, days}: an army is taking the province and has held it for this long.
var occupation: Dictionary = {}
## Wars being fought, keyed "A|B" with the tags in sorted order (id -> War for the record,
## see war_between). Diplomacy (phase 5) will own declarations and peace; until then the
## Military panel can switch wars on for testing.
var wars: Dictionary = {}
## Finished wars, oldest first.
var war_history: Array[War] = []
var next_war_id := 1
## Province id -> the battle being fought there (Military keeps it to write the war record).
var engagements: Dictionary = {}
## Finished battles in full (id -> battle dictionary, see Military._engagement); the oldest
## are dropped past MAX_ARCHIVED_BATTLES.
var battle_archive: Dictionary = {}
var next_battle_id := 1
const MAX_ARCHIVED_BATTLES := 300
## Opinion of each pair of nations, -100..100, keyed "A|B" with the tags sorted; what it drifts
## back to is relation_base. Rules in Diplomacy.
var relations: Dictionary = {}
var relation_base: Dictionary = {}
## Every treaty ever signed, ended ones included (see Treaty.active_on).
var treaties: Array[Treaty] = []
var next_treaty_id := 1
## Casus belli earned in play, not read from claims: {holder, target, kind, expires_day}.
var casus_belli: Array[Dictionary] = []
## "A>B" -> how much A resents B (0..100); see Diplomacy.add_grievance.
var grievance: Dictionary = {}
var next_war_group := 1
## war group id -> {id, attacker, defender, members: {tag: "attack"|"defend"}, declined: {tag: true}}.
## A group is one conflict: the pairwise wars opened together (see Diplomacy).
var war_groups: Dictionary = {}
## Join decisions waiting for the player, oldest first.
var pending_joins: Array[Dictionary] = []
var next_decision_id := 1
## Historical pressure (see Pressure): Europe's tension 0 to 100, the part of it that comes from events,
## the great powers' men under arms when the scenario began, the aggression it adds to the AI, the events
## that have come up (id -> month index), those waiting for the player, and what has happened lately.
var tension := 0.0
var tension_impulse := 0.0
var tension_arms_base := 1.0
var tension_bonus := 0.0
## Whether tension steers the AI (the scenario says so; 1914 begins with its crisis already under way).
var pressure_ai := false
## The month the scenario began (year * 12 + month): events dated before it are already history.
var pressure_start := 0
var events_fired: Dictionary = {}
## Nation tag -> day before which it may not take another public stand (Pressure.appeal).
var appeal_ready: Dictionary = {}
var pending_events: Array[Dictionary] = []
var next_event_uid := 1
var chronicle: Array[Dictionary] = []
var tension_history: Array[float] = []
## Peace offers waiting for the player's answer, oldest first.
var pending_offers: Array[Dictionary] = []
var next_offer_id := 1
## Pair key -> day until which a refused proposer may not ask again.
var peace_cooldown: Dictionary = {}
## Indemnities being paid: {payer, receiver, monthly, months_left}.
var indemnities: Array[Dictionary] = []
## Peace clauses keeping a nation's armies out of its border provinces:
## {nation, holder, provinces, until_day}.
var restrictions: Array[Dictionary] = []
## Allies called up because a neighbour of theirs was alarmed: "ALLY|AGAINST" ->
## {tag, for, against, day}. Cleared when the alarm is.
var mobilization_calls: Dictionary = {}
## "A>B" -> day A's mobilization alarmed B.
var alarms: Dictionary = {}
## AI nations called to join a war that are still mobilizing: "TAG|GROUP" -> join decision.
var join_calls: Dictionary = {}
## Each nation's figures month by month, for the rankings' charts: {day, date, values:
## {tag: {metric: value}}}, oldest first (see Standings).
var standings_history: Array[Dictionary] = []
## Efforts to improve relations under way: {from, to, months_left}.
var relation_projects: Array[Dictionary] = []
## Money each nation has recently gifted another, "from>to": {amount}; fades monthly (see Diplomacy.gift_effect).
var gift_memory: Dictionary = {}
## War justifications under way: {holder, target, done_day}.
var justifications: Array[Dictionary] = []
## Every command issued so far, in order.
var command_log: Array[Dictionary] = []
## AI temperament overrides by nation (aggression, caution), and the plans read from the
## scenario: [{nation, enemy, posture, objectives: [{province, weight}]}]. See AI.
var ai_traits: Dictionary = {}
var ai_plans: Array[Dictionary] = []
## What each AI nation is working toward after the opening: tag -> {target, since}; and the day each may
## next take up a new ambition. See AIAmbition.
var ai_ambition: Dictionary = {}
var ai_ambition_wait: Dictionary = {}
## Wars the AI has declared so far, and how many of them had no casus belli. Declarations by
## the player do not count.
var ai_declarations := {"total": 0, "unjustified": 0}
## The AI's reserve army by nation: tag -> army id (see AIDefense).
var ai_reserve: Dictionary = {}
## The AI's campaign by nation (see AIOffense), and the day before which it will not look
## for a new one.
var ai_campaign: Dictionary = {}
var ai_campaign_wait: Dictionary = {}
## The naval AI: tag -> {assign: {fleet id: zone}}, the landings it is preparing (tag -> {enemy,
## target, port, fleet, armies, phase, started}), when it may look for another, and what it lacks.
var ai_navy: Dictionary = {}
var ai_landing: Dictionary = {}
var ai_landing_wait: Dictionary = {}
var ai_navy_need: Dictionary = {}
## The month (year * 12 + month) in which each AI nation last weighed treaties.
var ai_diplo_stamp: Dictionary = {}
## The month (year * 12 + month) in which each AI nation last did its budget.
var ai_budget_stamp: Dictionary = {}
## False turns the computer players off (tests of the other systems, or watching a war
## with nobody at the controls).
var ai_enabled := true
## Set by issue_quiet; the day's step recomputes the economy once if it is true.
var economy_dirty := false
## True while the daily step runs: what changes the economy during it (a province taken, a nation mobilized, a
## ship launched) only marks it dirty, and the step recomputes once at its end instead of once for each.
var in_day_step := false
## A change that moves the budgets but no province (a blockade): the budgets and flows are worked
## out again, the provinces are not.
var budget_dirty := false
## Counts every change of who holds a province, so what depends on it is read again only then.
var control_version := 0
## True in the running game (not in tests): the first of each month is saved into one of
## AUTOSAVE_SLOTS rotating files.
var autosave_enabled := false
const AUTOSAVE_SLOTS := 3


func _ready() -> void:
	load_scenario(DEFAULT_SCENARIO)
	Clock.day_ticked.connect(_on_day_ticked)
	Clock.month_ticked.connect(_on_month_ticked)


## What a day is made of, in order: each is one stage, and the running game does one a frame (a day is some
## forty milliseconds of work, and all of it in one frame is a visible stutter), while tests and the
## tools run them all at once.
func _day_stage_list() -> Array:
	return [
		func() -> void:
			Economy.step_day(self)
			Focus.step_day(self)
			Navy.step_day(self),
		func() -> void: Military.step_day(self),
		func() -> void: Diplomacy.step_day(self),
		func() -> void: AI.step_day(self),
		func() -> void:
			in_day_step = false
			if economy_dirty:
				economy_dirty = false
				budget_dirty = false
				Economy.recompute(self)
				economy_updated.emit()
			elif budget_dirty:
				budget_dirty = false
				Economy.refresh_now(self)
				economy_updated.emit(),
	]


var _day_stages: Array = []


func _on_day_ticked() -> void:
	finish_day()
	in_day_step = true
	_day_stages = _day_stage_list()
	if autosave_enabled:
		_run_day_stage()        # the rest follow, a stage a frame (see _process)
	else:
		finish_day()


func _run_day_stage() -> void:
	var stage: Callable = _day_stages.pop_front()
	stage.call()


## Runs what is left of the day's step now (before the next day, a save, a month's end).
func finish_day() -> void:
	while not _day_stages.is_empty():
		_run_day_stage()


func _process(_delta: float) -> void:
	if not _day_stages.is_empty():
		_run_day_stage()


## Reads the scenario's list of major cities (none if it has no cities.tsv).
func _load_cities(dir: String) -> void:
	cities.clear()
	cities_by_province.clear()
	if not FileAccess.file_exists(dir + "cities.tsv"):
		return
	for row in MapData.read_table(dir + "cities.tsv"):
		var city := {"id": int(row.id), "name": row.name, "province": int(row.province),
				"pos": Vector2(float(row.x), float(row.y)), "pop": int(row.pop), "rank": int(row.rank), "est": int(row.est) == 1}
		cities.append(city)
		if not cities_by_province.has(city.province):
			cities_by_province[city.province] = []
		cities_by_province[city.province].append(city)


func load_scenario(dir: String) -> void:
	_day_stages.clear()
	in_day_step = false
	Military.invalidate_aura()
	Economy.load_config()
	Military.load_config()
	Navy.load_config()
	Diplomacy.load_config()
	Focus.load_config()
	AI.load_config()
	Pressure.load_config()
	command_log.clear()
	wars.clear()
	war_history.clear()
	next_war_id = 1
	next_war_group = 1
	engagements.clear()
	battle_archive.clear()
	sea_battles.clear()
	sea_battle_archive.clear()
	sea_control.clear()
	next_battle_id = 1
	occupation.clear()
	fronts.clear()
	next_front_id = 1
	scenario_dir = dir
	scenario = JSON.parse_string(FileAccess.get_file_as_string(dir + "scenario.json"))
	assert(scenario is Dictionary, "scenario.json is invalid")

	var count := MapData.provinces.size()
	province_owner.resize(count)
	province_controller.resize(count)
	province_population.resize(count)
	province_pop_frac.resize(count)
	province_pop_frac.fill(0.0)
	province_buildings.clear()
	province_deposit.clear()
	for i in count:
		province_buildings.append({})
		province_deposit.append({})
	for row in MapData.read_table(dir + "resources.tsv"):
		for r in Economy.deposit_ids():
			province_deposit[int(row.id)][r] = float(row[r])
	_load_cities(dir)
	for id in range(1, count):
		province_owner[id] = MapData.provinces[id].owner
		owner_version += 1
		province_controller[id] = MapData.provinces[id].owner
	var by_name := {}
	for id in range(1, count):
		by_name[MapData.provinces[id].name] = id
	# The works a scenario's big cities already have (tools/make_start_buildings.py).
	for pname: String in scenario.get("buildings", {}):
		for type: String in scenario.buildings[pname]:
			province_buildings[by_name[pname]][type] = int(scenario.buildings[pname][type])
	for pname: String in scenario.get("owner_changes", {}):
		var pid: int = by_name[pname]
		province_owner[pid] = scenario.owner_changes[pname]
		province_controller[pid] = scenario.owner_changes[pname]
	for row in MapData.read_table(dir + "provinces.tsv"):
		province_population[int(row.id)] = int(row.population)
	province_pop_base = province_population.duplicate()

	nations.clear()
	for tag in MapData.nations:
		nations[tag] = Nation.new(tag, MapData.nations[tag], scenario.nations.get(tag, {}))
	_rebuild_nation_provinces()
	materials_k = 0.0
	Military.deploy_starting(self)
	Navy.deploy_starting(self, dir)
	Economy.recompute(self)

	var d: Array = scenario.start_date
	Clock.start(d[0], d[1], d[2])
	Clock.paused = true
	Diplomacy.load_scenario(self)
	AI.load_scenario(self)
	Pressure.load_scenario(self)
	economy_dirty = false
	budget_dirty = false
	standings_history.clear()
	Standings.record(self)
	for pair: Array in scenario.get("starting_wars", []):
		Diplomacy.start_war(self, pair[0], pair[1], scenario.get("start_crisis", false))
	set_player(scenario.get("default_player", ""))
	scenario_loaded.emit()


## Saves the game to a file (see SaveGame). Returns "" or what went wrong.
func save_game(path: String) -> String:
	var err := SaveGame.write(self, path)
	if err.is_empty():
		game_saved.emit(path)
	return err


## Loads a save: the scenario it began from, then the saved state on top. Returns "" or what
## went wrong (a refused save leaves the game as it was).
func load_game(path: String) -> String:
	return SaveGame.read(self, path)


## What a loaded game needs to run: tables worked out from the saved state, and no cache
## filled by the game that was there before.
func finish_load() -> void:
	Diplomacy.invalidate_treaties()
	owner_version += 1
	_rebuild_nation_provinces()
	control_version += 1
	for front: Front in fronts.values():
		front.dirty = true
		front.line_stamp = -1
	Military._home_cache.clear()
	Military._home_day = -1
	Military.invalidate_aura()
	AI._index_key = -1
	AI._threat_cache.clear()
	AI._worth_cache.clear()
	AINavy._weight_day = -1
	AINavy._cordons.clear()
	Diplomacy._neighbor_version = -1
	economy_dirty = false
	budget_dirty = false
	Economy.recompute(self)
	Clock.date_changed.emit()
	Clock.pause_changed.emit(true)
	Clock.speed_changed.emit(Clock.speed)
	set_player(player_tag)
	scenario_loaded.emit()
	armies_changed.emit()
	fronts_changed.emit()
	fleets_changed.emit()
	economy_updated.emit()


## Whether the player owes an answer (a join decision or a peace offer) before time may run.
func has_pending() -> bool:
	return not pending_joins.is_empty() or not pending_offers.is_empty() or not pending_events.is_empty()


func set_player(tag: String) -> void:
	player_tag = tag
	player_changed.emit(tag)


func get_player() -> Nation:
	return nations.get(player_tag)


func owner_color(id: int) -> Color:
	return nations[province_owner[id]].color


## Transfers ownership (and control) of a province.
func transfer_province(id: int, tag: String) -> void:
	var old := province_owner[id]
	if old == tag:
		return
	province_owner[id] = tag
	province_controller[id] = tag
	control_version += 1
	owner_version += 1
	occupation.erase(id)
	# Construction by the old owner is lost with the province.
	for job in nations[old].construction.duplicate():
		if job.province == id:
			nations[old].construction.erase(job)
	_rebuild_nation_provinces()
	Economy.recompute(self)
	province_owner_changed.emit(id, old, tag)
	economy_updated.emit()


## Whether two nations are at war with each other.
func at_war(a: String, b: String) -> bool:
	return a != b and wars.has(_war_key(a, b))


## `a` starts the war when value is true. A new war joins the conflict `group` (0 starts a new one).
func set_war(a: String, b: String, value: bool, cb := "", group := 0) -> void:
	if a == b or at_war(a, b) == value:
		return
	if value:
		var war := War.new(next_war_id, a, b, Clock.days_elapsed, Clock.date_string())
		next_war_id += 1
		war.casus_belli = cb
		if group == 0:
			group = next_war_group
			next_war_group += 1
		war.war_group = group
		war.add_log(war.start_date, "war", "%s declares war on %s%s." % [nations[a].display_name, nations[b].display_name,
				" (%s)" % Diplomacy.cfg.war.casus_belli[cb].label.to_lower() if Diplomacy.cfg.war.casus_belli.has(cb) else ""])
		wars[_war_key(a, b)] = war
	else:
		var war: War = wars[_war_key(a, b)]
		war.end_day = Clock.days_elapsed
		war.end_date = Clock.date_string()
		war.add_log(war.end_date, "peace", "%s and %s make peace." % [nations[a].display_name, nations[b].display_name])
		wars.erase(_war_key(a, b))
		war_history.append(war)
	war_changed.emit(a, b, value)


## A battle by id, in progress or finished (an empty dictionary if unknown).
func battle_by_id(id: int) -> Dictionary:
	for battle: Dictionary in engagements.values():
		if battle.id == id:
			return battle
	return battle_archive.get(id, {})


## The battle in progress in a province (an empty dictionary if none).
func battle_at(province: int) -> Dictionary:
	return engagements.get(province, {})


## The war being fought between two nations, or null.
func war_between(a: String, b: String) -> War:
	return wars.get(_war_key(a, b)) if a != b else null


## Wars a nation is fighting now.
func wars_of(tag: String) -> Array[War]:
	var out: Array[War] = []
	for war: War in wars.values():
		if war.involves(tag):
			out.append(war)
	return out


## Every war, active first (newest first), then finished ones (most recent first).
func all_wars() -> Array[War]:
	var out: Array[War] = []
	var current: Array = wars.values()
	current.sort_custom(func(x: War, y: War) -> bool: return x.id > y.id)
	out.append_array(current)
	for i in range(war_history.size() - 1, -1, -1):
		out.append(war_history[i])
	return out


func _war_key(a: String, b: String) -> String:
	return "%s|%s" % [a, b] if a < b else "%s|%s" % [b, a]


## Changes who holds a province (the owner stays). The caller recomputes the economy.
func set_controller(id: int, tag: String) -> void:
	var old := province_controller[id]
	if old == tag:
		return
	province_controller[id] = tag
	control_version += 1
	Military.invalidate_aura()
	province_controller_changed.emit(id, old, tag)


## Runs a command and logs it. Returns false if it was rejected.
func issue(cmd: Command) -> bool:
	if not cmd.execute(self):
		return false
	command_log.append(cmd.to_dict())
	Economy.recompute(self)
	economy_updated.emit()
	command_issued.emit(str(cmd.get_script().get_global_name()))
	return true


## Runs a command from the AI: logged like any other, but the economy is not recomputed
## now. Dozens of orders can follow in one day; the day's step recomputes once.
func issue_quiet(cmd: Command) -> bool:
	if not cmd.execute(self):
		return false
	command_log.append(cmd.to_dict())
	if cmd.changes_economy():
		economy_dirty = true
	return true


func _rebuild_nation_provinces() -> void:
	var lists := {}
	var pops := {}
	for tag in nations:
		lists[tag] = PackedInt32Array()
		pops[tag] = 0
	for id in range(1, province_owner.size()):
		var tag := province_owner[id]
		lists[tag].append(id)
		pops[tag] += province_population[id]
	for tag in nations:
		nations[tag].provinces = lists[tag]
		nations[tag].population = pops[tag]


func _on_month_ticked() -> void:
	finish_day()
	Economy.step_month(self)
	Diplomacy.step_month(self)
	Pressure.step_month(self)
	Standings.record(self)
	economy_updated.emit()
	if autosave_enabled:
		autosave()


## Saves into the next of the rotating autosave slots (autosave_1 to autosave_3). Returns "" or
## what went wrong.
func autosave() -> String:
	var slot := (Clock.year * 12 + Clock.month) % AUTOSAVE_SLOTS + 1
	return save_game("%sautosave_%d%s" % [SaveGame.dir, slot, SaveGame.EXT])
