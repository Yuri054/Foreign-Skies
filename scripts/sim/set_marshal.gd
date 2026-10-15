class_name SetMarshal
extends Command
## Puts a general of the pool at the head of an army group (general 0 relieves the marshal).
## A general who leads an army or another group cannot be made marshal.

var tag: String
var group_id: int
var general_id: int


func _init(p_tag := "", p_group := 0, p_general := 0) -> void:
	tag = p_tag
	group_id = p_group
	general_id = p_general


func execute(gs: Node) -> bool:
	var grp: ArmyGroup = gs.army_groups.get(group_id)
	if grp == null or grp.tag != tag:
		return false
	if general_id == 0:
		if grp.marshal_id == 0:
			return false
		Military.set_marshal(gs, grp, null)
	else:
		var g: General = gs.generals.get(general_id)
		if g == null or g.tag != tag or g.army_id != 0 or g.group_id != 0:
			return false
		Military.set_marshal(gs, grp, g)
	gs.armies_changed.emit()
	return true


func to_dict() -> Dictionary:
	return {"type": "SetMarshal", "tag": tag, "group": group_id, "general": general_id}


func changes_economy() -> bool:
	return false
