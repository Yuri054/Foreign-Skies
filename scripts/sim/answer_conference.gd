class_name AnswerConference
extends Command
## The player's answer to the counter-offer of a conference: accept it (the smaller package is made at once) or refuse.

var accept: bool


func _init(p_accept := false) -> void:
	accept = p_accept


func execute(gs: Node) -> bool:
	return Conference.answer_counter(gs, accept)


func to_dict() -> Dictionary:
	return {"type": "AnswerConference", "accept": accept}
