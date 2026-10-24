class_name AnswerEvent
extends Command
## The player's answer to a historical event (GameState.pending_events): the number of the option chosen.

var decision_id: int
var option: int


func _init(p_decision_id := 0, p_option := 0) -> void:
	decision_id = p_decision_id
	option = p_option


func execute(gs: Node) -> bool:
	return Pressure.answer(gs, decision_id, option)


func to_dict() -> Dictionary:
	return {"type": "AnswerEvent", "decision_id": decision_id, "option": option}
