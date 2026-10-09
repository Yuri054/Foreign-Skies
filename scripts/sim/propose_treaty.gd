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
	var block := Diplomacy.proposal_block(gs, from, to, kind)
	if block != "":
		result = {"ok": false, "reason": block, "accepted": false}
		return false
	var cost := Diplomacy.cost_of("propose", kind)
	if not Diplomacy.can_afford(gs, from, cost):
		result = {"ok": false, "reason": "points", "accepted": false}
		return false
	result = Diplomacy.propose_treaty(gs, from, to, kind)
	if not result.ok:
		return false
	# The effort is spent whether or not they agree; a refusal gives part of it back.
	Diplomacy.spend(gs, from, cost)
	if not result.accepted:
		Diplomacy.gain(gs, from, cost * Diplomacy.cfg.points.refusal_refund)
	return true


func to_dict() -> Dictionary:
	return {"type": "ProposeTreaty", "from": from, "to": to, "kind": kind}
