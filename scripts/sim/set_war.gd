class_name SetWar
extends Command
## Puts two nations at war or at peace. A stand-in for the diplomacy of phase 5, so combat
## and occupation can be tried before declarations and peace deals exist.

var a: String
var b: String
var at_war: bool


func _init(p_a := "", p_b := "", p_at_war := true) -> void:
	a = p_a
	b = p_b
	at_war = p_at_war


func execute(gs: Node) -> bool:
	if a == b or not gs.nations.has(a) or not gs.nations.has(b):
		return false
	gs.set_war(a, b, at_war)
	return true


func to_dict() -> Dictionary:
	return {"type": "SetWar", "a": a, "b": b, "at_war": at_war}
