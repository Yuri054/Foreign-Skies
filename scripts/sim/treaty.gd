class_name Treaty
extends RefCounted
## One standing agreement between two nations. Kinds are listed in data/diplomacy.json:
## alliance, nap and neutral_pact bind both sides; guarantee (a guarantees b) and passage
## (a lets b's armies cross) run one way, from a to b.

var id := 0
var kind := ""
var a := ""
var b := ""
var start_day := 0
## Day the treaty lapses, or -1 if it has no end.
var end_day := -1
## Kind-specific clauses, e.g. an alliance's {"defensive_only": true} or {"entente": true}
## (a friendship that asks for a join decision instead of binding automatically).
var terms: Dictionary = {}
var note := ""


func _init(p_id := 0, p_kind := "", p_a := "", p_b := "", p_start := 0, p_end := -1, p_terms := {}, p_note := "") -> void:
	id = p_id
	kind = p_kind
	a = p_a
	b = p_b
	start_day = p_start
	end_day = p_end
	terms = p_terms
	note = p_note


func involves(tag: String) -> bool:
	return a == tag or b == tag


## The other party, or "" if `tag` is not in the treaty.
func other(tag: String) -> String:
	if tag == a:
		return b
	return a if tag == b else ""


func active_on(day: int) -> bool:
	return day >= start_day and (end_day < 0 or day < end_day)
