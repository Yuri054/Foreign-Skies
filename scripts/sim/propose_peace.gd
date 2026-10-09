class_name ProposePeace
extends Command
## `from` proposes peace to `to`. In "demand" mode it takes `demands` from the other side, in
## "offer" mode it gives them (no demands is a white peace); see Peace for the demand kinds
## and prices. The command succeeds when the proposal was valid; `result` says what the
## other side answered (accepted is null while the player still has to).

var from: String
var to: String
var mode: String
var demands: Array
var result: Dictionary = {}


func _init(p_from := "", p_to := "", p_mode := "demand", p_demands := []) -> void:
	from = p_from
	to = p_to
	mode = p_mode
	demands = p_demands


func execute(gs: Node) -> bool:
	result = Peace.propose(gs, from, to, mode, demands)
	return result.ok


func to_dict() -> Dictionary:
	return {"type": "ProposePeace", "from": from, "to": to, "mode": mode, "demands": demands}
