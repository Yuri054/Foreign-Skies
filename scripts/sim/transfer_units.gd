class_name TransferUnits
extends Command
## Moves some of an army's units (by their position in the army) into another army of the same
## nation that stands in the same province. An army left with no units is dissolved: its general
## goes back to the pool and its group and front forget it. Armies in a battle or aboard ship
## take no part.

var tag: String
var from_id: int
var unit_indices: Array[int]
var to_id: int


func _init(p_tag := "", p_from := 0, p_indices: Array[int] = [], p_to := 0) -> void:
	tag = p_tag
	from_id = p_from
	unit_indices = p_indices
	to_id = p_to


## Why the move cannot be made, or "": the same wording the menu shows.
static func block(gs: Node, from: Army, to: Army) -> String:
	if from == null or to == null or from == to or from.tag != to.tag:
		return "not possible"
	if from.province != to.province:
		return "not in the same province"
	if from.embarked() or to.embarked():
		return "aboard ship"
	if from.fighting or to.fighting:
		return "in a battle"
	return ""


func execute(gs: Node) -> bool:
	var from: Army = gs.armies.get(from_id)
	var to: Army = gs.armies.get(to_id)
	if from == null or from.tag != tag or unit_indices.is_empty() or block(gs, from, to) != "":
		return false
	var picked: Array[Unit] = []
	for i in unit_indices:
		if i < 0 or i >= from.units.size() or picked.has(from.units[i]):
			return false
		picked.append(from.units[i])
	for u in picked:
		from.units.erase(u)
		to.units.append(u)
	to.still_days = mini(to.still_days, from.still_days)
	if from.units.is_empty():
		gs.armies.erase(from.id)
		Military.release_orphan_generals(gs)
		Military.prune_groups(gs)
	gs.armies_changed.emit()
	return true


func to_dict() -> Dictionary:
	return {"type": "TransferUnits", "tag": tag, "from": from_id, "units": unit_indices, "to": to_id}


func changes_economy() -> bool:
	return false
