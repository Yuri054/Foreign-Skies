class_name AssignToFront
extends Command
## Assigns armies to a front (front 0 releases them from whichever front they are in). A detachment stands for its
## army: the whole army is assigned or released.

var tag: String
var front_id: int
var army_ids: Array[int]


func _init(p_tag := "", p_front := 0, p_ids: Array[int] = []) -> void:
	tag = p_tag
	front_id = p_front
	army_ids = p_ids


func execute(gs: Node) -> bool:
	var target: Front = gs.fronts.get(front_id)
	if front_id != 0 and (target == null or target.tag != tag):
		return false
	if army_ids.is_empty():
		return false
	for id in army_ids:
		var a: Army = gs.armies.get(id)
		if a == null or a.tag != tag:
			return false
	var roots: Array[int] = []
	for id in army_ids:
		var root := FrontSolver.root_of(gs, gs.armies[id])
		if root != null and not roots.has(root.id):
			roots.append(root.id)
	for id in roots:
		var a: Army = gs.armies[id]
		Military.leave_front(gs, a)
		if target != null:
			a.front_id = target.id
			target.army_ids.append(id)
			target.deploying[id] = true
	if target != null:
		target.dirty = true
	gs.fronts_changed.emit()
	return true


func to_dict() -> Dictionary:
	return {"type": "AssignToFront", "tag": tag, "front": front_id, "armies": army_ids}


func changes_economy() -> bool:
	return false
