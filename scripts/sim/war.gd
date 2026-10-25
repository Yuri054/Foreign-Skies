class_name War
extends RefCounted
## The record of one war between two nations: who started it, when it began and ended, what
## each side lost, what each took, every battle and the notable events. Fighting itself is
## done by Military; this only keeps the books.

const MAX_BATTLES := 300
const MAX_LOG := 400

var id := 0
## The nation that started the war, and the one it was started against.
var a := ""
var b := ""
## Why `a` could declare it (a casus belli id from data/diplomacy.json, "" if it was set up
## directly) and the conflict it belongs to: pairwise wars opened together share a group.
## tag -> war score earned from battles won; fades monthly (see Peace).
var battle_points: Dictionary = {}
## How the war ended, if by an accepted peace: {taker, giver, terms, white, score, forced, date}.
var peace: Dictionary = {}
var casus_belli := ""
var war_group := 0
var start_day := 0
## The day of the last battle between the two sides (-1: none yet): a war nobody fights goes stale (see AIPeace).
var last_fight_day := -1
var start_date := ""
var end_day := -1
var end_date := ""
## tag -> men killed or wounded in battle.
var losses: Dictionary = {}
## tag -> men lost to hunger and exhaustion away from supply while this war was on.
var attrition: Dictionary = {}
## tag -> men destroyed or disbanded because the army had nowhere left to go.
var surrendered: Dictionary = {}
## tag -> {provinces, population}: ground that nation took from the other.
var captured: Dictionary = {}
## One entry per finished battle: {id, province, name, date, days, attacker, winner, strength,
## lost}. The full account (timeline, events, compositions) is GameState.battle_by_id(id).
var battles: Array[Dictionary] = []
## Notable events, oldest first: {date, kind, text, province, battle} (battle is an id for
## GameState.battle_by_id, or 0).
var log: Array[Dictionary] = []


func _init(p_id := 0, p_a := "", p_b := "", p_day := 0, p_date := "") -> void:
	id = p_id
	a = p_a
	b = p_b
	start_day = p_day
	start_date = p_date
	for tag in [a, b]:
		losses[tag] = 0.0
		attrition[tag] = 0.0
		surrendered[tag] = 0.0
		battle_points[tag] = 0.0
		captured[tag] = {"provinces": 0, "population": 0}


func active() -> bool:
	return end_day < 0


func involves(tag: String) -> bool:
	return tag == a or tag == b


func other(tag: String) -> String:
	return b if tag == a else a


func add_log(date: String, kind: String, text: String, province := 0, battle := 0) -> void:
	log.append({"date": date, "kind": kind, "text": text, "province": province, "battle": battle})
	if log.size() > MAX_LOG:
		log.pop_front()


func add_battle(record: Dictionary) -> void:
	battles.append(record)
	if battles.size() > MAX_BATTLES:
		battles.pop_front()


## Battles the nation won, lost, or fought without a clear result.
func battle_count(tag: String, outcome: String) -> int:
	var n := 0
	for rec in battles:
		var result: String = "draw" if rec.winner.is_empty() else ("won" if rec.winner == tag else "lost")
		if result == outcome:
			n += 1
	return n


func days_lasted(today: int) -> int:
	return (today if active() else end_day) - start_day
