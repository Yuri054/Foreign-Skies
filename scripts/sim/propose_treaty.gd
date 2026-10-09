class_name ProposeTreaty
extends Command
## `from` proposes a treaty to `to`: an alliance, a non-aggression pact, a guarantee of `to`
## by `from`, or passage for `from`'s armies through `to`'s land. The command succeeds when
## the proposal was valid; `result.accepted` says whether the other nation agreed.

var from: String
var to: String
var kind: String
var result: Dictionary = {}


func _init(p_from := "", p_to := "", p_kind := "") -> void:
	from = p_from
	to = p_to
	kind = p_kind


func execute(gs: Node) -> bool:
	result = Diplomacy.propose_treaty(gs, from, to, kind)
	return result.ok


func to_dict() -> Dictionary:
	return {"type": "ProposeTreaty", "from": from, "to": to, "kind": kind}
