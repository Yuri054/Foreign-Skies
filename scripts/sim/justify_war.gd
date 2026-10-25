class_name JustifyWar
extends Command
## `a` starts manufacturing a casus belli against `b`: points up front, then
## data/diplomacy.json war.justify.days of work (or the goal's own days) before a fabricated claim is held.

var a: String
var b: String
## What the war is to be for (see WarGoal); {} for a bare fabricated claim.
var goal: Dictionary
## Why it was refused: "points", or a Diplomacy.justify_block reason.
var reason := ""


func _init(p_a := "", p_b := "", p_goal := {}) -> void:
	a = p_a
	b = p_b
	goal = p_goal


func execute(gs: Node) -> bool:
	reason = Diplomacy.justify_block(gs, a, b)
	if reason != "":
		return false
	if not goal.is_empty() and WarGoal.invalid(gs, a, b, goal) != "":
		reason = "goal"
		return false
	var cost := Diplomacy.justify_cost(gs, a, goal)
	if not Diplomacy.can_afford(gs, a, cost):
		reason = "points"
		return false
	if not Diplomacy.start_justification(gs, a, b, goal):
		return false
	Diplomacy.spend(gs, a, cost)
	return true


func to_dict() -> Dictionary:
	return {"type": "JustifyWar", "a": a, "b": b, "goal": goal}


func changes_economy() -> bool:
	return false
