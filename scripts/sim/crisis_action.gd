class_name CrisisAction
extends Command
## A nation acts in a crisis (see Crisis): the one asked answers ("yield", "refuse", "mobilize", "appeal"), a third
## nation mediates or backs a side ("mediate", "back_a", "back_b").

var tag: String
var crisis_id: int
var action: String


func _init(p_tag := "", p_crisis_id := 0, p_action := "") -> void:
	tag = p_tag
	crisis_id = p_crisis_id
	action = p_action


func execute(gs: Node) -> bool:
	var c := Crisis.find(gs, crisis_id)
	if c.is_empty():
		return false
	if tag == c.b:
		return Crisis.respond(gs, crisis_id, tag, action)
	return Crisis.act(gs, crisis_id, tag, action)


func to_dict() -> Dictionary:
	return {"type": "CrisisAction", "tag": tag, "crisis": crisis_id, "action": action}
