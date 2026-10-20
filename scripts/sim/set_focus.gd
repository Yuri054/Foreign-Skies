class_name SetFocus
extends Command
## A nation takes up a national focus (see Focus), or with an empty id drops the one it has.

var tag: String
var focus_id: String
## Why it was refused: a Focus.block reason.
var reason := ""


func _init(p_tag := "", p_id := "") -> void:
	tag = p_tag
	focus_id = p_id


func execute(gs: Node) -> bool:
	reason = ""
	if focus_id.is_empty():
		return Focus.cancel(gs, tag)
	reason = Focus.block(gs, tag, focus_id)
	return reason == "" and Focus.start(gs, tag, focus_id)


func to_dict() -> Dictionary:
	return {"type": "SetFocus", "tag": tag, "focus": focus_id}


func changes_economy() -> bool:
	return false
