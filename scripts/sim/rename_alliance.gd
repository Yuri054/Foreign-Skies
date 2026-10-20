class_name RenameAlliance
extends Command
## A member renames the alliance it belongs to (a name made in play, not a historic bloc).

var tag: String
var alliance_name: String


func _init(p_tag := "", p_name := "") -> void:
	tag = p_tag
	alliance_name = p_name


func execute(gs: Node) -> bool:
	return gs.nations.has(tag) and Diplomacy.rename_alliance(gs, tag, alliance_name)


func to_dict() -> Dictionary:
	return {"type": "RenameAlliance", "tag": tag, "name": alliance_name}


func changes_economy() -> bool:
	return false
