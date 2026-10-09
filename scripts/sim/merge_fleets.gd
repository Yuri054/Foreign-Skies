class_name MergeFleets
extends Command
## Combines fleets of one nation standing together (in the same port, or the same zone at sea)
## into the first one listed.

var tag: String
var fleet_ids: Array[int]


func _init(p_tag := "", p_ids: Array[int] = []) -> void:
	tag = p_tag
	fleet_ids = p_ids


func execute(gs: Node) -> bool:
	if fleet_ids.size() < 2:
		return false
	var target: Fleet = gs.fleets.get(fleet_ids[0])
	if target == null or target.tag != tag or target.fighting:
		return false
	var others: Array[Fleet] = []
	for i in range(1, fleet_ids.size()):
		var f: Fleet = gs.fleets.get(fleet_ids[i])
		if f == null or f == target or f.tag != tag or f.port != target.port or f.zone != target.zone or f.fighting:
			return false
		others.append(f)
	for f in others:
		target.ships.append_array(f.ships)
		for a: Army in gs.armies.values():
			if a.fleet_id == f.id:
				a.fleet_id = target.id
		gs.fleets.erase(f.id)
	target.path.clear()
	target.landing = 0
	target.entering = false
	target.dest_port = 0
	gs.fleets_changed.emit()
	return true


func to_dict() -> Dictionary:
	return {"type": "MergeFleets", "tag": tag, "fleets": fleet_ids}


func changes_economy() -> bool:
	return false
