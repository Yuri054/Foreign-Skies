class_name SetArmyIcon
extends Command
## Chooses the map symbol of some armies (see "icons" in data/military.json).

var tag: String
var army_ids: Array[int]
var icon: String


func _init(p_tag := "", p_ids: Array[int] = [], p_icon := "auto") -> void:
	tag = p_tag
	army_ids = p_ids
	icon = p_icon


func execute(gs: Node) -> bool:
	if army_ids.is_empty() or not Military.cfg.icons.has(icon):
		return false
	for id in army_ids:
		var a: Army = gs.armies.get(id)
		if a == null or a.tag != tag:
			return false
	for id in army_ids:
		gs.armies[id].icon = icon
	gs.armies_changed.emit()
	return true


func to_dict() -> Dictionary:
	return {"type": "SetArmyIcon", "tag": tag, "armies": army_ids, "icon": icon}


func changes_economy() -> bool:
	return false
