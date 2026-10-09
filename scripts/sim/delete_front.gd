class_name DeleteFront
extends Command
## Removes a front; its armies stay where they are.

var tag: String
var front_id: int


func _init(p_tag := "", p_front := 0) -> void:
	tag = p_tag
	front_id = p_front


func execute(gs: Node) -> bool:
	var f: Front = gs.fronts.get(front_id)
	if f == null or f.tag != tag:
		return false
	for id in f.army_ids:
		if gs.armies.has(id):
			gs.armies[id].front_id = 0
	gs.fronts.erase(front_id)
	gs.fronts_changed.emit()
	return true


func to_dict() -> Dictionary:
	return {"type": "DeleteFront", "tag": tag, "front": front_id}


func changes_economy() -> bool:
	return false
