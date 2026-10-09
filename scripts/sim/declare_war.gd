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


func execute(gs: Node) -> bool:
	return Diplomacy.declare_war(gs, a, b, casus_belli, group)


func to_dict() -> Dictionary:
	return {"type": "DeclareWar", "a": a, "b": b, "casus_belli": casus_belli, "group": group}
