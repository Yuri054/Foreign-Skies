class_name RaiseUnits
extends Command
## Starts training units in a province the nation owns and holds. Recruits and money are paid
## up front; the units join an army standing there (or form a new one) when training ends.

var tag: String
var province: int
var unit_type: String
var count: int


func _init(p_tag := "", p_province := 0, p_type := "", p_count := 1) -> void:
	tag = p_tag
	province = p_province
	unit_type = p_type
	count = p_count


## Why this cannot be done, or "" if it can.
static func problem(gs: Node, p_tag: String, p_province: int, p_type: String, p_count: int) -> String:
	var n: Nation = gs.nations.get(p_tag)
	if n == null or not Military.cfg.unit_types.has(p_type) or p_count < 1:
		return "Invalid order."
	if p_province < 1 or p_province >= gs.province_owner.size():
		return "Choose a province."
	if gs.province_owner[p_province] != p_tag or gs.province_controller[p_province] != p_tag:
		return "You must own and hold the province."
	var def: Dictionary = Military.cfg.unit_types[p_type]
	if n.manpower < def.size * p_count:
		return "Not enough recruits."
	if n.treasury < def.cost * p_count:
		return "Not enough money."
	return ""


func execute(gs: Node) -> bool:
	if not problem(gs, tag, province, unit_type, count).is_empty():
		return false
	var n: Nation = gs.nations[tag]
	var def: Dictionary = Military.cfg.unit_types[unit_type]
	n.manpower -= def.size * count
	n.treasury -= def.cost * count
	for i in count:
		n.recruiting.append({"type": unit_type, "province": province, "days_left": def.train_days})
	Military.refresh_men(gs)
	gs.armies_changed.emit()
	return true


func to_dict() -> Dictionary:
	return {"type": "RaiseUnits", "tag": tag, "province": province, "unit": unit_type, "count": count}
