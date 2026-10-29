class_name SetTraining
extends Command
## Puts armies on exercise or takes them off (the Train button): standing still, their divisions gain experience and
## their men cost more upkeep (military.json training). A detachment stands for its army.

var tag: String
var army_ids: Array[int]
var on: bool


func _init(p_tag := "", p_armies: Array[int] = [], p_on := true) -> void:
	tag = p_tag
	army_ids = p_armies
	on = p_on


func execute(gs: Node) -> bool:
	var changed := false
	for id in army_ids:
		var a: Army = gs.armies.get(id)
		if a == null or a.tag != tag:
			continue
		var root := FrontSolver.root_of(gs, a)
		if root.training != on:
			root.training = on
			changed = true
	if not changed:
		return false
	Military.refresh_men(gs)
	gs.armies_changed.emit()
	return true


func to_dict() -> Dictionary:
	return {"type": "SetTraining", "tag": tag, "armies": army_ids, "on": on}
