class_name DesignateFront
extends Command
## Draws a front: a named line of adjacent provinces. Armies are assigned separately.

var tag: String
var front_name: String
var provinces: Array[int]
## For a border front: the nation it faces (the line is then worked out, not given).
var against: String
## "line" or "garrison" (provinces picked one by one, of the nation's own, not joined).
var kind := "line"
## For a border front: hold only the stretch of the border nearest to this province (0: all of it).
var anchor := 0
## Id of the new front (filled in by execute).
var front_id := 0


func _init(p_tag := "", p_name := "", p_provinces: Array[int] = [], p_against := "", p_kind := "line", p_anchor := 0) -> void:
	anchor = p_anchor
	tag = p_tag
	front_name = p_name
	provinces = p_provinces
	against = p_against
	kind = p_kind


## Why the line is not valid, or "" if it is.
static func problem(gs: Node, p_tag: String, line: Array[int], p_against := "", p_kind := "line") -> String:
	if p_kind == "garrison":
		if not gs.nations.has(p_tag) or line.is_empty():
			return "Pick the provinces to guard."
		for p in line:
			if p < 1 or p >= gs.province_owner.size() or gs.province_controller[p] != p_tag:
				return "A garrison guards provinces you hold."
		return ""
	if not p_against.is_empty():
		if not gs.nations.has(p_tag) or not gs.nations.has(p_against) or p_against == p_tag:
			return "Choose another nation to face."
		if Military.border_provinces(gs, p_tag, p_against).is_empty():
			return "You share no border with %s." % gs.nations[p_against].display_name
		return ""
	if not gs.nations.has(p_tag) or line.is_empty():
		return "A front needs at least one province."
	for i in line.size():
		if line[i] < 1 or line[i] >= gs.province_owner.size():
			return "Unknown province."
		if i > 0 and not Military.neighbors(line[i - 1]).has(line[i]):
			return "The provinces of a front must border each other."
	return ""


func execute(gs: Node) -> bool:
	if not problem(gs, tag, provinces, against, kind).is_empty():
		return false
	var f := Front.new()
	f.id = gs.next_front_id
	gs.next_front_id += 1
	f.tag = tag
	f.display_name = front_name
	if f.display_name.is_empty():
		f.display_name = "Front vs %s" % gs.nations[against].display_name if not against.is_empty() else ("Garrison %d" if kind == "garrison" else "Front %d") % f.id
	f.against = against
	f.kind = kind
	f.anchor = anchor if not against.is_empty() else 0
	f.provinces = Military.border_stretch(Military.border_provinces(gs, tag, against), f.anchor) if not against.is_empty() else provinces.duplicate()
	# The player's armies spread their divisions along the line (FrontSolver); the AI's hold a province each.
	f.spread = tag == gs.player_tag
	gs.fronts[f.id] = f
	front_id = f.id
	gs.fronts_changed.emit()
	return true


func to_dict() -> Dictionary:
	return {"type": "DesignateFront", "tag": tag, "name": front_name, "provinces": provinces, "against": against, "kind": kind, "anchor": anchor}


func changes_economy() -> bool:
	return false
