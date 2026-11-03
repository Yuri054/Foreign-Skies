class_name Gift
extends Command
## `from` sends `amount` (gold) to `to`, which improves the receiver's opinion.

var from: String
var to: String
var amount: float


func _init(p_from := "", p_to := "", p_amount := 0.0) -> void:
	from = p_from
	to = p_to
	amount = p_amount


## "points" if the gift was refused for want of diplomacy points.
var reason := ""


func execute(gs: Node) -> bool:
	reason = ""
	var cost := Diplomacy.cost_of("gift")
	if not Diplomacy.can_afford(gs, from, cost):
		reason = "points"
		return false
	if not Diplomacy.gift(gs, from, to, amount):
		return false
	Diplomacy.spend(gs, from, cost)
	return true


func to_dict() -> Dictionary:
	return {"type": "Gift", "from": from, "to": to, "amount": amount}
