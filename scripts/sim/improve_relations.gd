class_name ImproveRelations
extends Command
## `from` starts an effort to improve relations with `to`: a year of slow gains in how the two
## regard each other. Costs diplomacy points up front; at most three efforts at a time.

var from: String
var to: String
## Why it was refused: "points", or a Diplomacy.improve_block reason.
var reason := ""


func _init(p_from := "", p_to := "") -> void:
	from = p_from
	to = p_to


func execute(gs: Node) -> bool:
	reason = Diplomacy.improve_block(gs, from, to)
	if reason != "":
		return false
	var cost := Diplomacy.cost_of("improve_relations")
	if not Diplomacy.can_afford(gs, from, cost):
		reason = "points"
		return false
	if not Diplomacy.improve_relations(gs, from, to):
		return false
	Diplomacy.spend(gs, from, cost)
	return true


func to_dict() -> Dictionary:
	return {"type": "ImproveRelations", "from": from, "to": to}


func changes_economy() -> bool:
	return false
