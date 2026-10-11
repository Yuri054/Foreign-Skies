class_name SetProductionAuto
extends Command
## Puts a nation's equipment production on or off automatic: the factories are shared between the
## categories by the rules in Production, and lines the player opened are folded into them.

var tag: String
var on: bool


func _init(p_tag := "", p_on := true) -> void:
	tag = p_tag
	on = p_on


func execute(gs: Node) -> bool:
	var n: Nation = gs.nations.get(tag)
	if n == null:
		return false
	n.lines_auto = on
	if on:
		Production.auto_assign(n)
	return true


func to_dict() -> Dictionary:
	return {"type": "SetProductionAuto", "tag": tag, "on": on}
