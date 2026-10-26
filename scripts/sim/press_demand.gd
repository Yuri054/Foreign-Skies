class_name PressDemand
extends Command
## `a` presses a demand on `b`: a crisis opens, for diplomacy points, and `b` must answer. The demand is `custom`
## ({demand, goal}, as the goal picker makes it) or else the one of `kind` among Crisis.demand_options.

var a: String
var b: String
var kind: String
var custom: Dictionary
## Why it was refused: "points", or a Crisis.press_block reason ("" when it was not).
var reason := ""


func _init(p_a := "", p_b := "", p_kind := "", p_custom := {}) -> void:
	a = p_a
	b = p_b
	kind = p_kind
	custom = p_custom


func execute(gs: Node) -> bool:
	reason = Crisis.press_block(gs, a, b, not custom.is_empty()) if gs.nations.has(a) and gs.nations.has(b) else "unknown"
	if reason != "":
		return false
	if not custom.is_empty():
		reason = Crisis.custom_problem(gs, a, b, custom)
		if reason == "" and not Diplomacy.can_afford(gs, a, Crisis.press_cost(gs, a, custom.goal)):
			reason = "points"
		if reason != "":
			return false
	return not Crisis.press(gs, a, b, kind, custom).is_empty()


func to_dict() -> Dictionary:
	return {"type": "PressDemand", "a": a, "b": b, "kind": kind, "custom": custom}
