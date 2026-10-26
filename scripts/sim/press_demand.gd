class_name PressDemand
extends Command
## `a` presses a demand of a kind (see Crisis.demand_options) on `b`: a crisis opens, for diplomacy points, and `b` must answer.

var a: String
var b: String
var kind: String
## Why it was refused: "points", or a Crisis.press_block reason ("" when it was not).
var reason := ""


func _init(p_a := "", p_b := "", p_kind := "") -> void:
	a = p_a
	b = p_b
	kind = p_kind


func execute(gs: Node) -> bool:
	reason = Crisis.press_block(gs, a, b) if gs.nations.has(a) and gs.nations.has(b) else "unknown"
	if reason != "":
		return false
	return not Crisis.press(gs, a, b, kind).is_empty()


func to_dict() -> Dictionary:
	return {"type": "PressDemand", "a": a, "b": b, "kind": kind}
