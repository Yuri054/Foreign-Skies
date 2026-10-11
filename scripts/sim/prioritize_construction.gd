class_name PrioritizeConstruction
extends Command
## Puts a building under construction first in the queue, so it is served before the rest of the
## day's construction points go on. Projects are served in queue order.

var tag: String
var province: int
var type: String


func _init(p_tag := "", p_province := 0, p_type := "") -> void:
	tag = p_tag
	province = p_province
	type = p_type


func execute(gs: Node) -> bool:
	var n: Nation = gs.nations.get(tag)
	if n == null:
		return false
	for i in n.construction.size():
		var job: Dictionary = n.construction[i]
		if job.province == province and job.type == type:
			if i == 0:
				return false
			n.construction.remove_at(i)
			n.construction.insert(0, job)
			return true
	return false


func changes_economy() -> bool:
	return false


func to_dict() -> Dictionary:
	return {"type": "PrioritizeConstruction", "tag": tag, "province": province, "building": type}
