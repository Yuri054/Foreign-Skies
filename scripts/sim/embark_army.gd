class_name EmbarkArmy
extends Command
## Puts an army aboard a fleet that lies in the same port. The fleet must have the transports
## to carry it. An embarked army cannot move, fight or be supplied until it lands.

var tag: String
var army_id: int
var fleet_id: int


func _init(p_tag := "", p_army := 0, p_fleet := 0) -> void:
	tag = p_tag
	army_id = p_army
	fleet_id = p_fleet


func execute(gs: Node) -> bool:
	var a: Army = gs.armies.get(army_id)
	var f: Fleet = gs.fleets.get(fleet_id)
	if not Navy.embark_problem(gs, tag, a, f).is_empty():
		return false
	Military.leave_front(gs, a)
	a.fleet_id = f.id
	a.still_days = 0
	gs.armies_changed.emit()
	return true


func to_dict() -> Dictionary:
	return {"type": "EmbarkArmy", "tag": tag, "army": army_id, "fleet": fleet_id}


func changes_economy() -> bool:
	return false
