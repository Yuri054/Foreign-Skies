class_name DeclareWar
extends Command
## `a` declares war on `b` with a casus belli (see Diplomacy.casus_belli_options). Replaces
## SetWar as the way wars start; SetWar stays for tests and the Military panel's debug switch.

var a: String
var b: String
var casus_belli: String
var group: int


func _init(p_a := "", p_b := "", p_cb := "none", p_group := 0) -> void:
	a = p_a
	b = p_b
	casus_belli = p_cb
	group = p_group


## "points" if the declaration was refused for want of diplomacy points.
var reason := ""


func execute(gs: Node) -> bool:
	reason = ""
	var cost := Diplomacy.cost_of("declare_war", casus_belli)
	if not Diplomacy.can_declare(gs, a, b, casus_belli):
		return false
	if not Diplomacy.can_afford(gs, a, cost):
		reason = "points"
		return false
	if not Diplomacy.declare_war(gs, a, b, casus_belli, group):
		return false
	Diplomacy.spend(gs, a, cost)
	return true


func to_dict() -> Dictionary:
	return {"type": "DeclareWar", "a": a, "b": b, "casus_belli": casus_belli, "group": group}
