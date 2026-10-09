class_name AnswerJoin
extends Command
## The player's answer to a join decision (GameState.pending_joins): honour an alliance,
## guarantee or entente by entering the war, or stay out and take the consequences.

var decision_id: int
var joins: bool


func _init(p_decision_id := 0, p_joins := true) -> void:
	decision_id = p_decision_id
	joins = p_joins


func execute(gs: Node) -> bool:
	return Diplomacy.answer_join(gs, decision_id, joins)


func to_dict() -> Dictionary:
	return {"type": "AnswerJoin", "decision_id": decision_id, "joins": joins}
