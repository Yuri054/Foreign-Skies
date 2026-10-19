class_name CreateArmyGroup
extends Command
## Makes a new army group of the given armies (they leave any group they were in).

var tag: String
var group_name: String
var army_ids: Array[int]
var group_id := 0


func _init(p_tag := "", p_name := "", p_ids: Array[int] = []) -> void:
	tag = p_tag
	group_name = p_name
	army_ids = p_ids


func execute(gs: Node) -> bool:
	if army_ids.is_empty():
		return false
	for id in army_ids:
		var a: Army = gs.armies.get(id)
		if a == null or a.tag != tag:
			return false
	var g := Military.new_group(gs, tag, group_name)
	group_id = g.id
	Military.put_in_group(gs, g, army_ids)
	Military.prune_groups(gs)
	gs.armies_changed.emit()
	return true


func to_dict() -> Dictionary:
	return {"type": "CreateArmyGroup", "tag": tag, "name": group_name, "armies": army_ids}


func changes_economy() -> bool:
	return false
