class_name Gift
extends Command
## `from` sends `amount` (GBP millions) to `to`, which improves the receiver's opinion.

var from: String
var to: String
var amount: float


func _init(p_from := "", p_to := "", p_amount := 0.0) -> void:
	from = p_from
	to = p_to
	amount = p_amount


func execute(gs: Node) -> bool:
	return Diplomacy.gift(gs, from, to, amount)


func to_dict() -> Dictionary:
	return {"type": "Gift", "from": from, "to": to, "amount": amount}
