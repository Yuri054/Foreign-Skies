class_name JustifyWar
extends Command
## `a` starts manufacturing a casus belli against `b`: points up front, then
## data/diplomacy.json war.justify.days of work before a fabricated claim is held.

var a: String
var b: String
## Why it was refused: "points", or a Diplomacy.justify_block reason.
var reason := ""


func _init(p_a := "", p_b := "") -> void:
	a = p_a
	b = p_b


func execute(gs: Node) -> bool:
	reason = Diplomacy.justify_block(gs, a, b)
	if reason != "":
		return false
	var cost := Diplomacy.justify_cost(gs, a)
	if not Diplomacy.can_afford(gs, a, cost):
		reason = "points"
		return false
	if not Diplomacy.start_justification(gs, a, b):
		return false
	Diplomacy.spend(gs, a, cost)
	return true


func to_dict() -> Dictionary:
	return {"type": "JustifyWar", "a": a, "b": b}


func changes_economy() -> bool:
	return false
