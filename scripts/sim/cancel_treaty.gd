class_name CancelTreaty
extends Command
## A party tears up a treaty (a non-aggression pact has to go before war can be declared on
## its partner). The cost is in data/diplomacy.json, war.cancel.

var canceller: String
var treaty_id: int


func _init(p_canceller := "", p_treaty_id := 0) -> void:
	canceller = p_canceller
	treaty_id = p_treaty_id


func execute(gs: Node) -> bool:
	for t: Treaty in gs.treaties:
		if t.id == treaty_id:
			return Diplomacy.cancel_treaty(gs, canceller, t)
	return false


func to_dict() -> Dictionary:
	return {"type": "CancelTreaty", "canceller": canceller, "treaty_id": treaty_id}
