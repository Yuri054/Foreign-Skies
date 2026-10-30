class_name RaiseShips
extends Command
## Starts building squadrons in a port the nation owns and holds. The gold is paid up front; the
## ships are launched after their build days and join a fleet in the port.

var tag: String
var province: int
var ship_type: String
var count: int


func _init(p_tag := "", p_province := 0, p_type := "", p_count := 1) -> void:
	tag = p_tag
	province = p_province
	ship_type = p_type
	count = p_count


func execute(gs: Node) -> bool:
	if not Navy.build_problem(gs, tag, province, ship_type, count).is_empty():
		return false
	var n: Nation = gs.nations[tag]
	var plan := Navy.ship_plan(gs, tag, ship_type, count)
	n.treasury -= plan.total
	var days: int = Navy.cfg.types[ship_type].build_days
	for i in count:
		n.shipbuilding.append({"type": ship_type, "province": province, "days_total": days, "days_left": days})
	gs.fleets_changed.emit()
	return true


func to_dict() -> Dictionary:
	return {"type": "RaiseShips", "tag": tag, "province": province, "ship": ship_type, "count": count}
