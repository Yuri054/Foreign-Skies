class_name MoveArmy
extends Command
## Orders an army to a province, by the cheapest route it may take.

var tag: String
var army_id: int
var destination: int
## The route the order found (filled in by execute).
var path: Array[int] = []


func _init(p_tag := "", p_army := 0, p_destination := 0) -> void:
	tag = p_tag
	army_id = p_army
	destination = p_destination


func execute(gs: Node) -> bool:
	var a: Army = gs.armies.get(army_id)
	if a == null or a.tag != tag or destination < 1 or destination >= gs.province_owner.size():
		return false
	if destination == a.province:
		Military.leave_front(gs, a)
		# Moving to where it stands cancels the order.
		a.path.clear()
		return true
	path = Military.find_path(gs, tag, a.speed(), a.province, destination)
	if path.is_empty():
		return false
	# A hand-given order takes the army off its front.
	Military.leave_front(gs, a)
	# Keep the progress already made if the army is still heading into the same province.
	if a.path.is_empty() or a.path[0] != path[0]:
		a.move_days_left = Military.move_days(gs, tag, a.speed(), a.province, path[0])
	a.path = path.duplicate()
	a.still_days = 0
	gs.armies_changed.emit()
	return true


func to_dict() -> Dictionary:
	return {"type": "MoveArmy", "tag": tag, "army": army_id, "destination": destination}


func changes_economy() -> bool:
	return false
