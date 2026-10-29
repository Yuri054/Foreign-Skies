class_name SetFrontLine
extends Command
## Reshapes a front drawn by hand (a line, a fallback line or a garrison): its provinces are replaced by these. A border
## front follows the border and cannot be reshaped.

var tag: String
var front_id: int
var provinces: Array[int]


func _init(p_tag := "", p_front := 0, p_provinces: Array[int] = []) -> void:
	tag = p_tag
	front_id = p_front
	provinces = p_provinces


## Why the front cannot take this shape, or "".
static func problem(gs: Node, p_tag: String, p_front: int, line: Array[int]) -> String:
	var f: Front = gs.fronts.get(p_front)
	if f == null or f.tag != p_tag:
		return "Choose one of your fronts."
	if not f.against.is_empty():
		return "A border front follows the border; draw a line of your own to shape it."
	return DesignateFront.problem(gs, p_tag, line, "", f.kind)


func execute(gs: Node) -> bool:
	if not problem(gs, tag, front_id, provinces).is_empty():
		return false
	var f: Front = gs.fronts[front_id]
	f.provinces = provinces.duplicate()
	f.order.clear()
	f.weights_day = -1
	f.dirty = true
	gs.fronts_changed.emit()
	return true


func to_dict() -> Dictionary:
	return {"type": "SetFrontLine", "tag": tag, "front": front_id, "provinces": provinces}


func changes_economy() -> bool:
	return false
