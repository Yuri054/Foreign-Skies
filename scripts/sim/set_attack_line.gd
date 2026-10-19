class_name SetAttackLine
extends Command
## Starts or stops an attack line (the button). Starting needs the war to exist; stopping halts
## the armies on the march and sends them back to the front.

var tag: String
var line_id: int
var active: bool


func _init(p_tag := "", p_line := 0, p_active := true) -> void:
	tag = p_tag
	line_id = p_line
	active = p_active


func execute(gs: Node) -> bool:
	var line: AttackLine = gs.attack_lines.get(line_id)
	if line == null or line.tag != tag or line.active == active:
		return false
	if active:
		if AttackLines.block(gs, line) != "":
			return false
		line.active = true
		line.wait = 0
	else:
		AttackLines.stop(gs, line)
	gs.armies_changed.emit()
	return true


func to_dict() -> Dictionary:
	return {"type": "SetAttackLine", "tag": tag, "line": line_id, "active": active}


func changes_economy() -> bool:
	return false
