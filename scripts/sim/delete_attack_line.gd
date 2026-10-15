class_name DeleteAttackLine
extends Command
## Removes an attack line, stopping it first if it is running.

var tag: String
var line_id: int


func _init(p_tag := "", p_line := 0) -> void:
	tag = p_tag
	line_id = p_line


func execute(gs: Node) -> bool:
	var line: AttackLine = gs.attack_lines.get(line_id)
	if line == null or line.tag != tag:
		return false
	if line.active:
		AttackLines.stop(gs, line)
	gs.attack_lines.erase(line_id)
	gs.armies_changed.emit()
	return true


func to_dict() -> Dictionary:
	return {"type": "DeleteAttackLine", "tag": tag, "line": line_id}


func changes_economy() -> bool:
	return false
