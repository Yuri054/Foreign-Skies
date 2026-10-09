class_name MergeArmies
extends Command
## Combines armies of one nation standing in the same province into the first one listed.

var tag: String
var army_ids: Array[int]


func _init(p_tag := "", p_ids: Array[int] = []) -> void:
	tag = p_tag
	army_ids = p_ids


func execute(gs: Node) -> bool:
	if army_ids.size() < 2:
		return false
	var target: Army = gs.armies.get(army_ids[0])
	if target == null or target.tag != tag:
		return false
	var others: Array[Army] = []
	for i in range(1, army_ids.size()):
		var a: Army = gs.armies.get(army_ids[i])
		if a == null or a == target or a.tag != tag or a.province != target.province:
			return false
		others.append(a)
	for a in others:
		target.units.append_array(a.units)
		if a.general_skill > target.general_skill:
			target.general_name = a.general_name
			target.general_skill = a.general_skill
		target.still_days = mini(target.still_days, a.still_days)
		gs.armies.erase(a.id)
	target.path.clear()
	gs.armies_changed.emit()
	return true


func to_dict() -> Dictionary:
	return {"type": "MergeArmies", "tag": tag, "armies": army_ids}


func changes_economy() -> bool:
	return false
