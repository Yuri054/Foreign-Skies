class_name AssignGeneral
extends Command
## Puts a general in command of an army (army 0 takes him off his army and back into the
## pool). An army that already has a general sends him back to the pool; a general who leads
## another army is moved, leaving that army without one.

var tag: String
var general_id: int
var army_id: int


func _init(p_tag := "", p_general := 0, p_army := 0) -> void:
	tag = p_tag
	general_id = p_general
	army_id = p_army


func execute(gs: Node) -> bool:
	var g: General = gs.generals.get(general_id)
	if g == null or g.tag != tag or g.group_id != 0:
		return false
	if army_id == 0:
		if g.army_id == 0:
			return false
		Military.set_general(gs, null, gs.armies.get(g.army_id))
	else:
		var a: Army = gs.armies.get(army_id)
		if a == null or a.tag != tag or a.general_id == g.id:
			return false
		Military.set_general(gs, g, a)
	gs.armies_changed.emit()
	return true


func to_dict() -> Dictionary:
	return {"type": "AssignGeneral", "tag": tag, "general": general_id, "army": army_id}


func changes_economy() -> bool:
	return false
