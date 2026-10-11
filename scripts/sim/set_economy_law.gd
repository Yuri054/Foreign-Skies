class_name SetEconomyLaw
extends Command
## Puts a nation under an economy law (civilian economy, early mobilization, war economy, total
## mobilization). Each has requirements, and a higher law than the one in force can be taken only
## some days after the last change (see Economy.law_problem). A lower law is always allowed.

var tag: String
var law: String
## Why it was refused, for the interface.
var reason := ""


func _init(p_tag := "", p_law := "") -> void:
	tag = p_tag
	law = p_law


func execute(gs: Node) -> bool:
	reason = ""
	var n: Nation = gs.nations.get(tag)
	if n == null:
		reason = "Unknown nation."
		return false
	var ids := Economy.law_ids()
	if law in ids and ids.find(law) < ids.find(n.economy_law):
		reason = Economy.law_requirement(gs, tag, law)
	else:
		reason = Economy.law_problem(gs, tag, law)
	if not reason.is_empty():
		return false
	n.economy_law = law
	n.law_changed_day = Clock.days_elapsed
	return true


func to_dict() -> Dictionary:
	return {"type": "SetEconomyLaw", "tag": tag, "law": law}
