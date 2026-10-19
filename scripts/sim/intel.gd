class_name Intel
extends RefCounted
## What the player can see of other nations' armies. The player's own armies and their allies'
## are seen exactly. Armies of nations at war with the player or an ally are seen as an estimate
## wherever they stand, and so are armies of other nations that stand on or next to ground the
## player or an ally holds or has troops on. Any other army is not seen at all. An estimate is the
## men rounded and moved up or down by up to a quarter (the same for an army all month, so it does
## not flicker), with nothing known about its units, general, morale or supply.
##
## This is about what the interface shows. The simulation and the AI work from the real figures.

const HIDDEN := 0
const ESTIMATE := 1
const EXACT := 2
## How far an estimate may be from the truth (a share of the men).
const ERROR := 0.25

static var _key := -1
static var _friends := {}
static var _enemies := {}
static var _watch := {}


## How well the player sees this army: HIDDEN, ESTIMATE or EXACT.
static func level(gs: Node, a: Army) -> int:
	if gs.player_tag == "":
		return EXACT  # nobody is playing yet (the nation picker): everything is shown
	_refresh(gs)
	if _friends.has(a.tag):
		return EXACT
	if _enemies.has(a.tag) or _watch.has(a.province):
		return ESTIMATE
	return HIDDEN


## Whether the player sees the armies of this nation exactly (their own and their allies').
static func is_friend(gs: Node, tag: String) -> bool:
	if gs.player_tag == "":
		return true
	_refresh(gs)
	return _friends.has(tag)


## Whether a province lies where the player's eyes are: on or next to ground they or their allies
## hold or have troops on.
static func sees_province(gs: Node, province: int) -> bool:
	if gs.player_tag == "":
		return true
	_refresh(gs)
	return _watch.has(province)


## The men of an army as the player knows them: exact, an estimate, or 0 if it is not seen.
static func men_seen(gs: Node, a: Army) -> float:
	match level(gs, a):
		EXACT:
			return a.men()
		ESTIMATE:
			return estimate(a.men(), a.id)
	return 0.0


## An estimate of a figure, moved by up to ERROR and rounded. `key` makes it the same each time
## for one army (or nation) within a month.
static func estimate(value: float, key: int) -> float:
	if value <= 0.0:
		return 0.0
	var month: int = Clock.year * 12 + Clock.month
	var noise := fposmod(sin(float(key) * 12.9898 + float(month) * 78.233) * 43758.5453, 1.0) * 2.0 - 1.0
	var guess: float = value * (1.0 + noise * ERROR)
	var step := 5000.0 if guess >= 25000.0 else 1000.0
	return maxf(snappedf(guess, step), step)


## An estimate as text: "~120k".
static func estimate_text(value: float) -> String:
	return "~" + Fmt.people(value)


## Works out who the player's friends and enemies are and which provinces they watch; again
## when the day, the player, the owners, the armies or the treaties have changed.
static func _refresh(gs: Node) -> void:
	var key := [Clock.days_elapsed, gs.player_tag, gs.owner_version, gs.armies.size(), gs.treaties.size(), gs.wars.size()].hash()
	if key == _key:
		return
	_key = key
	_friends.clear()
	_enemies.clear()
	_watch.clear()
	var me: String = gs.player_tag
	_friends[me] = true
	for tag: String in gs.nations:
		if tag != me and Diplomacy.are_allied(gs, me, tag):
			_friends[tag] = true
	for tag: String in gs.nations:
		if _friends.has(tag):
			continue
		for friend: String in _friends:
			if gs.at_war(friend, tag):
				_enemies[tag] = true
				break
	var eyes := {}
	for id in range(1, gs.province_controller.size()):
		if _friends.has(gs.province_controller[id]):
			eyes[id] = true
	for a: Army in gs.armies.values():
		if _friends.has(a.tag) and not a.embarked():
			eyes[a.province] = true
	for id: int in eyes:
		_watch[id] = true
		for n: int in Military.neighbors(id):
			_watch[n] = true
