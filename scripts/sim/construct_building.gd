class_name ConstructBuilding
extends Command
## Starts building one level of a building in a province. Its money (Economy.build_plan's gold) is paid when it is
## begun; then the project joins the queue and takes in what the nation's construction capacity (IC) gives it each day.

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
	var plan := Economy.build_plan(gs, province, type)
	n.treasury -= float(plan.gold)
	n.construction.append(Economy.new_job(province, type, plan.ic, plan.days))
	return true


func to_dict() -> Dictionary:
	return {"type": "ConstructBuilding", "tag": tag, "province": province, "building": type}
