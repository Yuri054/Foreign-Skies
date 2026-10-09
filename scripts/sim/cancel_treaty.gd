class_name CancelTreaty
extends Command
## A party tears up a treaty (a non-aggression pact has to go before war can be declared on
## its partner). The cost is in data/diplomacy.json, war.cancel.

var canceller: String
var treaty_id: int


func _init(p_canceller := "", p_treaty_id := 0) -> void:
	canceller = p_canceller
	treaty_id = p_treaty_id


## "points" if the cancellation was refused for want of diplomacy points.
var reason := ""


func execute(gs: Node) -> bool:
	reason = ""
	for t: Treaty in gs.treaties:
		if t.id != treaty_id:
			continue
		if not t.involves(canceller) or not t.active_on(Clock.days_elapsed):
			return false
		var cost := Diplomacy.cost_of("cancel", t.kind)
		if not Diplomacy.can_afford(gs, canceller, cost):
			reason = "points"
			return false
		if not Diplomacy.cancel_treaty(gs, canceller, t):
			return false
		Diplomacy.spend(gs, canceller, cost)
		return true
	return false


func to_dict() -> Dictionary:
	return {"type": "CancelTreaty", "canceller": canceller, "treaty_id": treaty_id}
