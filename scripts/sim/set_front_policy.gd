class_name SetFrontPolicy
extends Command
## Sets how a front is held (docs/FRONTLINES.md): "cohesion" ("rigid", "balanced" or "flexible": how far along the
## line a division may be sent to fill a gap, see FrontSolver).

const VALUES := {"cohesion": ["rigid", "balanced", "flexible"]}

var tag: String
var front_id: int
var key: String
var value: String


func _init(p_tag := "", p_front := 0, p_key := "", p_value := "") -> void:
	tag = p_tag
	front_id = p_front
	key = p_key
	value = p_value


func execute(gs: Node) -> bool:
	var f: Front = gs.fronts.get(front_id)
	if f == null or f.tag != tag or not VALUES.has(key) or not (VALUES[key] as Array).has(value):
		return false
	f.set(key, value)
	gs.fronts_changed.emit()
	return true


func to_dict() -> Dictionary:
	return {"type": "SetFrontPolicy", "tag": tag, "front": front_id, "key": key, "value": value}


func changes_economy() -> bool:
	return false
