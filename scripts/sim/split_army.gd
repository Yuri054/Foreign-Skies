class_name SplitArmy
extends Command
## Detaches some of an army's units (by their position in the army) into a new army.

var tag: String
var army_id: int
var unit_indices: Array[int]
## Id of the new army (filled in by execute).
var new_army_id := 0


func _init(p_tag := "", p_army := 0, p_indices: Array[int] = []) -> void:
	tag = p_tag
	army_id = p_army
	unit_indices = p_indices


## Positions of up to `count` units of one type in an army, front of the list first.
static func indices_of_type(a: Army, type: String, count: int) -> Array[int]:
	var out: Array[int] = []
	for i in a.units.size():
		if out.size() >= count:
			break
		if a.units[i].type == type:
			out.append(i)
	return out


func execute(gs: Node) -> bool:
	var a: Army = gs.armies.get(army_id)
	if a == null or a.tag != tag or unit_indices.is_empty() or unit_indices.size() >= a.units.size():
		return false
	var picked: Array[Unit] = []
	for i in unit_indices:
		if i < 0 or i >= a.units.size() or picked.has(a.units[i]):
			return false
		picked.append(a.units[i])
	var detachment := Military.new_army(gs, tag, "%s detachment" % a.display_name, a.province)
	for u in picked:
		a.units.erase(u)
		detachment.units.append(u)
	detachment.still_days = a.still_days
	detachment.attacking = a.attacking
	new_army_id = detachment.id
	gs.armies_changed.emit()
	return true


func to_dict() -> Dictionary:
	return {"type": "SplitArmy", "tag": tag, "army": army_id, "units": unit_indices}
