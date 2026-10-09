class_name SetProgram
extends Command
## Switches a national program (see "programs" in data/economy.json) on or off.

var tag: String
var program: String
var enabled: bool


func _init(p_tag := "", p_program := "", p_enabled := true) -> void:
	tag = p_tag
	program = p_program
	enabled = p_enabled


func execute(gs: Node) -> bool:
	var n: Nation = gs.nations.get(tag)
	if n == null or not Economy.cfg.programs.has(program) or program.begins_with("_"):
		return false
	if enabled:
		n.programs[program] = true
	else:
		n.programs.erase(program)
	return true


func to_dict() -> Dictionary:
	return {"type": "SetProgram", "tag": tag, "program": program, "enabled": enabled}
