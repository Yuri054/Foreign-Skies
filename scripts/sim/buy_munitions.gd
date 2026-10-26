class_name BuyMunitions
extends Command
## `tag` spends `amount` GBP millions on munitions bought abroad (see Munitions.bought_for: a blockade cuts what
## arrives). Refused if the treasury cannot pay.

var tag: String
var amount: float
## What arrived, in IC of munitions.
var bought := 0.0


func _init(p_tag := "", p_amount := 0.0) -> void:
	tag = p_tag
	amount = p_amount


func execute(gs: Node) -> bool:
	var n: Nation = gs.nations.get(tag)
	if n == null or amount <= 0.0 or n.treasury < amount:
		return false
	n.treasury -= amount
	bought = Munitions.bought_for(n, amount)
	n.munitions += bought
	return true


func changes_economy() -> bool:
	return true


func to_dict() -> Dictionary:
	return {"type": "BuyMunitions", "tag": tag, "amount": amount}
