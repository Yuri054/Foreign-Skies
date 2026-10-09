class_name ConstructBuilding
extends Command
## Starts building one level of a building in a province. Gold and materials are paid up
## front: materials come out of the national stockpile and any shortfall is bought.

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
	n.treasury -= plan.total
	for r in plan.from_stock:
		n.stock[r] -= plan.from_stock[r]
	n.construction.append({
		"province": province,
		"type": type,
		"days_total": Economy.cfg.buildings[type].build_days,
		"days_left": Economy.cfg.buildings[type].build_days,
	})
	return true


func to_dict() -> Dictionary:
	return {"type": "ConstructBuilding", "tag": tag, "province": province, "building": type}
