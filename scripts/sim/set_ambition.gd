class_name SetAmbition
extends Command
## The player sets the nation's ambition (see Ambition), or gives it up with "".

var tag: String
var id: String


func _init(p_tag := "", p_id := "") -> void:
	tag = p_tag
	id = p_id


func execute(gs: Node) -> bool:
	return Ambition.choose(gs, tag, id)


func to_dict() -> Dictionary:
	return {"type": "SetAmbition", "tag": tag, "id": id}


func changes_economy() -> bool:
	return false
