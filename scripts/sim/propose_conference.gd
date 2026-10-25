class_name ProposeConference
extends Command
## `from` and the partners it names (nations on its side at war with `to`) propose peace to `to` together (see
## Conference). `demands` are `from`'s own; each partner asks what its own goal and score pay for.

var from: String
var to: String
var demands: Array
var partners: Array
var result: Dictionary = {}


func _init(p_from := "", p_to := "", p_demands := [], p_partners := []) -> void:
	from = p_from
	to = p_to
	demands = p_demands
	partners = p_partners


func execute(gs: Node) -> bool:
	result = Conference.propose(gs, from, to, demands, partners)
	return result.ok


func to_dict() -> Dictionary:
	return {"type": "ProposeConference", "from": from, "to": to, "demands": demands, "partners": partners}
