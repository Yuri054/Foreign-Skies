class_name AnswerPeace
extends Command
## The player's answer to a pending peace offer (GameState.pending_offers).

var offer_id: int
var accept: bool


func _init(p_offer_id := 0, p_accept := true) -> void:
	offer_id = p_offer_id
	accept = p_accept


func execute(gs: Node) -> bool:
	return Peace.answer(gs, offer_id, accept)


func to_dict() -> Dictionary:
	return {"type": "AnswerPeace", "offer_id": offer_id, "accept": accept}
