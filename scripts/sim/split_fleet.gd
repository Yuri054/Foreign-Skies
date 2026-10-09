class_name SplitFleet
extends Command
## Detaches some of a fleet's ships (by their position in the fleet) into a new fleet that
## stands where it does.

var tag: String
var fleet_id: int
var ship_indices: Array[int]
## Id of the new fleet (filled in by execute).
var new_fleet_id := 0


func _init(p_tag := "", p_fleet := 0, p_indices: Array[int] = []) -> void:
	tag = p_tag
	fleet_id = p_fleet
	ship_indices = p_indices


## Positions of up to `count` ships of one type in a fleet, front of the list first.
static func indices_of_type(f: Fleet, type: String, count: int) -> Array[int]:
	var out: Array[int] = []
	for i in f.ships.size():
		if out.size() >= count:
			break
		if f.ships[i].type == type:
			out.append(i)
	return out


func execute(gs: Node) -> bool:
	var f: Fleet = gs.fleets.get(fleet_id)
	if f == null or f.tag != tag or f.fighting or ship_indices.is_empty() or ship_indices.size() >= f.ships.size():
		return false
	if not Navy.armies_aboard(gs, f).is_empty():
		return false
	var picked: Array[Ship] = []
	for i in ship_indices:
		if i < 0 or i >= f.ships.size() or picked.has(f.ships[i]):
			return false
		picked.append(f.ships[i])
	var detachment := Navy.new_fleet(gs, tag, "%s detachment" % f.display_name, f.port)
	for s in picked:
		f.ships.erase(s)
		detachment.ships.append(s)
	detachment.zone = f.zone
	detachment.mission = f.mission
	# The detachment keeps the parent's orders.
	detachment.path = f.path.duplicate()
	detachment.dest_port = f.dest_port
	detachment.entering = f.entering
	detachment.move_days_left = f.move_days_left
	new_fleet_id = detachment.id
	gs.fleets_changed.emit()
	return true


func to_dict() -> Dictionary:
	return {"type": "SplitFleet", "tag": tag, "fleet": fleet_id, "ships": ship_indices}


func changes_economy() -> bool:
	return false
