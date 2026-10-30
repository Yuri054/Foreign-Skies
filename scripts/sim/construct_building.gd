class_name ConstructBuilding
extends Command
## Queues one level of a building in a province. The queue starts it as soon as the province is free and its gold and
## construction points are there (Economy.start_queued): they are paid then, and it is finished after its days.

var tag: String
var province: int
var type: String


func _init(p_tag := "", p_province := 0, p_type := "") -> void:
	tag = p_tag
	province = p_province
	type = p_type


func execute(gs: Node) -> bool:
	if not Economy.build_problem(gs, tag, province, type).is_empty():
		return false
	var n: Nation = gs.nations[tag]
	n.construction.append(Economy.new_job(province, type, Economy.build_plan(gs, province, type).days))
	Economy.start_queued(gs, tag)
	return true


func to_dict() -> Dictionary:
	return {"type": "ConstructBuilding", "tag": tag, "province": province, "building": type}
