class_name DisbandArmyGroup
extends Command
## Dissolves an army group; its armies stay where they are and its marshal returns to the pool.

var tag: String
var group_id: int


func _init(p_tag := "", p_group := 0) -> void:
	tag = p_tag
	group_id = p_group


func execute(gs: Node) -> bool:
	var g: ArmyGroup = gs.army_groups.get(group_id)
	if g == null or g.tag != tag:
		return false
	Military.remove_group(gs, g)
	gs.armies_changed.emit()
	return true


func to_dict() -> Dictionary:
	return {"type": "DisbandArmyGroup", "tag": tag, "group": group_id}


func changes_economy() -> bool:
	return false
