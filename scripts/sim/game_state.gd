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
signal ship_built(tag: String, province: int, type: String)
signal war_changed(a: String, b: String, at_war: bool)
## A nation lost its last province and its armies broke up.
signal nation_collapsed(tag: String, men: int)
## A treaty was signed (added is true) or ended.
signal treaty_changed(treaty: Treaty, added: bool)
signal relations_changed(a: String, b: String)
## The player must answer a join decision (see Diplomacy.offer_joins); time is held until then.
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

const DEFAULT_SCENARIO := "res://data/scenarios/july_1914/"

var scenario: Dictionary = {}
var player_tag := ""
## tag -> Nation
var nations: Dictionary = {}
## Indexed by province id (element 0 unused).
var province_owner: PackedStringArray = []
## Counts changes of ownership, so things worked out from the borders can be cached.
var owner_version := 0
var province_controller: PackedStringArray = []
var province_population := PackedInt32Array()
## Province output before nation-wide modifiers; filled by Economy.recompute.
var province_gdp := PackedFloat32Array()       # GBP millions per year
var province_industry := PackedFloat32Array()  # GBP millions per year
var province_food := PackedFloat32Array()      # people the land can feed
var province_pool := PackedFloat32Array()      # recruitable men
## Indexed by province id: resource id -> potential output in thousand tonnes per year.
var province_deposit: Array[Dictionary] = []
## Indexed by province id: building type -> level.
var province_buildings: Array[Dictionary] = []
## army id -> Army.
var armies: Dictionary = {}
var next_army_id := 1
## id -> Fleet.
var fleets: Dictionary = {}
var next_fleet_id := 1
## Naval bases (dockyards) from the scenario: province id -> level. They count as a port for
## the navy, but not for the economy, so the 1914 trade figures stay as calibrated.
var naval_bases: Dictionary = {}
## Fights at sea now, by zone, and the accounts of those that have ended, by id.
var sea_battles: Dictionary = {}
var sea_battle_archive: Dictionary = {}
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
## Every command issued so far, in order.
var command_log: Array[Dictionary] = []
## AI temperament overrides by nation (aggression, caution), and the plans read from the
## scenario: [{nation, enemy, posture, objectives: [{province, weight}]}]. See AI.
var ai_traits: Dictionary = {}
var ai_plans: Array[Dictionary] = []
## Wars the AI has declared so far, and how many of them had no casus belli. Declarations by
## the player do not count.
var ai_declarations := {"total": 0, "unjustified": 0}
## The AI's reserve army by nation: tag -> army id (see AIDefense).
var ai_reserve: Dictionary = {}
## The AI's campaign by nation (see AIOffense), and the day before which it will not look
## for a new one.
var ai_campaign: Dictionary = {}
var ai_campaign_wait: Dictionary = {}
## The month (year * 12 + month) in which each AI nation last weighed treaties.
var ai_diplo_stamp: Dictionary = {}
## The month (year * 12 + month) in which each AI nation last did its budget.
var ai_budget_stamp: Dictionary = {}
## False turns the computer players off (tests of the other systems, or watching a war
## with nobody at the controls).
var ai_enabled := true
## Set by issue_quiet; the day's step recomputes the economy once if it is true.
var economy_dirty := false


func _ready() -> void:
	load_scenario(DEFAULT_SCENARIO)
	Clock.day_ticked.connect(func() -> void:
		Economy.step_day(self)
		Navy.step_day(self)
		Military.step_day(self)
		Diplomacy.step_day(self)
		AI.step_day(self)
		if economy_dirty:
			economy_dirty = false
			Economy.recompute(self)
			economy_updated.emit()
	)
	Clock.month_ticked.connect(_on_month_ticked)


func load_scenario(dir: String) -> void:
	Economy.load_config()
	Military.load_config()
	Navy.load_config()
	Diplomacy.load_config()
	AI.load_config()
	command_log.clear()
	wars.clear()
	war_history.clear()
	next_war_id = 1
	next_war_group = 1
	engagements.clear()
	battle_archive.clear()
	sea_battles.clear()
	sea_battle_archive.clear()
	next_battle_id = 1
	occupation.clear()
	fronts.clear()
	next_front_id = 1
	scenario = JSON.parse_string(FileAccess.get_file_as_string(dir + "scenario.json"))
	assert(scenario is Dictionary, "scenario.json is invalid")

	var count := MapData.provinces.size()
	province_owner.resize(count)
	province_controller.resize(count)
	province_population.resize(count)
	province_buildings.clear()
	province_deposit.clear()
	for i in count:
		province_buildings.append({})
		province_deposit.append({})
	for row in MapData.read_table(dir + "resources.tsv"):
		for r in Economy.resource_ids():
			province_deposit[int(row.id)][r] = float(row[r])
	_build_starting_mines()
	for id in range(1, count):
		province_owner[id] = MapData.provinces[id].owner
		owner_version += 1
		province_controller[id] = MapData.provinces[id].owner
	for row in MapData.read_table(dir + "provinces.tsv"):
		province_population[int(row.id)] = int(row.population)

	nations.clear()
	for tag in MapData.nations:
		nations[tag] = Nation.new(tag, MapData.nations[tag], scenario.nations.get(tag, {}))
	_rebuild_nation_provinces()
	Military.deploy_starting(self)
	Navy.deploy_starting(self, dir)
	Economy.recompute(self)
	# Start with half a full reserve of everything the nation uses.
	for tag in nations:
		for r in Economy.resource_ids():
			nations[tag].stock[r] = 0.5 * nations[tag].budget.resources[r].cap
	Economy.recompute(self)

	var d: Array = scenario.start_date
	Clock.start(d[0], d[1], d[2])
	Clock.paused = true
	Diplomacy.load_scenario(self)
	AI.load_scenario(self)
	economy_dirty = false
	standings_history.clear()
	Standings.record(self)
	for pair: Array in scenario.get("starting_wars", []):
		Diplomacy.start_war(self, pair[0], pair[1], scenario.get("start_crisis", false))
	set_player(scenario.get("default_player", ""))
	scenario_loaded.emit()


## Mines and sawmills that already work at the start, wherever a deposit exists.
func _build_starting_mines() -> void:
	var start: Dictionary = scenario.get("starting_buildings", {})
	for id in range(1, province_deposit.size()):
		for type in start:
			var resource: String = Economy.cfg.buildings[type].requires.trim_prefix("deposit:")
			if province_deposit[id].get(resource, 0.0) >= Economy.cfg.min_deposit:
				province_buildings[id][type] = int(start[type])


## Whether the player owes an answer (a join decision or a peace offer) before time may run.
func has_pending() -> bool:
	return not pending_joins.is_empty() or not pending_offers.is_empty()


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
	province_controller_changed.emit(id, old, tag)


## Runs a command and logs it. Returns false if it was rejected.
func issue(cmd: Command) -> bool:
	if not cmd.execute(self):
		return false
	command_log.append(cmd.to_dict())
	Economy.recompute(self)
	economy_updated.emit()
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
	Economy.step_month(self)
	Diplomacy.step_month(self)
	Standings.record(self)
	economy_updated.emit()
