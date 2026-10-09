class_name BuyPoints
extends Command
## Pays a batch of money for diplomacy points. The price rises with each purchase and eases back
## over the months (see Diplomacy.buy_points).

var tag: String
## "money" or "full" if the purchase was refused.
var reason := ""


func _init(p_tag := "") -> void:
	tag = p_tag


func execute(gs: Node) -> bool:
	reason = Diplomacy.purchase_block(gs, tag)
	return reason == "" and Diplomacy.buy_points(gs, tag)


func to_dict() -> Dictionary:
	return {"type": "BuyPoints", "tag": tag}
