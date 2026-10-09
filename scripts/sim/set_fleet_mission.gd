class_name SetFleetMission
extends Command
## Gives a fleet its standing orders (a key of "missions" in data/navy.json).

var tag: String
var fleet_id: int
var mission: String


func _init(p_tag := "", p_fleet := 0, p_mission := "station") -> void:
	tag = p_tag
	fleet_id = p_fleet
	mission = p_mission


func execute(gs: Node) -> bool:
	var f: Fleet = gs.fleets.get(fleet_id)
	if f == null or f.tag != tag or not Navy.cfg.missions.has(mission):
		return false
	f.mission = mission
	gs.fleets_changed.emit()
	return true


func to_dict() -> Dictionary:
	return {"type": "SetFleetMission", "tag": tag, "fleet": fleet_id, "mission": mission}


func changes_economy() -> bool:
	return false
