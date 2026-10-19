class_name AssignToGroup
extends Command
## Moves armies into an army group (group 0 takes them out of whichever group they are in).

var tag: String
var group_id: int
var army_ids: Array[int]


func _init(p_tag := "", p_group := 0, p_ids: Array[int] = []) -> void:
	tag = p_tag
	group_id = p_group
	army_ids = p_ids


func execute(gs: Node) -> bool:
	if army_ids.is_empty():
		return false
	var g: ArmyGroup = gs.army_groups.get(group_id)
	if group_id != 0 and (g == null or g.tag != tag):
		return false
	for id in army_ids:
		var a: Army = gs.armies.get(id)
		if a == null or a.tag != tag:
			return false
	Military.put_in_group(gs, g, army_ids)
	Military.prune_groups(gs)
	gs.armies_changed.emit()
	return true


func to_dict() -> Dictionary:
	return {"type": "AssignToGroup", "tag": tag, "group": group_id, "armies": army_ids}


func changes_economy() -> bool:
	return false
