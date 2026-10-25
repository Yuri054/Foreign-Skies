class_name SetFrontAnchors
extends Command
## Tells a front to mass its armies on a few provinces of its line (an empty list spreads them along all of it again).

var tag: String
var front_id: int
var provinces: Array[int]


func _init(p_tag := "", p_front := 0, p_provinces: Array[int] = []) -> void:
	tag = p_tag
	front_id = p_front
	provinces = p_provinces


func execute(gs: Node) -> bool:
	var f: Front = gs.fronts.get(front_id)
	if f == null or f.tag != tag:
		return false
	for p in provinces:
		if not f.provinces.has(p):
			return false
	if f.anchors == provinces:
		return true
	f.anchors = provinces.duplicate()
	f.dirty = true
	gs.fronts_changed.emit()
	return true


func to_dict() -> Dictionary:
	return {"type": "SetFrontAnchors", "tag": tag, "front": front_id, "provinces": provinces}


func changes_economy() -> bool:
	return false
