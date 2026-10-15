class_name CreateAttackLine
extends Command
## Draws an attack line for an army group against an enemy, optionally tied to a front. A group
## has at most one line; the line starts switched off (SetAttackLine).

var tag: String
var group_id: int
var enemy: String
var front_id: int
var line_id := 0


func _init(p_tag := "", p_group := 0, p_enemy := "", p_front := 0) -> void:
	tag = p_tag
	group_id = p_group
	enemy = p_enemy
	front_id = p_front


func execute(gs: Node) -> bool:
	var group: ArmyGroup = gs.army_groups.get(group_id)
	if group == null or group.tag != tag or enemy == tag or not gs.nations.has(enemy):
		return false
	if AttackLines.of_group(gs, group_id) != null:
		return false
	if front_id != 0:
		var f: Front = gs.fronts.get(front_id)
		if f == null or f.tag != tag:
			return false
	line_id = AttackLines.create(gs, tag, group, enemy, front_id).id
	gs.armies_changed.emit()
	return true


func to_dict() -> Dictionary:
	return {"type": "CreateAttackLine", "tag": tag, "group": group_id, "enemy": enemy, "front": front_id}


func changes_economy() -> bool:
	return false
